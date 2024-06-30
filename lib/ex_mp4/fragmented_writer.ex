defmodule ExMP4.FragmentedWriter do
  @moduledoc """
  Module responsible for writing fragmented MP4.
  """

  alias ExMP4.Box.{FileType, Movie, MediaData, MovieExtendsBox, MovieFragment}
  alias ExMP4.{Container, Track}
  alias ExMP4.Track.{Moof, SampleTable}

  @mdat_header_size 8

  @type t :: %__MODULE__{
          writer_mod: module(),
          writer_state: term(),
          tracks: %{integer() => Track.t()},
          current_fragments: %{integer() => Moof.t()},
          fragments_data: %{integer() => [binary()]},
          sequence_number: integer(),
          base_data_offset: integer()
        }

  @type new_opts :: [
          major_brand: binary(),
          compatible_brands: [binary()],
          major_brand_version: integer(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t()
        ]

  defstruct writer_mod: nil,
            writer_state: nil,
            tracks: %{},
            current_fragments: %{},
            fragments_data: %{},
            sequence_number: 0,
            base_data_offset: 0

  @doc """
  Create a new mp4 writer that writes to filesystem.
  """
  @spec new(Path.t(), [ExMP4.Track.t()], new_opts()) :: {:ok, t()} | {:error, term()}
  def new(filename, tracks, opts \\ []) do
    with {:ok, writer} <- do_new_writer(filename, ExMP4.Write.File) do
      opts = validate_new_opts(opts)

      tracks =
        tracks
        |> Enum.map(
          &%{&1 | sample_table: %SampleTable{}, frag_sample_table: %Track.FragmentedSampleTable{}}
        )
        |> Map.new(&{&1.id, &1})

      {:ok, write_init_header(%{writer | tracks: tracks}, opts)}
    end
  end

  @doc """
  The same as `new/2`, but raises if it fails.
  """
  @spec new!(Path.t(), [ExMP4.Track.t()], new_opts()) :: t()
  def new!(filepath, tracks, opts \\ []) do
    case new(filepath, tracks, opts) do
      {:ok, writer} -> writer
      {:error, reason} -> raise "could not open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Create a new empty fragment.

  After adding samples, the fragment should be flashed, with `flush_segment/1`.
  """
  @spec create_fragment(t()) :: t()
  def create_fragment(%{tracks: tracks} = writer) do
    track_ids = Map.keys(tracks)

    fragments = Enum.reduce(track_ids, writer.current_fragments, &Map.put(&2, &1, Moof.new()))
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
    fragments = Map.update!(fragments, sample.track_id, &Moof.store_sample(&1, sample))
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
        {track_id, Moof.flush(moof)}
      end)

    movie_fragment = MovieFragment.assemble(fragments, writer.sequence_number)
    movie_fragment_size = Container.serialize!(movie_fragment) |> byte_size()

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

          moof = Moof.update_base_data_offset(fragments[track_id], base_data_offset)
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
      |> Enum.flat_map(&Enum.reverse(writer.fragments_data[&1]))
      |> Enum.join()
      |> MediaData.assemble()

    write(writer, [Container.serialize!(movie_fragment), Container.serialize!(media_data)])

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
  def close(writer), do: writer.writer_mod.close(writer.writer_state)

  defp do_new_writer(input, writer_mod) do
    with {:ok, reader_state} <- writer_mod.open(input) do
      writer =
        %__MODULE__{
          writer_mod: ExMP4.Write.File,
          writer_state: reader_state
        }

      {:ok, writer}
    end
  end

  defp validate_new_opts(opts) do
    utc_date = DateTime.utc_now()

    Keyword.validate!(opts,
      major_brand: "iso5",
      major_brand_version: 512,
      compatible_brands: ["iso6", "mp41"],
      creation_time: utc_date,
      modification_time: utc_date
    )
  end

  defp write_init_header(writer, opts) do
    tracks = Map.values(writer.tracks)

    ftyp_box =
      FileType.assemble(opts[:major_brand], opts[:compatible_brands], opts[:major_brand_version])

    movie_box =
      writer.tracks
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Movie.assemble(opts, MovieExtendsBox.assemble(tracks))

    ftyp_box_data = Container.serialize!(ftyp_box)
    movie_box_data = Container.serialize!(movie_box)

    write(writer, [ftyp_box_data, movie_box_data])

    %{writer | base_data_offset: byte_size(ftyp_box_data) + byte_size(movie_box_data)}
  end

  defp write(%{writer_mod: writer, writer_state: state}, data), do: writer.write(state, data)
end
