defmodule ExMP4.DataWriter do
  @moduledoc """
  A behaviour module for implementing mp4 data writer.
  """

  @type state :: any()
  @type location :: :file.location() | nil

  @doc """
  Initialize the output.

  The returned `state` will be the first argument on the other callbacks.
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason :: any()}

  @doc """
  Invoked to handle writing an ISOBMFF box.

  The `data` may be a binary or an IO list.

  `location` if provided is the location in the output where to store the box.
  If `insert?` provided (defaults to `false`), the data should be inserted into
  that position and not overwriting existing data.
  """
  @callback write(state(), data :: iodata(), location(), insert? :: boolean()) :: :ok

  @doc """
  Close the output.
  """
  @callback close(state()) :: :ok
end
