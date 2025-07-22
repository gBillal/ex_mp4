defmodule ExMP4.Box.Dinf do
  @moduledoc """
  A module representing a `dinf` box.

  The data information box contains objects that declare the location of the media information in a track
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.DataEntryURL

  @type t :: %__MODULE__{dref: map()}

  defstruct dref: %{
              version: 0,
              flags: 0,
              entry_count: 1,
              data_entry: [%DataEntryURL{version: 0, flags: 1}]
            }

  defimpl ExMP4.Box do
    def size(_box) do
      ExMP4.header_size() + ExMP4.full_box_header_size() * 2 + 4
    end

    def parse(box, <<_size::32, "dref", version::8, flags::24, entry_count::32, rest::binary>>) do
      %{
        box
        | dref: %{
            version: version,
            flags: flags,
            entry_count: entry_count,
            data_entry: parse_entries(rest)
          }
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "dinf", 28::32, "dref", box.dref.version::8, box.dref.flags::24,
          box.dref.entry_count::32>>,
        Enum.map(box.dref.data_entry, &ExMP4.Box.serialize/1)
      ]
    end

    defp parse_entries(<<>>), do: []

    defp parse_entries(rest) do
      case parse_header(rest) do
        {"url ", box_data, rest} ->
          [ExMP4.Box.parse(%DataEntryURL{}, box_data) | parse_entries(rest)]

        {name, box_data, rest} ->
          parse_entries(rest)
      end
    end
  end
end
