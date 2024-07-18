defmodule ExMP4.Box.Moof do
  @moduledoc """
  A module repsenting an `moof` box.

  The movie fragments extend the presentation in time. They provide the information that
  would previously have been in the Movie Box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Mfhd, Traf}

  @type t :: %__MODULE__{
          mfhd: Mfhd.t(),
          traf: [Traf.t()]
        }

  defstruct mfhd: %Mfhd{}, traf: []

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + ExMP4.Box.size(box.mfhd) + ExMP4.Box.size(box.traf)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "moof">>,
        ExMP4.Box.serialize(box.mfhd),
        ExMP4.Box.serialize(box.traf)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"mfhd", box_data, rest} ->
            box = %{box | mfhd: ExMP4.Box.parse(%Mfhd{}, box_data)}
            {box, rest}

          {"traf", box_data, rest} ->
            box = %{box | traf: box.traf ++ [ExMP4.Box.parse(%Traf{}, box_data)]}
            {box, rest}

          {_other, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
