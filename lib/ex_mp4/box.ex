defprotocol ExMP4.Box do
  @moduledoc """
  A protocol defining the behaviour of an ISOBMFF box.
  """

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
