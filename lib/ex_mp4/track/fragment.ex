defmodule ExMP4.Track.Fragment do
  @moduledoc """
  Module representing a movie fragment (`moof`) of a single track.
  """

  alias __MODULE__.Run
  alias ExMP4.Track

  @type t :: %__MODULE__{
          track_id: Track.id(),
          base_data_offset: integer(),
          default_sample_description_index: pos_integer() | nil,
          default_sample_size: pos_integer() | nil,
          default_sample_duration: pos_integer() | nil,
          default_sample_flags: integer() | nil,
          base_media_decode_time: integer(),
          runs: [Run.t()],
          current_run: Run.t() | nil
        }

  @enforce_keys [:track_id]
  defstruct @enforce_keys ++
              [
                base_data_offset: 0,
                default_sample_description_index: nil,
                default_sample_size: nil,
                default_sample_duration: nil,
                default_sample_flags: nil,
                base_media_decode_time: 0,
                runs: [],
                current_run: nil
              ]

  @spec new(Track.id(), Keyword.t()) :: t()
  def new(track_id, opts \\ []) do
    fragment = struct!(__MODULE__, Keyword.put(opts, :track_id, track_id))

    %__MODULE__{
      fragment
      | current_run: %Run{
          sample_composition_offsets: [],
          sample_durations: [],
          sample_sizes: [],
          sync_samples: <<>>
        }
    }
  end

  @spec store_sample(t(), ExMP4.Sample.t()) :: t()
  def store_sample(%{current_run: run} = fragment, sample) do
    %{fragment | current_run: Run.store_sample(run, sample)}
  end

  @spec flush(t()) :: t()
  def flush(fragment) do
    fragment
    |> maybe_remove_composition_offsets()
    |> maybe_set_default_sample_duration()
    |> maybe_set_default_sample_size()
    |> then(&%{&1 | runs: &1.runs ++ [&1.current_run], current_run: nil})
  end

  @spec duration(t()) :: integer()
  @spec duration(t(), integer() | nil) :: integer()
  def duration(moof, default_duration \\ nil) do
    Enum.reduce(moof.runs, 0, fn
      %{sample_durations: nil} = run, total ->
        total + run.sample_count * (moof.default_sample_duration || default_duration)

      %{sample_durations: durations}, total ->
        total + Enum.sum(durations)
    end)
  end

  @spec total_samples(t()) :: integer()
  def total_samples(fragment), do: Enum.reduce(fragment.runs, 0, &(&1.sample_count + &2))

  @spec total_size(t(), integer() | nil) :: integer()
  def total_size(fragment, default_size) do
    Enum.reduce(fragment.runs, 0, fn
      %{sample_sizes: nil} = run, total ->
        total + run.sample_count * (fragment.default_sample_size || default_size)

      %{sample_sizes: sizes}, total ->
        total + Enum.sum(sizes)
    end)
  end

  @spec update_base_data_offset(t(), integer()) :: t()
  def update_base_data_offset(fragment, offset), do: %{fragment | base_data_offset: offset}

  @doc false
  def sample_metadata(%__MODULE__{runs: [run | rest]} = fragment) do
    {run, {duration, size, sync?, composition_offset}} = Run.sample_metadata(run)

    metadata = {
      duration || fragment.default_sample_duration,
      size || fragment.default_sample_size,
      sync?(sync?, fragment.default_sample_flags),
      composition_offset
    }

    fragment =
      case run do
        %{sample_count: 0} -> %{fragment | runs: rest}
        run -> %{fragment | runs: [run | rest]}
      end

    {fragment, metadata}
  end

  @spec add_run(t(), Run.t()) :: t()
  def add_run(moof, run) do
    %{moof | runs: moof.runs ++ [run]}
  end

  defp sync?(nil, nil), do: nil
  defp sync?(nil, number), do: Bitwise.band(number, 0x10000) == 0
  defp sync?(value, _number), do: value

  defp maybe_remove_composition_offsets(%{current_run: run} = fragment) do
    run =
      if Enum.all?(run.sample_composition_offsets, &(&1 == 0)),
        do: %{run | sample_composition_offsets: nil},
        else: %{run | sample_composition_offsets: Enum.reverse(run.sample_composition_offsets)}

    %{fragment | current_run: run}
  end

  defp maybe_set_default_sample_duration(%{current_run: run} = fragment) do
    durations = Enum.reverse(run.sample_durations)
    duration = hd(durations)

    if Enum.all?(durations, &(&1 == duration)) do
      %{fragment | default_sample_duration: duration, current_run: %{run | sample_durations: nil}}
    else
      %{fragment | current_run: %{run | sample_durations: durations}}
    end
  end

  defp maybe_set_default_sample_size(%{current_run: run} = fragment) do
    sizes = Enum.reverse(run.sample_sizes)
    size = hd(sizes)

    if Enum.all?(sizes, &(&1 == size)) do
      %{fragment | default_sample_size: size, current_run: %{run | sample_sizes: nil}}
    else
      %{fragment | current_run: %{run | sample_sizes: sizes}}
    end
  end
end
