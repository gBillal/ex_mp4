defmodule ExMP4.Box.Stbl do
  @moduledoc """
  A module representing an `stbl` box.

  The sample table contains all the time and data indexing of the media samples in a track.
  Using the tables here, it is possible to locate samples in time, determine their type (e.g. I‐frame or not),
  and determine their size, container, and offset into that container.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.Stbl
  alias ExMP4.Box
  alias ExMP4.Box.{Co64, Ctts, Stco, Stsc, Stsd, Stss, Stsz, Stz2, Stts}

  @type t :: %__MODULE__{
          stsd: Stsd.t(),
          stts: Stts.t(),
          ctts: Ctts.t() | nil,
          stss: Stss.t() | nil,
          stsz: Stsz.t() | nil,
          stz2: Stz2.t() | nil,
          stsc: Stsc.t(),
          stco: Stco.t() | nil,
          co64: Co64.t() | nil
        }

  defstruct stsd: %Stsd{},
            stts: %Stts{},
            ctts: nil,
            stss: nil,
            stsz: nil,
            stz2: nil,
            stsc: %Stsc{},
            stco: nil,
            co64: nil

  @doc """
  Get the next sample from the sample table.

  The `sample_index` is the index of the next sample to retrieve (must start from 1).

  The `total_duration` is the total duration of all the retrieved samples.

  The return type is a tuple with the first element being the
  sample table after removing the extracted sample and the second element
  is the extracted sample.
  """
  @spec next_sample(t(), integer(), integer()) :: {t(), ExMP4.SampleMetadata.t()}
  def next_sample(stbl, sample_index, total_duration) do
    {stbl, %ExMP4.SampleMetadata{}}
    |> sample_dts(total_duration)
    |> sample_pts()
    |> sync_sample(sample_index)
    |> sample_size()
    |> sample_offset(sample_index)
  end

  defp sample_dts({%{stts: stts} = stbl, element}, total_duration) do
    {delta, entries} =
      case stts.entries do
        [%{sample_count: 1, sample_delta: delta} | entries] ->
          {delta, entries}

        [%{sample_count: count, sample_delta: delta} = entry | entries] ->
          {delta, [%{entry | sample_count: count - 1} | entries]}
      end

    element = %{element | dts: total_duration, duration: delta}
    stts = %Stts{stts | entries: entries}

    {%Stbl{stbl | stts: stts}, element}
  end

  defp sample_pts({%{ctts: nil} = stbl, element}) do
    {stbl, %{element | pts: element.dts}}
  end

  defp sample_pts({%{ctts: ctts} = stbl, element}) do
    {offset, entries} =
      case ctts.entries do
        [%{sample_count: 1, sample_offset: offset} | entries] ->
          {offset, entries}

        [%{sample_count: count, sample_offset: offset} | entries] ->
          {offset, [%{sample_count: count - 1, sample_offset: offset} | entries]}
      end

    ctts = %Ctts{ctts | entries: entries}
    {%Stbl{stbl | ctts: ctts}, %{element | pts: element.dts + offset}}
  end

  defp sync_sample({%{stss: nil} = stbl, element}, _index), do: {stbl, %{element | sync?: true}}

  defp sync_sample({%{stss: stss} = stbl, element}, sample_index) do
    {sync?, entries} =
      case stss.entries do
        [] -> {true, []}
        [^sample_index] -> {true, [sample_index]}
        [^sample_index | entries] -> {true, entries}
        entries -> {false, entries}
      end

    stss = %Stss{stss | entries: entries}
    {%Stbl{stbl | stss: stss}, %{element | sync?: sync?}}
  end

  defp sample_size({%{stsz: stsz} = stbl, element}) when not is_nil(stsz) do
    if stsz.sample_size != 0 do
      {stbl, %{element | size: stsz.sample_size}}
    else
      [sample_size | entries] = stsz.entries
      stsz = %Stsz{stsz | entries: entries}
      {%Stbl{stbl | stsz: stsz}, %{element | size: sample_size}}
    end
  end

  defp sample_size({%{stz2: stz2} = stbl, element}) do
    [sample_size | entries] = stz2.entries
    stz2 = %Stz2{stz2 | entries: entries}
    {%Stbl{stbl | stz2: stz2}, %{element | size: sample_size}}
  end

  defp sample_offset({%{stco: stco, co64: co64, stsc: stsc} = stbl, element}, sample_index) do
    [chunk_offset | chunk_entries] = Map.get(stco || co64, :entries)
    [stsc_entry | stsc_entries] = stsc.entries

    diff = sample_index - stsc_entry.first_sample
    new_chunk? = diff != 0 and rem(diff, stsc_entry.samples_per_chunk) == 0

    {stsc, stco, chunk_offset} =
      case new_chunk? do
        true ->
          [chunk_offset | chunk_entries] = chunk_entries
          stsc_entry = %{stsc_entry | first_chunk: stsc_entry.first_chunk + 1}
          stsc = maybe_remove_stsc_entry(stsc, [stsc_entry | stsc_entries])

          {stsc, Map.put(stco || co64, :entries, [chunk_offset + element.size | chunk_entries]),
           chunk_offset}

        false ->
          {stsc, Map.put(stco || co64, :entries, [chunk_offset + element.size | chunk_entries]),
           chunk_offset}
      end

    stbl =
      if is_nil(stbl.stco),
        do: %Stbl{stsc: stsc, co64: stco},
        else: %Stbl{stbl | stsc: stsc, stco: stco}

    {stbl, %{element | offset: chunk_offset}}
  end

  defp maybe_remove_stsc_entry(stsc, stsc_entries) do
    case stsc_entries do
      [%{first_chunk: first_chunk}, %{first_chunk: first_chunk} = entry | entries] ->
        %Stsc{stsc | entries: [entry | entries]}

      entries ->
        %Stsc{stsc | entries: entries}
    end
  end

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + Box.size(box.stsd) + Box.size(box.stts) +
        Box.size(box.ctts) + Box.size(box.stsc) + Box.size(box.stss) + Box.size(box.stsz) +
        Box.size(box.stz2) + Box.size(box.stco) + Box.size(box.co64)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "stbl">>,
        Box.serialize(box.stsd),
        Box.serialize(box.stts),
        Box.serialize(box.ctts),
        Box.serialize(box.stsc),
        Box.serialize(box.stco),
        Box.serialize(box.stsz),
        Box.serialize(box.stss),
        Box.serialize(box.stz2),
        Box.serialize(box.co64)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"stsd", box_data, rest} ->
            box = %{box | stsd: ExMP4.Box.parse(%Stsd{}, box_data)}
            {box, rest}

          {"stts", box_data, rest} ->
            box = %{box | stts: ExMP4.Box.parse(%Stts{}, box_data)}
            {box, rest}

          {"ctts", box_data, rest} ->
            box = %{box | ctts: ExMP4.Box.parse(%Ctts{}, box_data)}
            {box, rest}

          {"stss", box_data, rest} ->
            box = %{box | stss: ExMP4.Box.parse(%Stss{}, box_data)}
            {box, rest}

          {"stsz", box_data, rest} ->
            box = %{box | stsz: ExMP4.Box.parse(%Stsz{}, box_data)}
            {box, rest}

          {"stz2", box_data, rest} ->
            box = %{box | stz2: ExMP4.Box.parse(%Stz2{}, box_data)}
            {box, rest}

          {"stsc", box_data, rest} ->
            box = %{box | stsc: ExMP4.Box.parse(%Stsc{}, box_data)}
            {box, rest}

          {"stco", box_data, rest} ->
            box = %{box | stco: ExMP4.Box.parse(%Stco{}, box_data)}
            {box, rest}

          {"co64", box_data, rest} ->
            box = %{box | co64: ExMP4.Box.parse(%Co64{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
