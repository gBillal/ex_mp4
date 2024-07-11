defmodule ExMP4.Box.Utils do
  @moduledoc """
  Utilities functions used by the parser and serializer
  """

  @base_date ~U(1904-01-01 00:00:00Z)

  @spec to_date(integer()) :: DateTime.t()
  def to_date(diff), do: DateTime.add(@base_date, diff)

  @spec from_date(DateTime.t()) :: integer()
  def from_date(date), do: DateTime.diff(date, @base_date)

  @spec parse_header(binary()) :: {String.t(), binary(), binary()}
  def parse_header(
        <<1::32, box_type::binary-size(4), size::64, box_data::binary-size(size - 16),
          rest::binary>>
      ) do
    {box_type, box_data, rest}
  end

  def parse_header(
        <<size::32, box_type::binary-size(4), box_data::binary-size(size - 8), rest::binary>>
      ) do
    {box_type, box_data, rest}
  end
end
