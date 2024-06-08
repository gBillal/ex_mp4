defmodule ExMP4 do
  @moduledoc File.read!("README.md")

  @type timescale :: Ratio.t() | integer()
  @type offset :: integer()
  @type duration :: non_neg_integer()
end
