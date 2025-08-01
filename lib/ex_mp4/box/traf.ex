defmodule ExMP4.Box.Traf do
  @moduledoc """
  A module representing an `traf` box.
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

  @spec store_sample(t(), ExMP4.Sample.t()) :: t()
  def store_sample(%{trun: [run]} = traf, sample) do
    run_entry = %{
      sample_duration: sample.duration,
      sample_size: IO.iodata_length(sample.payload),
      sample_flags: if(sample.sync?, do: 0, else: 0x10000),
      sample_composition_time_offset: sample.pts - sample.dts
    }

    run = %{run | entries: [run_entry | run.entries], sample_count: run.sample_count + 1}
    %{traf | trun: [run]}
  end

  @spec finalize(t()) :: t()
  @spec finalize(t(), boolean()) :: t()
  def finalize(traf, base_is_moof? \\ false)

  def finalize(%{trun: [%Trun{entries: []}]} = traf, _base_is_moof?), do: traf

  def finalize(%{trun: [run], tfhd: tfhd} = traf, base_is_moof?) do
    [first_entry | _entries] = run.entries

    {same_duration?, same_size?, same_flags?, zero_offset?} =
      Enum.reduce(
        run.entries,
        {true, true, true, true},
        fn entry, {same_duration?, same_size?, same_flags?, zero_offset?} ->
          {
            same_duration? and entry.sample_duration == first_entry.sample_duration,
            same_size? and entry.sample_size == first_entry.sample_size,
            same_flags? and entry.sample_flags == first_entry.sample_flags,
            zero_offset? and entry.sample_composition_time_offset == 0
          }
        end
      )

    run_flags = run_flags(same_duration?, same_size?, same_flags?, zero_offset?)
    tr_flags = tr_flags(same_duration?, same_size?, same_flags?, base_is_moof?)

    run = %{run | flags: run_flags, entries: Enum.reverse(run.entries)}
    %{traf | trun: [run], tfhd: track_header(tfhd, tr_flags, first_entry)}
  end

  @spec update_base_offset(t(), integer()) :: t()
  @spec update_base_offset(t(), integer(), integer()) :: t()
  def update_base_offset(traf, base_offset, trun_data_offset \\ 0) do
    %{trun: truns, tfhd: tfhd} = traf

    tfhd = %{tfhd | base_data_offset: base_offset}

    {truns, _offset} =
      Enum.map_reduce(
        truns,
        trun_data_offset,
        &{%{&1 | data_offset: &2}, &2 + trun_size(&1, tfhd)}
      )

    %{traf | tfhd: tfhd, trun: truns}
  end

  @doc """
  Get the total size of the track fragment.
  """
  @spec total_size(t(), ExMP4.Box.Trex.t() | nil) :: integer()
  def total_size(%{tfhd: tfhd} = traf, trex \\ nil) do
    default_sample_size = (trex && trex.default_sample_size) || 0
    Enum.reduce(traf.trun, 0, &(&2 + trun_size(&1, tfhd, default_sample_size)))
  end

  @doc """
  Get the total duration of the track fragment.
  """
  @spec duration(t(), ExMP4.Box.Trex.t() | nil) :: integer()
  def duration(%{tfhd: tfhd} = traf, trex \\ nil) do
    default_sample_duration = (trex && trex.default_sample_duration) || 0

    Enum.reduce(traf.trun, 0, fn trun, duration ->
      if Bitwise.band(trun.flags, 0x100) == 0 do
        duration + trun.sample_count * (tfhd.default_sample_duration || default_sample_duration)
      else
        duration + (Enum.map(trun.entries, & &1.sample_duration) |> Enum.sum())
      end
    end)
  end

  @doc """
  Get the count of samples of the track fragment.
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

  defp tr_flags(same_duration?, same_size?, same_flags?, base_is_moof?) do
    flags = if base_is_moof?, do: 0x20000, else: 0x1
    flags = if same_duration?, do: Bitwise.bor(flags, 0x8), else: flags
    flags = if same_size?, do: Bitwise.bor(flags, 0x10), else: flags
    if same_flags?, do: Bitwise.bor(flags, 0x20), else: flags
  end

  defp run_flags(same_duration?, same_size?, same_flags?, zoro_offset?) do
    flags = 0x1
    flags = if same_duration?, do: flags, else: Bitwise.bor(flags, 0x100)
    flags = if same_size?, do: flags, else: Bitwise.bor(flags, 0x200)
    flags = if same_flags?, do: flags, else: Bitwise.bor(flags, 0x400)
    if zoro_offset?, do: flags, else: Bitwise.bor(flags, 0x800)
  end

  defp track_header(tfhd, tr_flags, first_entry) do
    duration = if Bitwise.band(tr_flags, 0x8) != 0, do: first_entry.sample_duration
    size = if Bitwise.band(tr_flags, 0x10) != 0, do: first_entry.sample_size
    flags = if Bitwise.band(tr_flags, 0x20) != 0, do: first_entry.sample_flags

    %Tfhd{
      tfhd
      | flags: tr_flags,
        default_sample_duration: duration,
        default_sample_size: size,
        default_sample_flags: flags
    }
  end

  defp trun_size(trun, tfhd, default_sample_size \\ 0) do
    if Bitwise.band(trun.flags, 0x200) == 0 do
      trun.sample_count * (tfhd.default_sample_size || default_sample_size)
    else
      Enum.map(trun.entries, & &1.sample_size) |> Enum.sum()
    end
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
