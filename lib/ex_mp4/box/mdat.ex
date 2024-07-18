defmodule ExMP4.Box.Mdat do
  @moduledoc """
  A module representing an `mdat` box.
  """

  @type t :: %__MODULE__{
          content: iodata()
        }

  defstruct content: <<>>

  defimpl ExMP4.Box do
    def size(box), do: ExMP4.header_size() + IO.iodata_length(box.content)

    def parse(box, content), do: %{box | content: content}

    def serialize(box) do
      [<<size(box)::32, "mdat">>, box.content]
    end
  end
end
