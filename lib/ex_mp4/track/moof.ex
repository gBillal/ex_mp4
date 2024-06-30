defmodule ExMP4.Track.Moof do
  @moduledoc false
  alias ExMP4.Track.Moof

  defmodule Run do
    @moduledoc false

    @type t :: %__MODULE__{
            sample_count: integer(),
            first_sample_flags: bitstring() | nil,
            sample_sizes: [integer()] | nil,
            sample_durations: [integer()] | nil,
            sync_samples: bitstring() | nil,
            sample_composition_offsets: [integer()] | nil,
            first_sample?: boolean(),
            last_dts: integer() | nil
          }

    defstruct sample_count: 0,
              first_sample_flags: nil,
              sample_sizes: nil,
              sample_durations: nil,
              sync_samples: nil,
              sample_composition_offsets: nil,
              first_sample?: true,
              last_dts: nil

    @spec sample_metadata(t()) :: {t(), tuple()}
    def sample_metadata(run) do
      {run, duration} = sample_duration(run)
      {run, size} = sample_size(run)
      {run, sync?} = sync?(run)
      {run, offset} = sample_composition_offset(run)

      {%{run | sample_count: run.sample_count - 1}, {duration, size, sync?, offset}}
    end

    @spec store_sample(t(), ExMP4.Sample.t()) :: t()
    def store_sample(run, sample) do
      sync = if sample.sync?, do: 0, else: 1

      durations =
        case run.sample_durations do
          [] ->
            [0]

          [_duration | durations] ->
            # we update the duration of the last sample and
            # make the current sample have the same duration
            dur = sample.dts - run.last_dts
            [dur, dur | durations]
        end

      %{
        run
        | sample_count: run.sample_count + 1,
          sample_sizes: [byte_size(sample.payload) | run.sample_sizes],
          sample_composition_offsets: [sample.pts - sample.dts | run.sample_composition_offsets],
          sync_samples: <<run.sync_samples::bitstring, sync::1>>,
          sample_durations: durations,
          last_dts: sample.dts
      }
    end

    defp sample_duration(%{sample_durations: nil} = run), do: {run, nil}

    defp sample_duration(%{sample_durations: [duration | rest]} = run) do
      {%{run | sample_durations: rest}, duration}
    end

    defp sample_size(%{sample_sizes: nil} = run), do: {run, nil}

    defp sample_size(%{sample_sizes: [size | rest]} = run),
      do: {%{run | sample_sizes: rest}, size}

    defp sync?(%{first_sample_flags: <<sync::1, _rest::bitstring>>, first_sample?: true} = run) do
      {%{run | first_sample?: false}, sync == 0}
    end

    defp sync?(%{sync_samples: <<sync::1, rest::bitstring>>} = run) do
      {%{run | sync_samples: rest}, sync == 0}
    end

    defp sync?(run), do: {run, false}

    defp sample_composition_offset(%{sample_composition_offsets: nil} = run), do: {run, 0}

    defp sample_composition_offset(%{sample_composition_offsets: [offset | rest]} = run) do
      {%{run | sample_composition_offsets: rest}, offset}
    end
  end

  @type t :: %__MODULE__{
          base_data_offset: integer(),
          default_sample_description_index: pos_integer() | nil,
          default_sample_size: pos_integer() | nil,
          default_sample_duration: pos_integer() | nil,
          default_sample_flags: integer() | nil,
          runs: [Run.t()],
          current_run: Run.t() | nil
        }

  defstruct base_data_offset: 0,
            default_sample_description_index: nil,
            default_sample_size: nil,
            default_sample_duration: nil,
            default_sample_flags: nil,
            runs: [],
            current_run: nil

  @spec new() :: t()
  def new() do
    %Moof{
      current_run: %Run{
        sample_composition_offsets: [],
        sample_durations: [],
        sample_sizes: [],
        sync_samples: <<>>
      }
    }
  end

  @spec store_sample(t(), ExMP4.Sample.t()) :: t()
  def store_sample(%{current_run: run} = moof, sample) do
    %{moof | current_run: Run.store_sample(run, sample)}
  end

  @spec flush(t()) :: t()
  def flush(moof) do
    moof
    |> maybe_remove_composition_offsets()
    |> maybe_set_default_sample_duration()
    |> maybe_set_default_sample_size()
    |> then(&%{&1 | runs: &1.runs ++ [&1.current_run], current_run: nil})
  end

  @spec duration(t(), integer() | nil) :: integer()
  def duration(moof, default_duration) do
    Enum.reduce(moof.runs, 0, fn
      %{sample_durations: nil} = run, total ->
        total + run.sample_count * (moof.default_sample_duration || default_duration)

      %{sample_durations: durations}, total ->
        total + Enum.sum(durations)
    end)
  end

  @spec total_samples(t()) :: integer()
  def total_samples(moof), do: Enum.reduce(moof.runs, 0, &(&1.sample_count + &2))

  @spec total_size(t(), integer() | nil) :: integer()
  def total_size(moof, default_size) do
    Enum.reduce(moof.runs, 0, fn
      %{sample_sizes: nil} = run, total ->
        total + run.sample_count * (moof.default_sample_size || default_size)

      %{sample_sizes: sizes}, total ->
        total + Enum.sum(sizes)
    end)
  end

  @spec update_base_data_offset(t(), integer()) :: t()
  def update_base_data_offset(moof, offset), do: %{moof | base_data_offset: offset}

  @doc false
  def sample_metadata(%__MODULE__{runs: [run | rest]} = moof) do
    {run, {duration, size, sync?, composition_offset}} = Run.sample_metadata(run)

    metadata = {
      duration || moof.default_sample_duration,
      size || moof.default_sample_size,
      sync? || sync?(moof.default_sample_flags),
      composition_offset
    }

    moof =
      case run do
        %{sample_count: 0} -> %{moof | runs: rest}
        run -> %{moof | runs: [run | rest]}
      end

    {moof, metadata}
  end

  @spec add_run(
          t(),
          pos_integer(),
          binary() | nil,
          [pos_integer()] | nil,
          [pos_integer()] | nil,
          binary() | nil,
          [pos_integer()] | nil
        ) :: t()
  def add_run(moof, count, first_sample_flags, durations, sizes, sync, composition_offsets) do
    run = %Run{
      sample_count: count,
      first_sample_flags: first_sample_flags,
      sample_durations: durations,
      sample_sizes: sizes,
      sync_samples: sync,
      sample_composition_offsets: composition_offsets
    }

    %{moof | runs: moof.runs ++ [run]}
  end

  defp sync?(<<_prefix::15, sync::1, _rest::binary>>), do: sync == 0
  defp sync?(_flags), do: false

  defp maybe_remove_composition_offsets(%{current_run: run} = moof) do
    run =
      if Enum.all?(run.sample_composition_offsets, &(&1 == 0)),
        do: %{run | sample_composition_offsets: nil},
        else: %{run | sample_composition_offsets: Enum.reverse(run.sample_composition_offsets)}

    %{moof | current_run: run}
  end

  defp maybe_set_default_sample_duration(%{current_run: run} = moof) do
    durations = Enum.reverse(run.sample_durations)
    duration = hd(durations)

    if Enum.all?(durations, &(&1 == duration)) do
      %{moof | default_sample_duration: duration, current_run: %{run | sample_durations: nil}}
    else
      %{moof | current_run: %{run | sample_durations: durations}}
    end
  end

  defp maybe_set_default_sample_size(%{current_run: run} = moof) do
    sizes = Enum.reverse(run.sample_sizes)
    size = hd(sizes)

    if Enum.all?(sizes, &(&1 == size)) do
      %{moof | default_sample_size: size, current_run: %{run | sample_sizes: nil}}
    else
      %{moof | current_run: %{run | sample_sizes: sizes}}
    end
  end
end
