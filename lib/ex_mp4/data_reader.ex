defmodule ExMP4.DataReader do
  @moduledoc """
  A behaviour module for implementing mp4 data reader.
  """

  @type state :: any()
  @type reason :: any()
  @type location :: :file.location() | nil

  @doc """
  Open the provided input in read mode

  The returned `state` will be the first argument on the other callbacks
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason()}

  @doc """
  Read the specified amount of bytes from the input.

  An optional location may be provided to seek into the input.
  """
  @callback read(state(), chars :: non_neg_integer(), location()) :: iodata() | :eof

  @doc """
  Seek to the provided location in the input stream
  """
  @callback seek(state(), location()) :: :ok

  @doc """
  Close the input stream.
  """
  @callback close(state()) :: :ok
end
