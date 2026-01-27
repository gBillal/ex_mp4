defmodule ExMP4.Box.UUID do
  @moduledoc """
  Module describing a UUID box.
  """

  @type t :: %__MODULE__{
          type: binary(),
          data: binary()
        }

  defstruct [:type, :data]

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + byte_size(box.type) + byte_size(box.data)
    end

    def parse(box, <<type::binary-size(16), data::binary>>) do
      %{box | type: type, data: data}
    end

    def serialize(box) do
      [<<size(box)::32, "uuid">>, box.type, box.data]
    end
  end
end
