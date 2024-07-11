defmodule ExMP4.Box.Stsz do
  @moduledoc """
  A module representing an `stsz` box.

  This box contains the sample count and a table giving the size in bytes of each sample.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          sample_size: non_neg_integer(),
          sample_count: non_neg_integer(),
          entries: [non_neg_integer()]
        }

  defstruct version: 0, flags: 0, sample_size: 0, sample_count: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: MP4.full_box_header_size() + 8 + 4 * length(box.entries)

    def parse(box, <<version::8, flags::24, sample_size::32, sample_count::32, entries::binary>>) do
      %{
        box
        | version: version,
          flags: flags,
          sample_size: sample_size,
          sample_count: sample_count,
          entries: parse_entries(sample_size, entries)
      }
    end

    def serialize(box) do
      entries = if box.sample_size == 0, do: Enum.map(box.entries, &<<&1::32>>), else: <<>>

      [
        <<size(box)::32, "stsz", box.version::8, box.flags::24, box.sample_size::32,
          length(box.entries)::32>>,
        entries
      ]
    end

    defp parse_entries(0, entries) do
      for <<sample_size::32 <- entries>>, do: sample_size
    end

    defp parse_entries(_sample_size, _entries), do: []
  end
end
