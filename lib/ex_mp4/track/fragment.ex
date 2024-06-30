defmodule ExMP4.Track.Fragment do
  @moduledoc """
  Module representing a movie fragment (`moof`) of a single track.
  """

  alias __MODULE__.Run

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
    %__MODULE__{
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
