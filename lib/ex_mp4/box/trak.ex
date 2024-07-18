defmodule ExMP4.Box.Trak do
  @moduledoc """
  A module representing a track container box.
  """

  alias ExMP4.Box.{Mdia, Tkhd}

  import ExMP4.Box.Utils, only: [parse_header: 1]

  @type t :: %__MODULE__{
          tkhd: Tkhd.t(),
          mdia: Mdia.t()
        }

  defstruct tkhd: %Tkhd{}, mdia: %Mdia{}

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + ExMP4.Box.size(box.tkhd) + ExMP4.Box.size(box.mdia)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [<<size(box)::32, "trak">>, ExMP4.Box.serialize(box.tkhd), ExMP4.Box.serialize(box.mdia)]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"tkhd", box_data, rest} ->
            box = %{box | tkhd: ExMP4.Box.parse(%Tkhd{}, box_data)}
            {box, rest}

          {"mdia", box_data, rest} ->
            box = %{box | mdia: ExMP4.Box.parse(%Mdia{}, box_data)}
            {box, rest}

          {_other, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
