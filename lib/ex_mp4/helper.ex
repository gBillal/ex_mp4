defmodule ExMP4.Helper do
  @moduledoc """
  Helper functions.
  """

  @compile {:inline, timescalify: 3, timescalify: 4, convert_unit: 1}

  @type timescale :: :nanosecond | :microsecond | :millisecond | :second | integer | Ratio.t()

  @units [:nanosecond, :microsecond, :millisecond, :second]
  @seconds_in_hour 3_600
  @seconds_in_minute 60

  @doc """
  Convert duration between different timescales.

      iex> ExMP4.Helper.timescalify(1900, 90000, :millisecond)
      21

      iex> ExMP4.Helper.timescalify(21, :millisecond, 90_000)
      1890

      iex> ExMP4.Helper.timescalify(1600, :millisecond, :second)
      2

      iex> ExMP4.Helper.timescalify(15, :nanosecond, :nanosecond)
      15
  """
  @spec timescalify(Ratio.t() | integer, timescale(), timescale(), :round | :exact) ::
          integer() | float()
  def timescalify(time, timescale, timescale, rounding \\ :round)

  def timescalify(time, timescale, timescale, _rounding), do: time

  def timescalify(time, source_unit, target_unit, rounding)
      when is_atom(source_unit) or is_atom(target_unit) do
    timescalify(time, convert_unit(source_unit), convert_unit(target_unit), rounding)
  end

  def timescalify(time, source_timescale, target_timescale, rounding) do
    case rounding do
      :round -> round(time * target_timescale / source_timescale)
      :exact -> time * target_timescale / source_timescale
    end
  end

  @doc """
  Format a `millisecond` duration as `H:MM:ss.mmm`

      iex> ExMP4.Helper.format_duration(100)
      "0:00:00.100"

      iex> ExMP4.Helper.format_duration(165_469_850)
      "45:57:49.850"
  """
  @spec format_duration(non_neg_integer()) :: String.t()
  def format_duration(duration_ms) do
    milliseconds = rem(duration_ms, 1000)
    duration = div(duration_ms, 1000)

    {hours, duration} = div_rem(duration, @seconds_in_hour)
    {minutes, seconds} = div_rem(duration, @seconds_in_minute)

    "#{hours}:#{pad_value(minutes)}:#{pad_value(seconds)}.#{milliseconds}"
  end

  defp convert_unit(:nanosecond), do: 10 ** 9
  defp convert_unit(:microsecond), do: 10 ** 6
  defp convert_unit(:millisecond), do: 10 ** 3
  defp convert_unit(:second), do: 1
  defp convert_unit(integer) when is_integer(integer), do: integer
  defp convert_unit(unit), do: raise("Expected one of #{inspect(@units)}, got: #{inspect(unit)}")

  defp div_rem(a, b), do: {div(a, b), rem(a, b)}
  defp pad_value(a), do: a |> to_string() |> String.pad_leading(2, "0")
end
