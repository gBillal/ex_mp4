defmodule ExMP4.Box.Trun do
  @moduledoc """
  A module repsenting an `trun` box.

  A track run documents a contiguous set of samples for a track.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          sample_count: integer(),
          data_offset: integer() | nil,
          first_sample_flags: integer() | nil,
          entries: [
            %{
              :sample_duration => integer() | nil,
              :sample_size => integer() | nil,
              :sample_flags => integer() | nil,
              :sample_composition_time_offset => integer() | nil
            }
          ]
        }

  defstruct version: 0,
            flags: 0,
            sample_count: 0,
            data_offset: 0,
            first_sample_flags: nil,
            entries: []

  defimpl ExMP4.Box do
    import Bitwise

    def size(%{flags: flags} = box) do
      flag_present_in_entries =
        [0x100, 0x200, 0x400, 0x800]
        |> Enum.map(&flag_value(flags, &1))
        |> Enum.sum()

      ExMP4.full_box_header_size() + 4 + (flag_value(flags, 0x1) + flag_value(flags, 0x4)) * 4 +
        length(box.entries) * flag_present_in_entries * 4
    end

    def parse(box, <<version::8, flags::24, sample_count::32, rest::binary>>) do
      {data_offset, rest} = parse_entry(flags &&& 0x1, rest)
      {first_sample_flags, rest} = parse_entry(flags &&& 0x4, rest)

      {entries, <<>>} =
        Enum.reduce(1..sample_count, {[], rest}, fn _idx, {entries, data} ->
          {sample_duration, rest} = parse_entry(flags &&& 0x100, data)
          {sample_size, rest} = parse_entry(flags &&& 0x200, rest)
          {sample_flags, rest} = parse_entry(flags &&& 0x400, rest)
          {sample_composition, rest} = parse_signed_entry(version, flags &&& 0x800, rest)

          entry = %{
            sample_duration: sample_duration,
            sample_size: sample_size,
            sample_flags: sample_flags,
            sample_composition_time_offset: sample_composition
          }

          {[entry | entries], rest}
        end)

      %{
        box
        | version: version,
          flags: flags,
          sample_count: sample_count,
          data_offset: data_offset || 0,
          first_sample_flags: first_sample_flags,
          entries: Enum.reverse(entries)
      }
    end

    def serialize(%{flags: flags} = box) do
      entries =
        Enum.reduce(box.entries, [], fn entry, data ->
          time_offset =
            if box.version == 0 do
              serialize_entry(flags &&& 0x800, entry.sample_composition_time_offset)
            else
              serialize_signed_entry(flags &&& 0x800, entry.sample_composition_time_offset)
            end

          entry = [
            serialize_entry(flags &&& 0x100, entry.sample_duration),
            serialize_entry(flags &&& 0x200, entry.sample_size),
            serialize_entry(flags &&& 0x400, entry.sample_flags),
            time_offset
          ]

          [entry | data]
        end)

      [
        <<size(box)::32, "trun", box.version::8, box.flags::24, box.sample_count::32>>,
        serialize_entry(flags &&& 0x1, box.data_offset),
        serialize_entry(flags &&& 0x4, box.first_sample_flags),
        Enum.reverse(entries)
      ]
    end

    defp parse_entry(0, bin), do: {nil, bin}
    defp parse_entry(_other, <<value::32, rest::binary>>), do: {value, rest}

    defp parse_signed_entry(_version, 0, bin), do: {nil, bin}
    defp parse_signed_entry(0, _flag_set, <<value::32, rest::binary>>), do: {value, rest}
    defp parse_signed_entry(1, _flag_set, <<value::32-signed, rest::binary>>), do: {value, rest}

    defp serialize_entry(0, _value), do: <<>>
    defp serialize_entry(_flag_set, value), do: <<value::32>>

    defp serialize_signed_entry(0, _value), do: <<>>
    defp serialize_signed_entry(_flag_set, value), do: <<value::32-signed>>

    defp flag_value(flags, mask), do: min(flags &&& mask, 1)
  end
end
