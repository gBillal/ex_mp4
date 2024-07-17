defmodule ExMP4.Box.Stz2 do
  @moduledoc """
  A module representing an `stz2` box.

  This box contains the sample count and a table giving the size in bytes of each sample.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          field_size: non_neg_integer(),
          sample_count: non_neg_integer(),
          entries: [non_neg_integer()]
        }

  defstruct version: 0, flags: 0, field_size: 0, sample_count: 0, entries: []

  defimpl ExMP4.Box do
    def size(box),
      do: ExMP4.full_box_header_size() + 8 + div(box.field_size * length(box.entries), 8)

    def parse(
          box,
          <<version::8, flags::24, 0::24, field_size::8, sample_count::32, entries::binary>>
        ) do
      %{
        box
        | version: version,
          flags: flags,
          field_size: field_size,
          sample_count: sample_count,
          entries: for(<<sample_size::size(field_size) <- entries>>, do: sample_size)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "stz2", box.version::8, box.flags::24, 0::24, box.field_size::8,
          length(box.entries)::32>>,
        Enum.map(box.entries, &<<&1::size(box.field_size)>>)
      ]
    end
  end
end
