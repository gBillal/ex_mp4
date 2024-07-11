defmodule ExMP4 do
  @moduledoc File.read!("README.md")

  @type timescale :: Ratio.t() | integer()
  @type offset :: integer()
  @type duration :: non_neg_integer()

  @base_date ~U(1904-01-01 00:00:00Z)
  @movie_timescale 1000
  @header_size 8
  @full_box_header_size 12

  @spec base_date() :: DateTime.t()
  def base_date(), do: @base_date

  @spec movie_timescale() :: integer()
  def movie_timescale(), do: @movie_timescale

  @doc """
  Get the header size of a box.
  """
  @spec header_size() :: integer()
  def header_size(), do: @header_size

  @doc """
  Get the size of the header of a full box.
  """
  @spec full_box_header_size() :: integer()
  def full_box_header_size(), do: @full_box_header_size
end
