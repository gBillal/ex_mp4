defmodule ExMP4.Box.Traf do
  @moduledoc """
  A module repsenting an `traf` box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.{Box, SampleMetadata}
  alias ExMP4.Box.{Tfdt, Tfhd, Trun}

  @type t :: %__MODULE__{
          tfhd: Tfhd.t(),
          tfdt: Tfdt.t() | nil,
          trun: [Trun.t()]
        }

  defstruct tfhd: %Tfhd{}, tfdt: nil, trun: []

  @doc """
  Get the next sample from the fragment.

  The `trex` argument is the `trex` box that contains global defaults.

  The `duration` refers to the total duration of the extracted samples. This field
  should be updated by the caller and provided in each call.

  It returns a tuple with the first element being the `traf` box after removing
  the sample entry and the second element as the sample metadata.
  """
  @spec next_sample(t(), ExMP4.Box.Trex.t(), integer()) :: {t(), SampleMetadata.t()}
  def next_sample(%{tfhd: tfhd} = traf, trex, duration) do
    [run | runs] = traf.trun
    [entry | entries] = run.entries

    sample_metadata = %SampleMetadata{
      dts: duration,
      pts: duration + (entry.sample_composition_time_offset || 0),
      sync?: sync?(entry, run, tfhd, trex),
      duration:
        entry.sample_duration || tfhd.default_sample_duration || trex.default_sample_duration,
      size: entry.sample_size || tfhd.default_sample_size || trex.default_sample_size,
      offset: tfhd.base_data_offset + run.data_offset
    }

    traf =
      case entries do
        [] ->
          %{traf | trun: runs}

        entries ->
          run = %{
            run
            | data_offset: run.data_offset + sample_metadata.size,
              entries: entries,
              first_sample_flags: nil
          }

          %{traf | trun: [run | runs]}
      end

    {traf, sample_metadata}
  end

  @doc """
  Get the total size of the track fragment.
  """
  @spec total_size(t(), ExMP4.Box.Trex.t()) :: integer()
  def total_size(%{tfhd: tfhd} = traf, trex) do
    Enum.reduce(traf.trun, 0, fn trun, size ->
      if Bitwise.band(trun.flags, 0x200) == 0 do
        size + trun.sample_count * (tfhd.default_sample_size || trex.default_sample_size)
      else
        size + (Enum.map(trun.entries, & &1.sample_size) |> Enum.sum())
      end
    end)
  end

  @doc """
  Get the total duration of the track fragment.
  """
  @spec duration(t(), ExMP4.Box.Trex.t()) :: integer()
  def duration(%{tfhd: tfhd} = traf, trex) do
    Enum.reduce(traf.trun, 0, fn trun, duration ->
      if Bitwise.band(trun.flags, 0x100) == 0 do
        duration +
          trun.sample_count * (tfhd.default_sample_duration || trex.default_sample_duration)
      else
        duration + (Enum.map(trun.entries, & &1.sample_duration) |> Enum.sum())
      end
    end)
  end

  @doc """
  Get the total duration of the track fragment.
  """
  @spec sample_count(t()) :: integer()
  def sample_count(traf) do
    Enum.reduce(traf.trun, 0, &(&1.sample_count + &2))
  end

  defp sync?(entry, run, tfhd, trex) do
    Bitwise.band(
      run.first_sample_flags || entry.sample_flags || tfhd.default_sample_flags ||
        trex.default_sample_flags,
      0x10000
    ) == 0
  end

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + Box.size(box.tfhd) + Box.size(box.tfdt) + Box.size(box.trun)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "traf">>,
        Box.serialize(box.tfhd),
        Box.serialize(box.tfdt),
        Box.serialize(box.trun)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"tfhd", box_data, rest} ->
            box = %{box | tfhd: ExMP4.Box.parse(%Tfhd{}, box_data)}
            {box, rest}

          {"tfdt", box_data, rest} ->
            box = %{box | tfdt: ExMP4.Box.parse(%Tfdt{}, box_data)}
            {box, rest}

          {"trun", box_data, rest} ->
            box = %{box | trun: box.trun ++ [Box.parse(%Trun{}, box_data)]}
            {box, rest}

          {_other, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
