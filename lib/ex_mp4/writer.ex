defmodule ExMP4.Writer do
  @moduledoc """
  This module contains functions to write MP4.
  """

  alias ExMP4.{Box, Helper, Track}
  alias ExMP4.Box.{Ftyp, Moov}

  @type t :: %__MODULE__{
          writer_mod: module(),
          writer_state: any(),
          ftyp_size: integer(),
          tracks: %{non_neg_integer() => Track.t()},
          current_chunk: %{non_neg_integer() => {[iodata()], integer()}},
          mdat_size: integer(),
          fast_start: boolean()
        }

  @type new_opts :: [fast_start: boolean()]

  @mdat_header_size 8
  @chunk_duration 1000
  @movie_timescale 1000

  defstruct [
    :writer_mod,
    :writer_state,
    ftyp_size: 0,
    tracks: %{},
    current_chunk: %{},
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
      {:error, reason} -> raise "cannot not open writer: #{inspect(reason)}"
    end
  end

  @doc """
  Get a track by id or type.
  """
  @spec track(t(), integer() | atom()) :: Track.t() | nil
  def track(writer, id_or_type) when is_atom(id_or_type) do
    Map.values(writer.tracks) |> Enum.find(&(&1.type == id_or_type))
  end

  def track(writer, id_or_type) when is_integer(id_or_type) do
    Map.get(writer.tracks, id_or_type)
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
      minor_version: version
    ] =
      Keyword.validate!(opts,
        major_brand: "isom",
        minor_version: 512,
        compatible_brands: ["isom", "iso2", "avc1", "mp41"]
      )
      |> Enum.sort()

    ftyp_box = %Ftyp{
      major_brand: major_brand,
      minor_version: version,
      compatible_brands: compatible_brands
    }

    mdata_box = %ExMP4.Box.Mdat{}

    writer.writer_mod.write(writer.writer_state, [
      Box.serialize(ftyp_box),
      Box.serialize(mdata_box)
    ])

    %__MODULE__{writer | ftyp_size: Box.size(ftyp_box)}
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
        sample_table: new_sample_table(),
        duration: 0
    }

    current_chunk = Map.put(writer.current_chunk, track_id, {[], 0})
    tracks = Map.put(writer.tracks, track_id, track)

    %{writer | tracks: tracks, current_chunk: current_chunk}
  end

  @doc """
  Add multiple tracks.
  """
  @spec add_tracks(t(), [Track.t()]) :: t()
  def add_tracks(%__MODULE__{} = writer, tracks) do
    Enum.reduce(tracks, writer, &add_track(&2, &1))
  end

  @doc """
  Get all the available tracks.
  """
  @spec tracks(t()) :: [Track.t()]
  def tracks(%__MODULE__{} = writer), do: Map.values(writer.tracks)

  @doc """
  Update a track.

  Only the following fields can be updated: `#{Track.updatable_fields() |> Enum.join(" ")}`
  """
  @spec update_track(t(), Track.id(), Keyword.t()) :: t()
  def update_track(%__MODULE__{} = writer, track_id, opts) do
    opts =
      opts
      |> Keyword.take(Track.updatable_fields())
      |> Map.new()

    track = track!(writer, track_id) |> Map.merge(opts)
    %{writer | tracks: Map.put(writer.tracks, track_id, track)}
  end

  @doc """
  Write a sample.
  """
  @spec write_sample(t(), ExMP4.Sample.t()) :: t()
  def write_sample(writer, sample) do
    track = Track.store_sample(track!(writer, sample.track_id), sample)

    current_chunk =
      Map.update!(writer.current_chunk, track.id, fn {data, duration} ->
        duration =
          duration + Helper.timescalify(sample.duration, track.timescale, @movie_timescale)

        {[sample.payload | data], duration}
      end)

    chunk_duration = elem(current_chunk[track.id], 1)

    if chunk_duration >= @chunk_duration do
      flush_chunk(writer, track, current_chunk[track.id])
    else
      tracks = Map.put(writer.tracks, track.id, track)
      %__MODULE__{writer | tracks: tracks, current_chunk: current_chunk}
    end
  end

  @doc """
  Write the trailer and close the stream.
  """
  @spec write_trailer(t()) :: :ok
  def write_trailer(%{fast_start: fast_start} = writer, opts \\ []) do
    [
      creation_time: creation_time,
      modification_time: modification_time
    ] =
      Keyword.validate!(opts,
        creation_time: DateTime.utc_now(:second),
        modification_time: DateTime.utc_now(:second)
      )
      |> Enum.sort()

    writer =
      writer.tracks
      |> Map.values()
      |> Enum.reduce(writer, &flush_chunk(&2, &1, &2.current_chunk[&1.id]))

    trak =
      writer.tracks
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&Track.to_trak(&1, @movie_timescale))

    moov = %Moov{
      mvhd: %Box.Mvhd{
        duration: Enum.map(trak, & &1.tkhd.duration) |> Enum.max(fn -> 0 end),
        timescale: @movie_timescale,
        next_track_id: length(trak) + 1,
        creation_time: creation_time,
        modification_time: modification_time
      },
      trak: trak
    }

    after_ftyp = {:bof, writer.ftyp_size}
    mdat_total_size = @mdat_header_size + writer.mdat_size

    case fast_start do
      false ->
        writer.writer_mod.write(writer.writer_state, Box.serialize(moov))
        writer.writer_mod.write(writer.writer_state, <<mdat_total_size::32>>, after_ftyp)

      true ->
        movie_box = adjust_chunk_offset(moov) |> Box.serialize()

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

  defp flush_chunk(writer, _track, {[], _duration}), do: writer

  defp flush_chunk(writer, track, {data, _duration}) do
    track = Track.flush_chunk(track, chunk_offset(writer))

    chunk_data = Enum.reverse(data)
    chunk_size = IO.iodata_length(chunk_data)

    writer.writer_mod.write(writer.writer_state, chunk_data)

    %{
      writer
      | tracks: Map.put(writer.tracks, track.id, track),
        current_chunk: Map.put(writer.current_chunk, track.id, {[], 0}),
        mdat_size: writer.mdat_size + chunk_size
    }
  end

  defp chunk_offset(%{ftyp_size: ftyp_size, mdat_size: mdat_size}) do
    ftyp_size + @mdat_header_size + mdat_size
  end

  defp close(%__MODULE__{writer_mod: writer, writer_state: state}), do: writer.close(state)

  defp new_sample_table do
    %Box.Stbl{
      ctts: %Box.Ctts{},
      stss: %Box.Stss{},
      stsz: %Box.Stsz{},
      stco: %Box.Stco{}
    }
  end

  defp adjust_chunk_offset(%Moov{} = moov) do
    size = Box.size(moov)

    Map.update!(moov, :trak, fn traks ->
      Enum.map(traks, fn trak ->
        stbl = update_trak_offset(trak.mdia.minf.stbl, size)
        %{trak | mdia: %{trak.mdia | minf: %{trak.mdia.minf | stbl: stbl}}}
      end)
    end)
  end

  defp update_trak_offset(stbl, size) do
    case stbl do
      %{stco: stco} when not is_nil(stco) ->
        %{stbl | stco: %{stco | entries: Enum.map(stco.entries, &(&1 + size))}}

      %{co64: co64} ->
        %{stbl | co64: %{co64 | entries: Enum.map(co64.entries, &(&1 + size))}}
    end
  end

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
