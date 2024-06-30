defmodule ExMP4.Track do
  @moduledoc """
  A struct describing an MP4 track.
  """

  alias ExMP4.{Container, Helper}
  alias ExMP4.Track.{FragmentedSampleTable, SampleTable}

  @type id :: non_neg_integer()
  @type box :: %{fields: map(), children: Container.t()}

  @typedoc """
  Struct describing an mp4 track.

  The public fields are:
    * `:id` - the track id
    * `:type` - the type of the media of the track
    * `:media` - the codec used to encode the media.
    * `:media_tag` - the box `name` to use for the `:media`.

        This field is used to indicate the layout of some codec specific data, take for example `H264`,
        `avc1` indicates that parameter sets are included in the sample description and removed from
        the samples themselves.
    * `:priv_data` - private data specific to the contained `:media`.
    * `:duration` - the duration of the track in `:timescale` units.
    * `:timescale` - the timescale used for the track.
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
          media_tag: ExMP4.Container.box_name_t(),
          priv_data: binary() | struct(),
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          sample_rate: non_neg_integer() | nil,
          channels: non_neg_integer() | nil,
          sample_count: non_neg_integer(),

          # private fields
          sample_table: SampleTable.t() | nil,
          frag_sample_table: FragmentedSampleTable.t() | nil,
          movie_duration: integer() | nil
        }

  defstruct [
    :id,
    :type,
    :media,
    :media_tag,
    :duration,
    :width,
    :height,
    :sample_rate,
    :channels,
    :sample_count,
    :sample_table,
    :frag_sample_table,
    :movie_duration,
    priv_data: <<>>,
    timescale: 1000
  ]

  @doc false
  @spec from_trak_box(box()) :: t()
  def from_trak_box(trak), do: ExMP4.Box.Track.unpack(trak)

  @doc false
  @spec from_trex(t(), box()) :: t()
  def from_trex(track, %{fields: fields}) do
    %{
      track
      | frag_sample_table: %FragmentedSampleTable{
          default_sample_description_id: fields.default_sample_duration,
          default_sample_duration: fields.default_sample_duration,
          default_sample_flags: fields.default_sample_flags,
          default_sample_size: fields.default_sample_size
        }
    }
  end

  @doc false
  @spec from_moof(t(), box(), [box()]) :: t()
  def from_moof(track, tfhd, truns) do
    sample_table = FragmentedSampleTable.add_moof(track.frag_sample_table, tfhd, truns)

    %{
      track
      | frag_sample_table: sample_table,
        duration: track.duration + sample_table.duration,
        sample_count: track.sample_count + sample_table.sample_count
    }
  end

  @spec add_fragment(t(), ExMP4.Track.Moof.t()) :: t()
  def add_fragment(track, fragment) do
    sample_table = FragmentedSampleTable.add_moof(track.frag_sample_table, fragment)
    %{track | frag_sample_table: sample_table}
  end

  @doc """
  Create a new track
  """
  @spec new(Keyword.t()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  @doc """
  Get the duration of the track.
  """
  @spec duration(t(), Helper.timescale()) :: integer()
  @spec duration(t()) :: integer()
  def duration(track, unit_or_timescale \\ :millisecond) do
    Helper.timescalify(track.duration, track.timescale, unit_or_timescale)
  end

  @doc """
  Get the bitrate of the track in `bps` (bit per second)
  """
  @spec bitrate(t()) :: non_neg_integer()
  def bitrate(track) do
    total_size =
      case track do
        %{frag_sample_table: nil} -> SampleTable.total_size(track.sample_table)
        _track -> FragmentedSampleTable.total_size(track.frag_sample_table)
      end

    div(total_size * 1000 * 8, duration(track, :millisecond))
  end

  @doc """
  Get the fps (frames per second) of the video track.
  """
  @spec fps(t()) :: number()
  def fps(%{type: :video} = track) do
    track.sample_count * 1_000 / duration(track, :millisecond)
  end

  def fps(_track), do: 0

  @doc false
  @spec store_sample(t(), ExMP4.Sample.t()) :: t()
  def store_sample(track, sample) do
    %{track | sample_table: SampleTable.store_sample(track.sample_table, sample)}
  end

  @doc false
  @spec chunk_duration(t()) :: ExMP4.duration()
  def chunk_duration(%{sample_table: table}), do: SampleTable.chunk_duration(table)

  @doc false
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

  defimpl Enumerable do
    def reduce(track, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(track, &1, fun)}
    end

    def reduce(_track, {:halt, acc}, _fun), do: {:halted, acc}

    # progressive file
    def reduce(%{frag_sample_table: nil, sample_table: table}, {:cont, acc}, _fun)
        when table.sample_index > table.sample_count do
      {:done, acc}
    end

    def reduce(%{frag_sample_table: nil} = track, {:cont, acc}, fun) do
      {sample_table, sample_metadata} = SampleTable.next_sample(track.sample_table)
      sample_metadata = %{sample_metadata | track_id: track.id}
      reduce(%{track | sample_table: sample_table}, fun.(sample_metadata, acc), fun)
    end

    # fragmented file
    def reduce(%{frag_sample_table: %{moofs: []}}, {:cont, acc}, _fun) do
      {:done, acc}
    end

    def reduce(track, {:cont, acc}, fun) do
      {frag_table, sample_metadata} = FragmentedSampleTable.next_sample(track.frag_sample_table)
      sample_metadata = %{sample_metadata | track_id: track.id}
      reduce(%{track | frag_sample_table: frag_table}, fun.(sample_metadata, acc), fun)
    end

    def count(%{sample_count: count}), do: {:ok, count}

    def member?(_enumerable, _element), do: {:error, __MODULE__}

    def slice(_enumerable), do: {:error, __MODULE__}
  end
end
