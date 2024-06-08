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
  Seek to the provided position in the stream
  """
  @callback seek(state(), location(), insert? :: boolean()) :: :ok

  @doc """
  Seek and write from the input stream.

  Some stream may have optimised way of seeking and reading at the same time as the case for `:file`
  """
  @callback pwrite(state(), location(), data :: iodata(), insert? :: boolean()) :: :ok

  @doc """
  Close the input stream.
  """
  @callback close(state()) :: :ok

  @optional_callbacks pwrite: 4

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour ExMP4.Write

      @doc false
      def pwrite(state, location, data, insert?) do
        :ok = seek(state, location, insert?)
        write(state, data)
      end

      defoverridable pwrite: 4
    end
  end
end
