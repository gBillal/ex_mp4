defmodule ExMP4.Box.Co64 do
  @moduledoc """
  A module representing an `co64` box.

  The chunk offset table gives the index of each chunk into the containing file.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          entries: [non_neg_integer()]
        }

  defstruct version: 0, flags: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: ExMP4.full_box_header_size() + 4 + 8 * length(box.entries)

    def parse(box, <<version::8, flags::24, _entry_count::32, entries::binary>>) do
      %{
        box
        | version: version,
          flags: flags,
          entries: for(<<offset::64 <- entries>>, do: offset)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "co64", box.version::8, box.flags::24, length(box.entries)::32>>,
        Enum.map(box.entries, &<<&1::64>>)
      ]
    end
  end
end
