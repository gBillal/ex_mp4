defmodule ExMP4.Box.Stss do
  @moduledoc """
  A module representing an `stss` box.

  This box provides a compact marking of the sync samples within the stream. The table is arranged
  in strictly increasing order of sample number.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          entries: [integer()]
        }

  defstruct version: 0, flags: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: ExMP4.full_box_header_size() + 4 * (length(box.entries) + 1)

    def parse(box, <<version::8, flags::24, _entry_count::32, entries::binary>>) do
      %{
        box
        | version: version,
          flags: flags,
          entries: for(<<sample_num::32 <- entries>>, do: sample_num)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "stss", box.version::8, box.flags::24, length(box.entries)::32>>,
        Enum.map(box.entries, &<<&1::32>>)
      ]
    end
  end
end
