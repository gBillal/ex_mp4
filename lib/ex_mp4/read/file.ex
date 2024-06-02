defmodule ExMP4.Read.File do
  @moduledoc """
  Implementation of the `ExMP4.Read` behaviour using filesystem.
  """

  use ExMP4.Read

  @impl true
  def open(filename), do: File.open(filename, [:binary, :read])

  @impl true
  def read(fd, chars), do: IO.binread(fd, chars)

  @impl true
  def seek(fd, location) do
    {:ok, _new_pos} = :file.position(fd, location)
    :ok
  end

  @impl true
  def pread(fd, location, chars) do
    {:ok, data} = :file.pread(fd, location, chars)
    data
  end

  @impl true
  def close(fd), do: File.close(fd)
end
