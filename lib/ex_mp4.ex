defmodule ExMP4 do
  @moduledoc File.read!("README.md")

  @type timescale :: Ratio.t() | integer()
  @type offset :: integer()
  @type duration :: non_neg_integer()

  @base_date ~U(1904-01-01 00:00:00Z)
  @movie_timescale 1000

  alias ExMP4.{FWriter, Reader}

  @spec base_date() :: DateTime.t()
  def base_date(), do: @base_date

  @spec movie_timescale() :: integer()
  def movie_timescale(), do: @movie_timescale
end
