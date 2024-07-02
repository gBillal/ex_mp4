defmodule ExMP4.Track.Fragment.Run do
  @moduledoc """
  A struct representing a run (`trun` box) in a fragment.
  """

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
      cond do
        not is_nil(sample.duration) ->
          [sample.duration | run.sample_durations]

        Enum.empty?(run.sample_durations) ->
          [0]

        true ->
          # we update the duration of the last sample and
          # make the current sample have the same duration
          duration = sample.dts - run.last_dts
          [duration, duration | tl(run.sample_durations)]
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

  defp sync?(run), do: {run, nil}

  defp sample_composition_offset(%{sample_composition_offsets: nil} = run), do: {run, 0}

  defp sample_composition_offset(%{sample_composition_offsets: [offset | rest]} = run) do
    {%{run | sample_composition_offsets: rest}, offset}
  end
end
