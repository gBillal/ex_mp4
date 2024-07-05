defmodule ExMP4.FWriter do
  @moduledoc """
  Module responsible for writing fragmented MP4.
  """

  alias ExMP4.Box.{FileType, Movie, MediaData, MovieExtendsBox, MovieFragment}
  alias ExMP4.{Container, Track}
  alias ExMP4.Track.{Fragment, SampleTable}

  @mdat_header_size 8

  @type t :: %__MODULE__{
          writer_mod: module(),
          writer_state: term(),
          tracks: %{integer() => Track.t()},
          current_fragments: %{integer() => Fragment.t()},
          fragments_data: %{integer() => [binary()]},
          sequence_number: integer(),
          base_data_offset: integer(),
          ftyp_box_size: integer(),
          movie_box: Container.t() | nil
        }

  @typedoc """
  Options to supply when creating the writer.
  """
  @type new_opts :: [
          major_brand: binary(),
          compatible_brands: [binary()],
          major_brand_version: integer(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),
          duration: integer() | boolean()
        ]

  defstruct writer_mod: nil,
            writer_state: nil,
            tracks: %{},
            current_fragments: %{},
            fragments_data: %{},
            sequence_number: 0,
            base_data_offset: 0,
            ftyp_box_size: 0,
            movie_box: nil

  @doc """
  Create a new mp4 writer that writes to filesystem.

  The tracks are assigned an id starting from 1.

  The following options can be provided:
    * `major_brand` - Set the major brand
    * `compatible_brands` - Set the compatible brands
    * `creation_time` - Set the creation time
    * `modification_time` - Set the modification time
    * `duration` - Set the total duration if known. The value can be `true`, `false` or an integer.

      If `true`, the total duration of the presentation is calculated when closing the `writer` and the `mehd` box is
      set to include the fragment duration. Note that this needs the output target to support seeking (not suitable for live streaming.)

      If `false`, the total duration is not calculated and the `mehd` box is not included. This is suitable for real time or
      for presentations where the total duration is not available.

      If an integer, it's the total duration in the `movie` timescale and it'll be set in the `mehd` box.

  The last argument is an optional module implementing `ExMP4.FragDataWriter`.
  """
  @spec new(Path.t(), [ExMP4.Track.t()], new_opts(), module()) :: {:ok, t()} | {:error, term()}
  def new(filename, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    do_new_writer(filename, module, tracks, opts)
  end

  @doc """
  The same as `new/2`, but raises if it fails.
  """
  @spec new!(Path.t(), [ExMP4.Track.t()], new_opts(), module()) :: t()
  def new!(filepath, tracks, opts \\ [], module \\ ExMP4.FragDataWriter.File) do
    case new(filepath, tracks, opts, module) do
      {:ok, writer} -> writer
      {:error, reason} -> raise "could not open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Create a new empty fragment.

  After adding samples, the fragment should be flashed, with `flush_fragment/1`.
  """
  @spec create_fragment(t()) :: t()
  def create_fragment(%{tracks: tracks} = writer) do
    track_ids = Map.keys(tracks)

    fragments =
      Map.new(track_ids, &{&1, Fragment.new(&1, base_media_decode_time: tracks[&1].duration)})

    data = Enum.reduce(track_ids, writer.fragments_data, &Map.put(&2, &1, []))

    %{
      writer
      | current_fragments: fragments,
        fragments_data: data,
        sequence_number: writer.sequence_number + 1
    }
  end

  @doc """
  Write a sample to the current fragment.
  """
  @spec write_sample(t(), ExMP4.Sample.t()) :: t()
  def write_sample(%{current_fragments: fragments} = writer, sample) do
    fragments = Map.update!(fragments, sample.track_id, &Fragment.store_sample(&1, sample))
    fragments_data = Map.update!(writer.fragments_data, sample.track_id, &[sample.payload | &1])

    %{writer | current_fragments: fragments, fragments_data: fragments_data}
  end

  @doc """
  Flush the current fragment.
  """
  @spec flush_fragment(t()) :: t()
  def flush_fragment(%{tracks: tracks} = writer) do
    track_ids = Map.keys(tracks) |> Enum.sort()

    fragments =
      Map.new(writer.current_fragments, fn {track_id, moof} ->
        {track_id, Fragment.flush(moof)}
      end)

    movie_fragment = MovieFragment.assemble(Map.values(fragments), writer.sequence_number)
    movie_fragment_size = Container.serialize!(movie_fragment) |> IO.iodata_length()

    base_data_offset = writer.base_data_offset + movie_fragment_size + @mdat_header_size

    {tracks, base_offsets, base_data_offset} =
      Enum.reduce(
        track_ids,
        {tracks, %{}, base_data_offset},
        fn track_id, {tracks, base_offsets, base_data_offset} ->
          mdat_size =
            writer.fragments_data[track_id]
            |> Stream.map(&byte_size/1)
            |> Enum.sum()

          moof = Fragment.update_base_data_offset(fragments[track_id], base_data_offset)
          base_offsets = Map.put(base_offsets, track_id, base_data_offset)

          tracks =
            Map.update!(
              tracks,
              track_id,
              &Track.add_fragment(&1, moof)
            )

          {tracks, base_offsets, base_data_offset + mdat_size}
        end
      )

    movie_fragment = MovieFragment.update_base_data_offsets(movie_fragment, base_offsets)

    media_data =
      track_ids
      |> Enum.map(&Enum.reverse(writer.fragments_data[&1]))
      |> MediaData.assemble()

    writer.writer_mod.write_fragment(writer.writer_state, [
      Container.serialize!(movie_fragment),
      Container.serialize!(media_data)
    ])

    %{
      writer
      | tracks: tracks,
        current_fragments: %{},
        fragments_data: %{},
        base_data_offset: base_data_offset
    }
  end

  @doc """
  Close the writer.
  """
  @spec close(t()) :: :ok
  def close(writer) do
    if writer.movie_box do
      movie_box =
        writer.tracks
        |> Map.values()
        |> Enum.map(&ExMP4.Helper.timescalify(&1.duration, &1.timescale, ExMP4.movie_timescale()))
        |> Enum.max()
        |> then(&Movie.update_fragment_duration(writer.movie_box, &1))

      writer.writer_mod.write(
        writer.writer_state,
        Container.serialize!(movie_box),
        {:bof, writer.ftyp_box_size}
      )
    end

    writer.writer_mod.close(writer.writer_state)
  end

  defp do_new_writer(input, writer_mod, tracks, opts) do
    with {:ok, writer_state} <- writer_mod.open(input) do
      opts = validate_new_opts(opts)

      tracks =
        tracks
        |> Enum.with_index(1)
        |> Enum.map(fn {track, id} ->
          %{
            track
            | id: id,
              duration: 0,
              sample_count: 0,
              sample_table: %SampleTable{},
              frag_sample_table: %Track.FragmentedSampleTable{}
          }
        end)
        |> Map.new(&{&1.id, &1})

      writer =
        %__MODULE__{
          writer_mod: writer_mod,
          writer_state: writer_state,
          tracks: tracks
        }

      {:ok, write_init_header(writer, opts)}
    end
  end

  defp validate_new_opts(opts) do
    utc_date = DateTime.utc_now()

    Keyword.validate!(opts,
      major_brand: "isom",
      major_brand_version: 512,
      compatible_brands: ["isom", "iso2", "avc1", "mp41", "iso6"],
      creation_time: utc_date,
      modification_time: utc_date,
      duration: false
    )
  end

  defp write_init_header(writer, opts) do
    tracks = Map.values(writer.tracks)
    fragment_duration = fragment_duration(opts[:duration])

    ftyp_box =
      FileType.assemble(opts[:major_brand], opts[:compatible_brands], opts[:major_brand_version])

    movie_box =
      writer.tracks
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Movie.assemble(opts, MovieExtendsBox.assemble(tracks, fragment_duration))

    ftyp_box_data = Container.serialize!(ftyp_box)
    movie_box_data = Container.serialize!(movie_box)

    writer.writer_mod.write_init_header(writer.writer_state, [ftyp_box_data, movie_box_data])

    %{
      writer
      | base_data_offset: IO.iodata_length(ftyp_box_data) + IO.iodata_length(movie_box_data),
        ftyp_box_size: IO.iodata_length(ftyp_box_data),
        movie_box: if(fragment_duration == 0, do: movie_box)
    }
  end

  defp fragment_duration(false), do: nil
  defp fragment_duration(true), do: 0
  defp fragment_duration(duration) when is_integer(duration), do: duration
end
