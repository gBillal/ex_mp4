defmodule ExMP4.Track.FragmentedSampleTable.Moof do
  @moduledoc false

  defmodule Run do
    @moduledoc false

    @type t :: %__MODULE__{
            sample_count: non_neg_integer(),
            first_sample_flags: binary(),
            sample_sizes: [pos_integer()],
            sample_durations: [pos_integer()],
            sync_samples: binary(),
            sample_composition_offsets: [pos_integer()],
            first_sample?: boolean()
          }

    defstruct sample_count: 0,
              first_sample_flags: nil,
              sample_sizes: nil,
              sample_durations: nil,
              sync_samples: nil,
              sample_composition_offsets: nil,
              first_sample?: true

    @spec sample_metadata(t()) :: {t(), tuple()}
    def sample_metadata(run) do
      {run, duration} = sample_duration(run)
      {run, size} = sample_size(run)
      {run, sync?} = sync?(run)
      {run, offset} = sample_composition_offset(run)

      {%{run | sample_count: run.sample_count - 1}, {duration, size, sync?, offset}}
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
          base_data_offset: pos_integer(),
          default_sample_description_index: pos_integer() | nil,
          default_sample_size: pos_integer() | nil,
          default_sample_duration: pos_integer() | nil,
          default_sample_flags: integer() | nil,
          runs: [Run.t()]
        }

  defstruct base_data_offset: 0,
            default_sample_description_index: nil,
            default_sample_size: nil,
            default_sample_duration: nil,
            default_sample_flags: nil,
            runs: []

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
end
