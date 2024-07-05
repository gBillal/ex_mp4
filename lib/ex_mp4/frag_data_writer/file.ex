defmodule ExMP4.FragDataWriter.File do
  @moduledoc """
  Implementation of the `ExMP4.FragDataWriter` behaviour using filesystem (single file).
  """

  @behaviour ExMP4.FragDataWriter

  @impl true
  def open(filename), do: File.open(filename, [:binary, :write])

  @impl true
  def write_init_header(fd, header) do
    :ok = :file.write(fd, header)
  end

  @impl true
  def write_fragment(fd, fragment) do
    :ok = :file.write(fd, fragment)
  end

  @impl true
  def write(fd, data, location) do
    :ok = :file.pwrite(fd, location, data)
  end

  @impl true
  defdelegate close(fd), to: File
end
