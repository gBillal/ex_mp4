defmodule ExMP4.Helper do
  @moduledoc false

  @doc """
  Convert duration in `t:Membrane.Time.t/0` to duration in ticks.
  """
  @spec timescalify(Ratio.t() | integer, Ratio.t() | integer, Ratio.t() | integer) :: integer
  def timescalify(time, timescale, timescale), do: time

  def timescalify(time, source_timescale, target_timescale) do
    use Numbers, overload_operators: true
    Ratio.trunc(time * target_timescale / source_timescale + 0.5)
  end
end
