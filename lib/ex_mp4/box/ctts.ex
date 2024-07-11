defmodule ExMP4.Box.Ctts do
  @moduledoc """
  A module representing an `ctts` box.

  This box provides the offset between decoding time and composition time.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          entries: [%{:sample_count => integer(), :sample_offset => integer()}]
        }

  defstruct version: 0, flags: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: MP4.full_box_header_size() + 4 + 8 * length(box.entries)

    def parse(box, <<version::8, flags::24, _entry_count::32, entries::binary>>) do
      %{
        box
        | version: version,
          flags: flags,
          entries: parse_entries(version, entries)
      }
    end

    def serialize(box) do
      entries = Enum.map(box.entries, &<<&1.sample_count::32, &1.sample_offset::32>>)
      [<<size(box)::32, "ctts", box.version::8, box.flags::24, length(box.entries)::32>>, entries]
    end

    defp parse_entries(0, entries) do
      for <<sample_count::32, sample_offset::32 <- entries>>,
        do: %{sample_count: sample_count, sample_offset: sample_offset}
    end

    defp parse_entries(1, entries) do
      for <<sample_count::32, sample_offset::32-signed <- entries>>,
        do: %{sample_count: sample_count, sample_offset: sample_offset}
    end
  end
end
