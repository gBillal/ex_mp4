defmodule ExMP4.Reader do
  @moduledoc """
  This module contains function to read mp4 sources.

  The following fields are public:

    * `duration` - The duration of the mp4 mapped in `:timescale` unit.
    * `timescale` - The timescale of the mp4.
    * `fragmented?` - The MP4 file is fragmented.
    * `creation_time` - Creation date time of the presentation.
    * `modification_time` - Modification date time of the presentation.
    * `major_brand`
    * `minor_version`
    * `compatible_brands`


  ## Examples

      # Read a file
      {:ok, reader} = ExMP4.Reader.new("some_mp4_file.mp4")

      IO.inspect("Duration: \#{reader.duration}")
      IO.inspect("Timescale: \#{reader.timescale}")
      IO.inspect("Major Brand: \#{reader.major_brand}")

      # Get tracks information
      for track <- ExMP4.Reader.tracks(reader) do
        IO.inspect("Track information :")
        IO.inspect("====================")
        IO.inspect("  Id: \#{track.id}")
        IO.inspect("  Type: \#{track.type}")
        IO.inspect("  Media: \#{track.media}")
        IO.inspect("  Duration: \#{track.duration}")
        IO.inspect("  Timescale: \#{track.timescale}")
        IO.inspect("")
      end

      # Read samples from the first track
      track = ExMP4.Reader.tracks(reader) |> List.first()
      Enum.each(0..(track.sample_count - 1), fn sample_id ->
        sample = ExMP4.Reader.read_sample(reader, track.id, sample_id)
        IO.inspect("Size of the sample: \#{byte_size(sample.content)}")
      end)

  ## MP4 Source

  In the last example, the source of the mp4 is a file, to read from other sources (binary, http server, ...etc.), you need to write
  a module that implements the `ExMP4.Read` behaviour.

  """

  alias ExMP4.Box
  alias ExMP4.{Helper, Sample, SampleMetadata, Track}

  @typedoc """
  Stream options.

    - `tracks` - stream only the specified tracks.
  """
  @type stream_opts :: [tracks: [non_neg_integer()]]

  @typedoc """
  Struct describing an MP4 reader.
  """
  @type t :: %__MODULE__{
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          major_brand: binary(),
          minor_version: integer(),
          compatible_brands: [binary()],
          fragmented?: boolean(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),

          # private fields
          reader_mod: module(),
          reader_state: any(),
          tracks: %{non_neg_integer() => Track.t()},
          location: integer()
        }

  defstruct [
    :duration,
    :timescale,
    :major_brand,
    :minor_version,
    :compatible_brands,
    :fragmented?,
    :creation_time,
    :modification_time,
    :reader_mod,
    :reader_state,
    :tracks,
    location: 0
  ]

  @max_header_size 8

  @doc """
  Create a new MP4 reader.

  The input may be a file name, a binary `{:binary, data}` or any other input with
  an module implementing `ExMP4.DataReader` behaviour.
  """
  @spec new(any(), module()) :: {:ok, t()} | {:error, any()}
  def new(input, _module \\ ExMP4.DataReader.File)

  def new({:binary, data}, module) do
    do_create_reader({:binary, data}, module)
  end

  def new(filename, module), do: do_create_reader(filename, module)

  @doc """
  The same as `new/1`, but raises if it fails.
  """
  @spec new!(any(), module()) :: t()
  def new!(filename, module \\ ExMP4.DataReader.File) do
    case new(filename, module) do
      {:ok, reader} -> reader
      {:error, reason} -> raise "cannot open reader: #{inspect(reason)}"
    end
  end

  @doc """
  Get all the available tracks.
  """
  @spec tracks(t()) :: [Track.t()]
  def tracks(reader), do: Map.values(reader.tracks)

  @doc """
  Get the duration of the stream.
  """
  @spec duration(t(), Helper.timescale()) :: non_neg_integer()
  def duration(%__MODULE__{} = reader, unit_or_timescale \\ :millisecond) do
    Helper.timescalify(reader.duration, reader.timescale, unit_or_timescale)
  end

  @doc """
  Read a sample from the specified track.

  The first `sample_id` of any track starts at `0`. The `sample_count` field
  of track provides the total number of samples on the track.

  Retrieving samples by their id is slow since it scans all the metadata to get
  the specified sample, a better approach is to stream all the samples using `stream/2`.
  """
  @spec read_sample(t(), Track.id(), Sample.id()) :: Sample.t()
  def read_sample(%__MODULE__{} = reader, track_id, sample_id) do
    reader.tracks
    |> Map.fetch!(track_id)
    |> Enum.at(sample_id)
    |> do_get_sample(reader)
  end

  @doc """
  Read a sample by providing a sample metadata.
  """
  @spec read_sample(t(), SampleMetadata.t()) :: Sample.t()
  def read_sample(%__MODULE__{} = reader, %SampleMetadata{} = metadata) do
    do_get_sample(metadata, reader)
  end

  @doc """
  Stream the samples' metadata.

  The samples are retrieved ordered by their `dts` value.
  """
  @spec stream(t(), stream_opts()) :: Enumerable.t()
  def stream(reader, opts \\ []) do
    step = fn element, _acc -> {:suspend, element} end

    acc =
      Keyword.get(opts, :tracks, Map.keys(reader.tracks))
      |> Enum.map(fn track_id ->
        track = Map.fetch!(reader.tracks, track_id)
        {track, nil, &Enumerable.reduce(track, &1, step)}
      end)

    Stream.resource(
      fn -> acc end,
      &next_element(&1, []),
      fn _acc -> [] end
    )
  end

  @doc """
  Close the reader and free resources.
  """
  @spec close(t()) :: :ok
  def close(reader), do: reader.reader_mod.close(reader.reader_state)

  defp do_create_reader(input, input_reader) do
    with {:ok, state} <- input_reader.open(input) do
      reader = %__MODULE__{
        reader_mod: input_reader,
        reader_state: state
      }

      {:ok, parse_metadata(reader)}
    end
  end

  defp parse_metadata(%__MODULE__{} = reader) do
    case reader.reader_mod.read(reader.reader_state, @max_header_size) do
      :eof ->
        if reader.fragmented?, do: reverse_trafs(reader), else: reader

      data ->
        {:ok, {box_type, header_size, content_size, rest}} = Box.Utils.try_parse_header(data)

        reader
        |> do_parse_metadata(box_type, content_size, rest)
        |> then(&%{&1 | location: &1.location + header_size + content_size})
        |> parse_metadata()
    end
  end

  defp do_parse_metadata(reader, "ftyp", content_size, rest) do
    ftyp = Box.parse(%Box.Ftyp{}, read_box(reader, content_size, rest))

    %{
      reader
      | major_brand: ftyp.major_brand,
        minor_version: ftyp.minor_version,
        compatible_brands: ftyp.compatible_brands
    }
  end

  defp do_parse_metadata(reader, "moov", content_size, rest) do
    moov = Box.parse(%Box.Moov{}, read_box(reader, content_size, rest))

    tracks =
      moov.trak
      |> Enum.map(&Track.from_trak/1)
      |> Map.new(&{&1.id, &1})

    tracks =
      if moov.mvex do
        Enum.reduce(moov.mvex.trex, tracks, fn trex, tracks ->
          Map.update!(tracks, trex.track_id, &%{&1 | trex: trex})
        end)
      else
        tracks
      end

    %{
      reader
      | duration: moov.mvhd.duration,
        timescale: moov.mvhd.timescale,
        creation_time: moov.mvhd.creation_time,
        modification_time: moov.mvhd.modification_time,
        fragmented?: not is_nil(moov.mvex),
        tracks: tracks
    }
  end

  defp do_parse_metadata(reader, "moof", content_size, rest) do
    moof = Box.parse(%Box.Moof{}, read_box(reader, content_size, rest))

    Enum.reduce(moof.traf, reader.tracks, fn traf, tracks ->
      track_id = traf.tfhd.track_id
      traf_duration = Box.Traf.duration(traf, tracks[track_id].trex)
      sample_count = Box.Traf.sample_count(traf)

      traf =
        if traf.tfhd.base_is_moof?,
          do: %{traf | tfhd: %{traf.tfhd | base_data_offset: reader.location}},
          else: traf

      Map.update!(
        tracks,
        track_id,
        &%{
          &1
          | trafs: [traf | &1.trafs],
            duration: &1.duration + traf_duration,
            sample_count: &1.sample_count + sample_count
        }
      )
    end)
    |> then(&%{reader | tracks: &1, duration: max_duration(reader, Map.values(&1))})
  end

  defp do_parse_metadata(reader, _box_nale, content_size, rest) do
    skip(reader, content_size, rest)
  end

  defp reverse_trafs(reader) do
    Map.update!(reader, :tracks, fn tracks ->
      Map.new(tracks, fn {track_id, track} ->
        {track_id, %{track | trafs: Enum.reverse(track.trafs)}}
      end)
    end)
  end

  defp read_box(reader, content_size, rest) do
    amount_to_read = content_size - byte_size(rest)
    box_data = reader.reader_mod.read(reader.reader_state, amount_to_read)
    rest <> box_data
  end

  defp skip(reader, content_size, rest) do
    amount_to_skip = content_size - byte_size(rest)
    reader.reader_mod.seek(reader.reader_state, {:cur, amount_to_skip})
    reader
  end

  defp max_duration(reader, tracks) do
    tracks
    |> Enum.map(&ExMP4.Helper.timescalify(&1.duration, &1.timescale, reader.timescale))
    |> Enum.max()
  end

  defp next_element([], []), do: {:halt, []}

  defp next_element([], acc) do
    {track, selected_element, _fun} =
      Enum.min_by(acc, & &1, fn {track1, elem1, _fun}, {track2, elem2, _fun2} ->
        dts1 = div(elem1.dts * 1_000, track1.timescale)
        dts2 = div(elem2.dts * 1_000, track2.timescale)
        dts1 <= dts2
      end)

    acc =
      Enum.map(acc, fn {track, element, fun} ->
        case element == selected_element do
          true -> {track, nil, fun}
          false -> {track, element, fun}
        end
      end)

    {[%{selected_element | track_id: track.id}], acc}
  end

  defp next_element([{track, nil, fun} | rest], acc) do
    case fun.({:cont, nil}) do
      {:suspended, element, fun} ->
        next_element(rest, [{track, element, fun} | acc])

      {:done, _acc} ->
        next_element(rest, acc)
    end
  end

  defp next_element([head | rest], acc) do
    next_element(rest, [head | acc])
  end

  defp do_get_sample(metadata, %{reader_mod: reader, reader_state: state}) do
    payload = reader.read(state, metadata.size, metadata.offset)

    %Sample{
      track_id: metadata.track_id,
      dts: metadata.dts,
      pts: metadata.pts,
      duration: metadata.duration,
      sync?: metadata.sync?,
      payload: payload
    }
  end
end
