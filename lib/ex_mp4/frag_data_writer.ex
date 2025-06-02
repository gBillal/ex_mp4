defmodule ExMP4.FragDataWriter do
  @moduledoc """
  A behaviour module for implementing fragmented mp4 data writer.
  """

  alias ExMP4.Box

  @type state :: any()
  @type location :: :file.location() | nil

  @doc """
  Initialize the output.

  The returned `state` will be the first argument on the other callbacks.
  """
  @callback open(input :: any()) :: {:ok, state()} | {:error, reason :: any()}

  @doc """
  Invoked to handle writing media header initialization.

  The header is two element list with the first element being `ftyp` box and
  the second the `moov` box.
  """
  @callback write_init_header(state(), header :: [Box.t()]) :: state()

  @doc """
  Invoked to handle writing the whole segment.

  The segment is a list of boxes that are part of the segment.  The first boxes are `sidx` if present,
  then a `moof` box, followed by the `mdat` box containing the media data.
  """
  @callback write_segment(state(), segment :: [Box.t()]) :: state()

  @doc """
  Invoked to handle writing while seeking into the file.

  This is an optional callback, only called by the `ExMP4.FWriter` to
  update the fragments duration in case `mehd` is present.
  """
  @callback write(state(), data :: iodata(), location()) :: state()

  @doc """
  Close the output.
  """
  @callback close(state()) :: :ok

  @optional_callbacks write: 3
end
