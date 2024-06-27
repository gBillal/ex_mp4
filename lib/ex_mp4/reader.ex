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
    * `major_brand_version`
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

  alias ExMP4.Container
  alias ExMP4.Container.Header
  alias ExMP4.{Helper, Sample, Track}

  @typedoc """
  Stream options.

    - `tracks` - stream only the specified tracks.
  """
  @type stream_opts :: [tracks: [non_neg_integer()]]

  @typedoc """
  Struct describing
  """
  @type t :: %__MODULE__{
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          major_brand: binary(),
          major_brand_version: integer(),
          compatible_brands: [binary()],
          fragmented?: boolean(),
          creation_time: DateTime.t(),
          modification_time: DateTime.t(),

          # private fields
          reader_mod: module(),
          reader_state: any(),
          tracks: %{non_neg_integer() => Track.t()}
        }

  defstruct [
    :duration,
    :timescale,
    :major_brand,
    :major_brand_version,
    :compatible_brands,
    :fragmented?,
    :creation_time,
    :modification_time,
    :reader_mod,
    :reader_state,
    :tracks
  ]

  @max_header_size 8

  @doc """
  Create a new reader from an mp4 file.
  """
  @spec new(Path.t()) :: {:ok, t()} | {:error, any()}
  def new(filename) do
    do_create_reader(filename, ExMP4.Read.File)
  end

  @doc """
  The same as `new/1`, but raises if it fails.
  """
  @spec new!(Path.t()) :: t()
  def new!(filename) do
    case new(filename) do
      {:ok, reader} -> reader
      {:error, reason} -> raise "could not open reader: #{inspect(reason)}"
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
    track = Map.fetch!(reader.tracks, track_id)
    metadata = Enum.at(track, sample_id)
    sample_data = reader.reader_mod.pread(reader.reader_state, metadata.offset, metadata.size)

    %Sample{
      track_id: track_id,
      dts: metadata.dts,
      pts: metadata.pts,
      sync?: metadata.sync?,
      payload: sample_data
    }
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
  Get samples.
  """
  @spec samples(Enumerable.t(), t()) :: Enumerable.t()
  def samples(metadata_stream, reader) do
    Stream.map(metadata_stream, &do_get_sample(&1, reader))
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
        reader

      data ->
        {:ok, header, rest} = Header.parse(data)

        reader
        |> do_parse_metadata(header, {data, rest})
        |> parse_metadata()
    end
  end

  defp do_parse_metadata(reader, %{name: :ftyp} = header, {data, rest}) do
    [ftyp: box] = read_and_parse_box(reader, header, {data, rest})

    %{
      reader
      | major_brand: box[:fields][:major_brand],
        major_brand_version: box[:fields][:major_brand_version],
        compatible_brands: box[:fields][:compatible_brands]
    }
  end

  defp do_parse_metadata(reader, %{name: :moov} = header, {data, rest}) do
    box = read_and_parse_box(reader, header, {data, rest})
    mvhd = Container.get_box(box, [:moov, :mvhd])

    reader =
      reader
      |> fragmented?(box)
      |> get_tracks(box)

    %{
      reader
      | duration: mvhd[:fields][:duration],
        timescale: mvhd[:fields][:timescale],
        creation_time: DateTime.add(ExMP4.base_date(), mvhd[:fields][:creation_time]),
        modification_time: DateTime.add(ExMP4.base_date(), mvhd[:fields][:modification_time])
    }
  end

  defp do_parse_metadata(reader, %{name: :moof} = header, {data, rest}) do
    box = read_and_parse_box(reader, header, {data, rest})

    Keyword.get_values(box[:moof][:children], :traf)
    |> Enum.map(fn traf ->
      tfhd = traf[:children][:tfhd]
      truns = Keyword.get_values(traf[:children], :trun)
      Track.from_moof(reader.tracks[tfhd.fields.track_id], tfhd, truns)
    end)
    |> Map.new(&{&1.id, &1})
    |> then(&%{reader | tracks: &1, duration: max_duration(reader, Map.values(&1))})
  end

  defp do_parse_metadata(reader, header, {_data, rest}) do
    skip(reader, header, rest)
    reader
  end

  defp read_and_parse_box(reader, header, {header_data, rest}) do
    amount_to_read = header.content_size - byte_size(rest)
    box_data = reader.reader_mod.read(reader.reader_state, amount_to_read)
    {box, ""} = Container.parse!(header_data <> box_data)
    box
  end

  defp skip(reader, header, rest) do
    amount_to_skip = header.content_size - byte_size(rest)
    reader.reader_mod.seek(reader.reader_state, {:cur, amount_to_skip})
  end

  defp fragmented?(reader, moov_box) do
    %{reader | fragmented?: not is_nil(get_in(moov_box, [:moov, :children, :mvex]))}
  end

  defp get_tracks(reader, box) do
    tracks =
      box[:moov][:children]
      |> Keyword.get_values(:trak)
      |> Enum.map(&Track.from_trak_box/1)
      |> Map.new(&{&1.id, &1})

    if reader.fragmented? do
      get_in(box, [:moov, :children, :mvex, :children])
      |> Keyword.get_values(:trex)
      |> Enum.map(&Track.from_trex(tracks[&1.fields.track_id], &1))
      |> Map.new(&{&1.id, &1})
      |> then(&%{reader | tracks: &1})
    else
      %{reader | tracks: tracks}
    end
  end

  defp max_duration(reader, tracks) do
    track = Enum.max_by(tracks, & &1.duration)
    ExMP4.Helper.timescalify(track.duration, track.timescale, reader.timescale)
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
    payload = reader.pread(state, metadata.offset, metadata.size)

    %Sample{
      track_id: metadata.track_id,
      dts: metadata.dts,
      pts: metadata.pts,
      sync?: metadata.sync?,
      payload: payload
    }
  end
end
