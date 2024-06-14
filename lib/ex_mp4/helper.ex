defmodule ExMP4.Helper do
  @moduledoc """
  Helper functions.
  """

  @units [:nanosecond, :microsecond, :millisecond, :second]

  @type timescale :: :nanosecond | :microsecond | :millisecond | :second | integer | Ratio.t()

  @doc """
  Convert duration between different timescales.
  """
  @spec timescalify(Ratio.t() | integer, timescale(), timescale()) :: integer
  def timescalify(time, timescale, timescale), do: time

  def timescalify(time, source_unit, target_unit)
      when is_atom(source_unit) or is_atom(target_unit) do
    timescalify(time, convert_unit(source_unit), convert_unit(target_unit))
  end

  def timescalify(time, source_timescale, target_timescale) do
    use Numbers, overload_operators: true
    Ratio.trunc(time * target_timescale / source_timescale + 0.5)
  end

  defp convert_unit(:nanosecond), do: 10 ** 9
  defp convert_unit(:microsecond), do: 10 ** 6
  defp convert_unit(:millisecond), do: 10 ** 3
  defp convert_unit(:second), do: 1
  defp convert_unit(integer) when is_integer(integer), do: integer
  defp convert_unit(unit), do: raise("Expected one of #{inspect(@units)}, got: #{inspect(unit)}")
end
