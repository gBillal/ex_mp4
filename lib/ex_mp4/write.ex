defmodule ExMP4.Write do
  @moduledoc """
  A behaviour defining how to write data to a destination
  """

  @type state :: any()
  @type reason :: any()
  @type location :: {:cur, offset :: integer()} | integer()

  @doc """
  Open the provided input in write mode

  The returned `state` will be the first argument on the other callbacks
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason()}

  @doc """
  Write the data
  """
  @callback write(state(), data :: iodata()) :: :ok

  @doc """
  Seek and write to the stream.
  """
  @callback pwrite(state(), location(), data :: iodata(), insert? :: boolean()) :: :ok

  @doc """
  Close the input stream.
  """
  @callback close(state()) :: :ok
end
