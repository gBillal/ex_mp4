defmodule ExMP4 do
  @moduledoc File.read!("README.md")

  @type timescale :: Ratio.t() | integer()
  @type offset :: integer()
  @type duration :: non_neg_integer()

  @base_date ~U(1904-01-01 00:00:00Z)

  def base_date(), do: @base_date

end
