defmodule ExMP4.Writer do
  @moduledoc """
  This module contains functions to write MP4.
  """

  use Bunch.Access

  alias ExMP4.{Container, Track}
  alias ExMP4.Box.{FileType, MediaData, Movie}

  @type t :: %__MODULE__{
          writer_mod: module(),
          writer_state: any(),
          ftyp_size: integer(),
          tracks: %{non_neg_integer() => Track.t()},
          mdat_size: integer(),
          fast_start: boolean()
        }

  @type new_opts :: [fast_start: boolean()]

  @mdat_header_size 8
  @chunk_duration 1_000

  defstruct [
    :writer_mod,
    :writer_state,
    ftyp_size: 0,
    tracks: %{},
    next_track_id: 1,
    mdat_size: 0,
    fast_start: false
  ]

  @doc """
  Create a new mp4 writer that writes to filesystem.

  The following options can be provided:
    * `fast_start` - Move the `moov` box to the beginning of the file. Defaults to: `false`

  By default the writer writes the data to the file system, this behaviour can be changed by
  providing a module implementing `ExMP4.DataWriter` in the third argument.
  """
  @spec new(Path.t(), new_opts()) :: {:ok, t()} | {:error, reason :: any()}
  def new(filepath, opts \\ [], module \\ ExMP4.DataWriter.File) do
    do_new_writer(filepath, module, opts)
  end

  @doc """
  The same as `new/2`, but raises if it fails.
  """
  @spec new!(Path.t(), new_opts(), module()) :: t()
  def new!(filepath, opts \\ [], module \\ ExMP4.DataWriter.File) do
    case new(filepath, opts, module) do
      {:ok, writer} -> writer
      {:error, reason} -> raise "could not open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Write the mp4 header.

  This function should be called first before adding tracks.
  """
  @spec write_header(t(), Keyword.t()) :: t()
  def write_header(%__MODULE__{} = writer, opts \\ []) do
    [
      compatible_brands: compatible_brands,
      major_brand: major_brand,
      major_brand_version: version
    ] =
      Keyword.validate!(opts,
        major_brand: "isom",
        major_brand_version: 512,
        compatible_brands: ["isom", "iso2", "avc1", "mp41"]
      )
      |> Enum.sort()

    ftyp_box = FileType.assemble(major_brand, compatible_brands, version)
    mdata_box = MediaData.assemble(<<>>)

    ftyp_box_data = Container.serialize!(ftyp_box)
    mdat_box_data = Container.serialize!(mdata_box)

    writer.writer_mod.write(writer.writer_state, [ftyp_box_data, mdat_box_data])

    %__MODULE__{writer | ftyp_size: IO.iodata_length(ftyp_box_data)}
  end

  @doc """
  Add a new track.

  A track is created by instantiating the public fields of `ExMP4.Track`. The
  id is assigned by the writer and it's equals to the index of the track starting
  from `1`. The first track has an id `1`, the second `2`, ...etc.
  """
  @spec add_track(t(), Track.t()) :: t()
  def add_track(%__MODULE__{} = writer, track) do
    track_id = map_size(writer.tracks) + 1

    track = %{
      track
      | id: track_id,
        sample_table: %Track.SampleTable{},
        frag_sample_table: nil,
        movie_duration: 0
    }

    put_in(writer, [:tracks, track_id], track)
  end

  @doc """
  Add multiple tracks.
  """
  @spec add_tracks(t(), [Track.t()]) :: t()
  def add_tracks(%__MODULE__{} = writer, tracks) do
    Enum.reduce(tracks, writer, &add_track(&2, &1))
  end

  @doc """
  Write a sample.
  """
  @spec write_sample(t(), ExMP4.Sample.t()) :: t()
  def write_sample(writer, sample) do
    track = Track.store_sample(track!(writer, sample.track_id), sample)

    chunk_duration =
      track
      |> Track.chunk_duration()
      |> ExMP4.Helper.timescalify(track.timescale, 1_000)

    if chunk_duration >= @chunk_duration do
      flush_chunk(writer, track)
    else
      put_in(writer, [:tracks, track.id], track)
    end
  end

  @doc """
  Write the trailer and close the stream.
  """
  @spec write_trailer(t()) :: :ok
  def write_trailer(%{fast_start: fast_start} = writer, opts \\ []) do
    movie_header_opts =
      Keyword.validate!(opts,
        creation_time: DateTime.utc_now(:second),
        modification_time: DateTime.utc_now(:second)
      )
      |> Enum.sort()

    writer = Enum.reduce(Map.values(writer.tracks), writer, &flush_chunk(&2, &1))

    movie_box =
      writer.tracks
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Movie.assemble(movie_header_opts)

    after_ftyp = {:bof, writer.ftyp_size}
    mdat_total_size = @mdat_header_size + writer.mdat_size

    case fast_start do
      false ->
        writer.writer_mod.write(writer.writer_state, Container.serialize!(movie_box))
        writer.writer_mod.write(writer.writer_state, <<mdat_total_size::32>>, after_ftyp)

      true ->
        movie_box = Movie.adjust_chunk_offsets(movie_box) |> Container.serialize!()

        writer.writer_mod.write(writer.writer_state, <<mdat_total_size::32>>, after_ftyp)
        writer.writer_mod.write(writer.writer_state, movie_box, after_ftyp, true)
    end

    close(writer)
  end

  defp do_new_writer(input, writer_mod, opts) do
    with {:ok, state} <- writer_mod.open(input) do
      writer = %__MODULE__{
        writer_mod: writer_mod,
        writer_state: state,
        fast_start: Keyword.get(opts, :fast_start, false)
      }

      {:ok, writer}
    end
  end

  defp track!(%{tracks: tracks}, track_id) do
    case Map.fetch(tracks, track_id) do
      {:ok, track} ->
        track

      :error ->
        raise "No track found with id: #{inspect(track_id)}"
    end
  end

  defp flush_chunk(writer, track) do
    {chunk_data, track} = Track.flush_chunk(track, chunk_offset(writer))
    writer.writer_mod.write(writer.writer_state, chunk_data)

    writer = put_in(writer, [:tracks, track.id], track)
    %{writer | mdat_size: writer.mdat_size + byte_size(chunk_data)}
  end

  defp chunk_offset(%{ftyp_size: ftyp_size, mdat_size: mdat_size}) do
    ftyp_size + @mdat_header_size + mdat_size
  end

  defp close(%__MODULE__{writer_mod: writer, writer_state: state}), do: writer.close(state)

  defimpl Collectable do
    def into(writer) do
      collector = fn
        writer, {:cont, sample} ->
          ExMP4.Writer.write_sample(writer, sample)

        writer, :done ->
          writer

        _writer, :halt ->
          :ok
      end

      {writer, collector}
    end
  end
end
