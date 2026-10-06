defmodule ExMP4.Box.UUID do
  @moduledoc """
  Module describing a UUID box.

  A `uuid` box is a user extension box, the following fields are available:
    * `type` - The 16 bytes extended type (`usertype`) identifying the box.
    * `data` - The raw payload of the box.
  """

  @type t :: %__MODULE__{
          type: <<_::128>>,
          data: binary()
        }

  defstruct type: nil, data: <<>>

  @doc """
  Create a new UUID box.

  `type` must be a 16 bytes binary.
  """
  @spec new(<<_::128>>, binary()) :: t()
  def new(type, data \\ <<>>)

  def new(<<_::binary-size(16)>> = type, data) when is_binary(data) do
    %__MODULE__{type: type, data: data}
  end

  def new(type, _data) do
    raise ArgumentError, "uuid type must be a 16 bytes binary, got: #{inspect(type)}"
  end

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
