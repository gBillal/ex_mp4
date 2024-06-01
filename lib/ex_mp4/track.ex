defmodule ExMP4.Track do
  @moduledoc """
  A struct describing an MP4 track.
  """

  alias ExMP4.{Container, Helper}
  alias ExMP4.Track.SampleTable

  @type id :: non_neg_integer()

  @typedoc """
  Struct describing an mp4 track.

  The public fields are:
    * `:id` - the track id
    * `:type` - the type of the media of the track
    * `:media` - the codec used to encode the media.
    * `:duration` - the duration of the track in `:timescale` units.
    * `:timescale` - the timescale used in the track.
    * `:width` - the width of the video frames.
    * `:height` - the height of the video frames.
    * `:sample_rate` - the sample rate of audio samples.
    * `:channels` - the number of audio channels.
    * `:sample_count` - the total count of samples.
  """
  @type t :: %__MODULE__{
          id: id(),
          type: :video | :audio | :subtitle | :unknown,
          media: :h264 | :h265 | :aac | :opus | :unknown,
          priv_data: binary(),
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          sample_rate: non_neg_integer() | nil,
          channels: non_neg_integer() | nil,
          sample_count: non_neg_integer(),

          # private fields
          sample_table: SampleTable.t() | nil,
          movie_duration: integer() | nil
        }

  defstruct [
    :id,
    :type,
    :media,
    :duration,
    :width,
    :height,
    :sample_rate,
    :channels,
    :sample_count,
    :sample_table,
    :movie_duration,
    priv_data: <<>>,
    timescale: 1000
  ]

  @doc false
  @spec from_trak_box(Container.t()) :: t()
  def from_trak_box(trak), do: ExMP4.Box.Track.unpack(trak)

  @doc """
  Create a new track
  """
  @spec new(Keyword.t()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  @doc false
  @spec sample_metadata(t(), non_neg_integer()) :: tuple()
  def sample_metadata(%{sample_table: sample_table}, sample_id) do
    {
      SampleTable.sample_timestamps(sample_table, sample_id),
      SampleTable.sync?(sample_table, sample_id),
      SampleTable.sample_size(sample_table, sample_id),
      SampleTable.sample_offset(sample_table, sample_id)
    }
  end

  @doc false
  @spec store_sample(t(), ExMP4.Sample.t()) :: t()
  def store_sample(track, sample) do
    %{track | sample_table: SampleTable.store_sample(track.sample_table, sample)}
  end

  @spec chunk_duration(t()) :: ExMP4.duration()
  def chunk_duration(%{sample_table: table}), do: SampleTable.chunk_duration(table)

  @spec flush_chunk(t(), ExMP4.offset()) :: {binary(), t()}
  def flush_chunk(track, chunk_offset) do
    {chunk_data, sample_table} = SampleTable.flush_chunk(track.sample_table, chunk_offset)
    {chunk_data, %{track | sample_table: sample_table}}
  end

  @doc false
  @spec finalize(t(), non_neg_integer()) :: t()
  def finalize(track, movie_timescale) do
    track
    |> put_durations(movie_timescale)
    |> Map.update!(:sample_table, &SampleTable.reverse/1)
  end

  defp put_durations(track, movie_timescale) do
    use Numbers, overload_operators: true

    duration =
      track.sample_table.decoding_deltas
      |> Enum.reduce(0, &(&1.sample_count * &1.sample_delta + &2))

    %{
      track
      | duration: Helper.timescalify(duration, track.timescale, track.timescale),
        movie_duration: Helper.timescalify(duration, track.timescale, movie_timescale)
    }
  end
end
