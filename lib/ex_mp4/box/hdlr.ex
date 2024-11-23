defmodule ExMP4.Box.Hdlr do
  @moduledoc """
  A module representing an `hdlr` box.

  This box within a Media Box declares media type of the track, and thus the process by which
  the media data in the track is presented
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          handler_type: binary(),
          name: String.t()
        }

  defstruct version: 0, flags: 0, handler_type: nil, name: ""

  defimpl ExMP4.Box do
    def size(box), do: ExMP4.full_box_header_size() + byte_size(box.name) + 21

    def parse(box, <<version::8, flags::24, 0::32, type::binary-size(4), 0::32*3, name::binary>>) do
      %{
        box
        | version: version,
          flags: flags,
          handler_type: type,
          name: String.slice(name, 0..-2//1)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "hdlr", box.version::8, box.flags::24, 0::32>>,
        box.handler_type,
        <<0::32*3>>,
        box.name,
        0
      ]
    end
  end
end
