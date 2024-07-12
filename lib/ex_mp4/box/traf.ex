defmodule ExMP4.Box.Traf do
  @moduledoc """
  A module repsenting an `traf` box.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
  alias ExMP4.Box.{Tfdt, Tfhd, Trun}

  @type t :: %__MODULE__{
          tfhd: Tfhd.t(),
          tfdt: Tfdt.t() | nil,
          trun: [Trun.t()]
        }

  defstruct tfhd: %Tfhd{}, tfdt: nil, trun: []

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + Box.size(box.tfhd) + Box.size(box.tfdt) + Box.size(box.trun)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "traf">>,
        Box.serialize(box.tfhd),
        Box.serialize(box.tfdt),
        Box.serialize(box.trun)
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"tfhd", box_data, rest} ->
            box = %{box | tfhd: ExMP4.Box.parse(%Tfhd{}, box_data)}
            {box, rest}

          {"tfdt", box_data, rest} ->
            box = %{box | tfdt: ExMP4.Box.parse(%Tfdt{}, box_data)}
            {box, rest}

          {"trun", box_data, rest} ->
            box = %{box | trun: box.trun ++ [Box.parse(%Trun{}, box_data)]}
            {box, rest}

          {_other, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
