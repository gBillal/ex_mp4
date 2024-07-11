defmodule ExMP4.Box.Stts do
  @moduledoc """
  A module representing an `stts` box.

  This box contains a compact version of a table that allows indexing from decoding time to sample number.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          entries: [%{:sample_count => integer(), :sample_delta => integer()}]
        }

  defstruct version: 0, flags: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: MP4.full_box_header_size() + 4 + 8 * length(box.entries)

    def parse(box, <<version::8, flags::24, _entry_count::32, entries::binary>>) do
      entries =
        for <<sample_count::32, sample_delta::32 <- entries>>,
          do: %{sample_count: sample_count, sample_delta: sample_delta}

      %{
        box
        | version: version,
          flags: flags,
          entries: entries
      }
    end

    def serialize(box) do
      entries = Enum.map(box.entries, &<<&1.sample_count::32, &1.sample_delta::32>>)
      [<<size(box)::32, "stts", box.version::8, box.flags::24, length(box.entries)::32>>, entries]
    end
  end
end
