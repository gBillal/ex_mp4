defmodule ExMP4.Box.Mvex do
  @moduledoc """
  A module representing an `mvex` box.

  This box warns readers that there might be Movie Fragment Boxes in this file.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Mehd, Trex}

  @type t :: %__MODULE__{
          mehd: Mehd.t() | nil,
          trex: [Trex.t()]
        }

  defstruct mehd: nil, trex: []

  defimpl ExMP4.Box do
    def size(box) do
      trex_size = Enum.map(box.trex, &Box.size/1) |> Enum.sum()
      ExMP4.header_size() + Box.size(box.mehd) + trex_size
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [<<size(box)::32, "mvex">>, Box.serialize(box.mehd), Box.serialize(box.trex)]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"mehd", box_data, rest} ->
            box = %{box | mehd: Box.parse(%Mehd{}, box_data)}
            {box, rest}

          {"trex", box_data, rest} ->
            box = %{box | trex: box.trex ++ [Box.parse(%Trex{}, box_data)]}
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
