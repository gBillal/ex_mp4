defmodule ExMP4.Track.FragmentedSampleTable do
  @moduledoc false

  alias ExMP4.Track.Fragment

  @type t :: %__MODULE__{
          default_sample_duration: integer(),
          default_sample_size: integer(),
          default_sample_flags: binary() | nil,
          default_sample_description_id: integer(),
          moofs: [Fragment.t()],
          duration: integer(),
          sample_count: integer(),
          elapsed_duration: integer()
        }

  defstruct default_sample_duration: 0,
            default_sample_size: 0,
            default_sample_flags: nil,
            default_sample_description_id: 0,
            moofs: [],
            duration: 0,
            sample_count: 0,
            elapsed_duration: 0

  @spec next_sample(t()) :: {t(), ExMP4.SampleMetadata.t()}
  def next_sample(%__MODULE__{moofs: [moof | rest]} = frag_table) do
    {moof, {duration, size, sync?, composition_offset}} = Fragment.sample_metadata(moof)

    sample_metadata = %ExMP4.SampleMetadata{
      dts: frag_table.elapsed_duration,
      pts: frag_table.elapsed_duration + composition_offset,
      duration: duration || frag_table.default_sample_duration,
      size: size || frag_table.default_sample_size,
      sync?: sync? || sync?(frag_table.default_sample_flags),
      offset: moof.base_data_offset
    }

    moofs =
      case moof do
        %{runs: []} ->
          rest

        _other ->
          [%{moof | base_data_offset: moof.base_data_offset + sample_metadata.size} | rest]
      end

    {%{
       frag_table
       | moofs: moofs,
         elapsed_duration: frag_table.elapsed_duration + sample_metadata.duration
     }, sample_metadata}
  end

  @spec add_fragment(t(), Fragment.t()) :: t()
  def add_fragment(sample_table, fragment) do
    %{
      sample_table
      | moofs: sample_table.moofs ++ [fragment],
        duration: Fragment.duration(fragment, sample_table.default_sample_duration),
        sample_count: Fragment.total_samples(fragment)
    }
  end

  @spec total_size(t()) :: integer()
  def total_size(%{moofs: moofs} = sample_table) do
    Enum.reduce(moofs, 0, &(Fragment.total_size(&1, sample_table.default_sample_size) + &2))
  end

  defp sync?(<<_prefix::15, sync::1, _rest::binary>>), do: sync == 0
  defp sync?(_flags), do: false
end
