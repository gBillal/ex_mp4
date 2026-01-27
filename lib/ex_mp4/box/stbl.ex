defmodule ExMP4.Box.Stbl do
  @moduledoc """
  A module representing an `stbl` box.

  The sample table contains all the time and data indexing of the media samples in a track.
  Using the tables here, it is possible to locate samples in time, determine their type (e.g. I‐frame or not),
  and determine their size, container, and offset into that container.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Co64, Ctts, Stbl, Stco, Stsc, Stsd, Stss, Stsz, Stts, Stz2}

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
            co64: nil,
            # private fields
            _duration: 0,
            _idx: 1

  @doc """
  Gets the next sample metadata from the sample table.

  The return type is a tuple with the first element being the sample metadata and
  the second element is the sample table after removing the extracted sample.

  If there's no more samples, the first element will be `nil`.
  """
  @spec next_sample(t()) :: {ExMP4.SampleMetadata.t() | nil, t()}
  def next_sample(%Stbl{stts: %Stts{entries: []}} = stbl) do
    {nil, stbl}
  end

  def next_sample(stbl) do
    {%ExMP4.SampleMetadata{}, stbl}
    |> sample_dts()
    |> sample_pts()
    |> sync_sample()
    |> sample_size()
    |> sample_offset()
  end

  defp sample_dts({element, %Stbl{stts: %Stts{} = stts} = stbl}) do
    {delta, entries} =
      case stts.entries do
        [%{sample_count: 1, sample_delta: delta} | entries] ->
          {delta, entries}

        [%{sample_count: count, sample_delta: delta} = entry | entries] ->
          {delta, [%{entry | sample_count: count - 1} | entries]}
      end

    element = %{element | dts: stbl._duration, duration: delta}
    stts = %Stts{stts | entries: entries}

    {element, %Stbl{stbl | stts: stts, _duration: stbl._duration + delta}}
  end

  defp sample_pts({element, %{ctts: nil} = stbl}) do
    {%{element | pts: element.dts}, stbl}
  end

  defp sample_pts({element, %{ctts: %{entries: []}} = stbl}) do
    {%{element | pts: element.dts}, stbl}
  end

  defp sample_pts({element, %Stbl{ctts: %Ctts{} = ctts} = stbl}) do
    {offset, entries} =
      case ctts.entries do
        [%{sample_count: 1, sample_offset: offset} | entries] ->
          {offset, entries}

        [%{sample_count: count, sample_offset: offset} | entries] ->
          {offset, [%{sample_count: count - 1, sample_offset: offset} | entries]}
      end

    ctts = %Ctts{ctts | entries: entries}
    {%{element | pts: element.dts + offset}, %Stbl{stbl | ctts: ctts}}
  end

  defp sync_sample({element, %{stss: nil} = stbl}), do: {%{element | sync?: true}, stbl}

  defp sync_sample({element, %Stbl{stss: %Stss{} = stss, _idx: sample_index} = stbl}) do
    {sync?, entries} =
      case stss.entries do
        [] -> {true, []}
        [^sample_index] -> {true, [sample_index]}
        [^sample_index | entries] -> {true, entries}
        entries -> {false, entries}
      end

    stss = %Stss{stss | entries: entries}
    {%{element | sync?: sync?}, %Stbl{stbl | stss: stss}}
  end

  defp sample_size({element, %Stbl{stsz: %Stsz{sample_size: 0} = stsz} = stbl})
       when not is_nil(stsz) do
    [sample_size | entries] = stsz.entries
    stsz = %Stsz{stsz | entries: entries}
    {%{element | size: sample_size}, %Stbl{stbl | stsz: stsz}}
  end

  defp sample_size({element, %{stsz: stsz} = stbl}) when not is_nil(stsz) do
    {%{element | size: stsz.sample_size}, stbl}
  end

  defp sample_size({element, %Stbl{stz2: %Stz2{} = stz2} = stbl}) do
    [sample_size | entries] = stz2.entries
    stz2 = %Stz2{stz2 | entries: entries}
    {%{element | size: sample_size}, %Stbl{stbl | stz2: stz2}}
  end

  defp sample_offset(
         {element, %Stbl{stco: stco, co64: co64, stsc: stsc, _idx: sample_index} = stbl}
       ) do
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
        do: %Stbl{stbl | stsc: stsc, co64: stco},
        else: %Stbl{stbl | stsc: stsc, stco: stco}

    {%{element | offset: chunk_offset}, %{stbl | _idx: sample_index + 1}}
  end

  defp maybe_remove_stsc_entry(%Stsc{} = stsc, stsc_entries) do
    case stsc_entries do
      [%{first_chunk: first_chunk}, %{first_chunk: first_chunk} = entry | entries] ->
        %Stsc{stsc | entries: [entry | entries]}

      entries ->
        %Stsc{stsc | entries: entries}
    end
  end

  defimpl ExMP4.Box do
    @child_boxes %{
      "stsd" => %Stsd{},
      "stts" => %Stts{},
      "ctts" => %Ctts{},
      "stss" => %Stss{},
      "stsz" => %Stsz{},
      "stz2" => %Stz2{},
      "stsc" => %Stsc{},
      "stco" => %Stco{},
      "co64" => %Co64{}
    }

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
      {box_name, box_data, rest} = parse_header(data)

      box =
        case Map.fetch(@child_boxes, box_name) do
          {:ok, box_struct} ->
            Map.put(box, String.to_atom(box_name), Box.parse(box_struct, box_data))

          :error ->
            box
        end

      do_parse(box, rest)
    end
  end
end
