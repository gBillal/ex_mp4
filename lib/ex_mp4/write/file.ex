defmodule ExMP4.Write.File do
  @moduledoc """
  Implementation of the `ExMP4.Write` behaviour using filesystem.
  """

  use ExMP4.Write

  @impl true
  def open(filename), do: File.open(filename, [:binary, :write])

  @impl true
  def write(fd, data), do: IO.binwrite(fd, data)

  @impl true
  def seek(fd, location, _insert? \\ false) do
    {:ok, _new_pos} = :file.position(fd, location)
    :ok
  end

  @impl true
  def pwrite(fd, location, data, _insert?) do
    :file.pwrite(fd, location, data)
  end

  @impl true
  def close(fd), do: File.close(fd)
end
