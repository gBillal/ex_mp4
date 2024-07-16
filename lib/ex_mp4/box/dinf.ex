defmodule ExMP4.Box.Dinf do
  @moduledoc """
  A module representing a `dinf` box.

  The data information box contains objects that declare the location of the media information in a track
  """

  @type t :: %__MODULE__{dref: map()}

  defstruct dref: %{
              version: 0,
              flags: 0,
              entry_count: 1,
              data_entry: [
                %{
                  version: 0,
                  flags: 0
                }
              ]
            }

  defimpl ExMP4.Box do
    def size(_box) do
      ExMP4.header_size() + MP4.full_box_header_size() * 2 + 4
    end

    def parse(
          box,
          <<_size::32, "dref", version::8, flags::24, entry_count::32, _url_size::32, "url ",
            url_version::8, url_flags::24>>
        ) do
      %{
        box
        | dref: %{
            version: version,
            flags: flags,
            entry_count: entry_count,
            data_entry: [%{version: url_version, flags: url_flags}]
          }
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "dinf", 28::32, "dref", box.dref.version::8, box.dref.flags::24,
          box.dref.entry_count::32>>,
        Enum.map(box.dref.data_entry, &<<12::32, "url ", &1.version::8, &1.flags::24>>)
      ]
    end
  end
end
