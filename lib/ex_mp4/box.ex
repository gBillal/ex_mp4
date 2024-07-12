defprotocol ExMP4.Box do
  @moduledoc """
  A protocol defining the behaviour of an ISOBMFF box.
  """

  @fallback_to_any true

  @doc """
  Serialize a box into a io list.
  """
  @spec serialize(t()) :: iodata()
  def serialize(box)

  @doc """
  Parses the binary into a box.

  The header (size + name of the box) should not included.
  """
  @spec parse(t(), binary()) :: t()
  def parse(_box, value)

  @doc """
  Get the size of a box.
  """
  @spec size(t()) :: integer()
  def size(box)
end

defimpl ExMP4.Box, for: List do
  def size(list), do: Enum.map(list, &ExMP4.Box.size/1) |> Enum.sum()

  def serialize(list), do: Enum.map(list, &ExMP4.Box.serialize/1)

  def parse(_, _) do
  end
end

defimpl ExMP4.Box, for: Any do
  def size(_), do: 0

  def serialize(_), do: <<>>

  def parse(_, _) do
  end
end
