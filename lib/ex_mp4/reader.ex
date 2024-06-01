defmodule ExMP4.Reader do
  @moduledoc """
  This module contains function to read mp4 sources.

  The following fields are public:

    * `duration` - The duration of the mp4 mapped in `:timescale` unit.
    * `timescale` - The timescale of the mp4.
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
  alias ExMP4.{Sample, Track}

  @typedoc """
  Struct describing
  """
  @type t :: %__MODULE__{
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          major_brand: binary(),
          major_brand_version: integer(),
          compatible_brands: [binary()],

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
  Get all the available tracks.
  """
  @spec tracks(t()) :: [Track.t()]
  def tracks(reader), do: Map.values(reader.tracks)

  @doc """
  Get the duration of the stream.
  """
  @spec duration(t()) :: non_neg_integer()
  def duration(%__MODULE__{duration: duration}), do: duration

  @doc """
  Read a sample from the specified track.

  The first `sample_id` of any track starts at `0`. The `sample_count` field
  of track provides the total number of samples on the track.
  """
  @spec read_sample(t(), Track.id(), Sample.id()) :: Sample.t()
  def read_sample(%__MODULE__{} = reader, track_id, sample_id) do
    track = Map.fetch!(reader.tracks, track_id)
    {{dts, pts}, sync?, sample_size, sample_offset} = Track.sample_metadata(track, sample_id)
    sample_data = reader.reader_mod.pread(reader.reader_state, sample_offset, sample_size)

    %Sample{
      dts: dts,
      pts: pts,
      sync?: sync?,
      content: sample_data
    }
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

        reader =
          case header.name do
            :ftyp ->
              [ftyp: box] = read_and_parse_box(reader, header, {data, rest})

              %{
                reader
                | major_brand: box[:fields][:major_brand],
                  major_brand_version: box[:fields][:major_brand_version],
                  compatible_brands: box[:fields][:compatible_brands]
              }

            :moov ->
              box = read_and_parse_box(reader, header, {data, rest})
              mvhd = Container.get_box(box, [:moov, :mvhd])

              %{
                reader
                | duration: mvhd[:fields][:duration],
                  timescale: mvhd[:fields][:timescale],
                  tracks: get_tracks(box)
              }

            _other ->
              skip(reader, header, rest)
              reader
          end

        parse_metadata(reader)
    end
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

  defp get_tracks(box) do
    box[:moov][:children]
    |> Keyword.get_values(:trak)
    |> Enum.map(&Track.new/1)
    |> Map.new(&{&1.id, &1})
  end
end
