defmodule ExMP4.BitStreamFilter do
  @moduledoc """
  A behaviour module for implementing a bit stream filter.

  A bit stream filter operates on encoded data without decoding by
  performing bitstream level modifications.
  """

  alias ExMP4.{Sample, Track}

  @type state :: any()
  @type opts :: Keyword.t()

  @doc """
  Callback invoked to initialize the filter.
  """
  @callback init(Track.t(), opts()) :: {:ok, state()} | {:error, any()}

  @doc """
  Callback invoked to filter a payload (usually a video frame or audio sample).

  This method should not fail, in case of error returns the input data.
  """
  @callback filter(state(), Sample.t()) :: {Sample.t(), state()}
end
