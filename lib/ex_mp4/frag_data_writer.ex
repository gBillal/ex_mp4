defmodule ExMP4.FragDataWriter do
  @moduledoc """
  A behaviour module for implementing fragmented mp4 data writer.
  """

  @type state :: any()
  @type location :: :file.location() | nil

  @doc """
  Initialize the output.

  The returned `state` will be the first argument on the other callbacks.
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason :: any()}

  @doc """
  Invoked to handle writing media header initialization.
  """
  @callback write_init_header(state(), header :: iodata()) :: :ok

  @doc """
  Invoked to handle writing the whole fragment (`sidx` [optional] + `moof` + `mdat`).
  """
  @callback write_fragment(state(), fragment :: iodata()) :: :ok

  @doc """
  Invoked to handle writing while seeking into the file.

  This is an optional callback, only called by the `ExMP4.FWriter` to
  update the fragments duration in case `mehd` need to be included.s
  """
  @callback write(state(), data :: iodata(), location()) :: :ok

  @doc """
  Close the output.
  """
  @callback close(state()) :: :ok

  @optional_callbacks write: 3
end
