defmodule ExMP4.Box.Esds do
  @moduledoc """
  A module representing an `esds` box.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          es_descriptor: binary()
        }

  defstruct version: 0, flags: 0, es_descriptor: nil

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.full_box_header_size() + byte_size(box.es_descriptor)
    end

    def parse(box, <<version::8, flags::24, es_descriptor::binary>>) do
      %{box | version: version, flags: flags, es_descriptor: es_descriptor}
    end

    def serialize(box) do
      [<<size(box)::32, "esds">>, box.version, <<box.flags::24>>, box.es_descriptor]
    end
  end
end
