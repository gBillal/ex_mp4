defmodule ExMP4.Read do
  @moduledoc """
  A behaviour defining how to read data from an mp4 input
  """

  @type state :: any()
  @type reason :: any()
  @type location :: {:cur, offset :: integer()} | integer()

  @doc """
  Open the provided input in read mode

  The returned `state` will be the first argument on the other callbacks
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason()}

  @doc """
  Read the specified amount of bytes from the input
  """
  @callback read(state(), chars :: non_neg_integer()) :: iodata() | :eof

  @doc """
  Seek to the provided position in the input stream
  """
  @callback seek(state(), location()) :: :ok

  @doc """
  Seek and read from the input stream.

  Some stream may have optimised way of seeking and reading at the same time as the case for `:file`
  """
  @callback pread(state(), location(), chars :: non_neg_integer()) :: iodata() | :eof

  @doc """
  Close the input stream.
  """
  @callback close(state()) :: :ok

  @optional_callbacks pread: 3

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour ExMP4.Read

      @doc false
      def pread(state, location, chars) do
        :ok = seek(state, location)
        read(state, chars)
      end

      defoverridable pread: 3
    end
  end
end
