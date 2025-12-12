defmodule ExMP4.FragDataWriter.File do
  @moduledoc """
  Implementation of the `ExMP4.FragDataWriter` behaviour using filesystem (single file).
  """

  @behaviour ExMP4.FragDataWriter

  alias ExMP4.Box

  @impl true
  def open({filename, modes}), do: File.open(filename, modes ++ [:binary, :write])
  def open(filename), do: File.open(filename, [:binary, :write])

  @impl true
  def write_init_header(fd, header) do
    :ok = :file.write(fd, Box.serialize(header))
    fd
  end

  @impl true
  def write_segment(fd, segment) do
    :ok = :file.write(fd, Box.serialize(segment))
    fd
  end

  @impl true
  def write(fd, data, location) do
    :ok = :file.pwrite(fd, location, data)
    fd
  end

  @impl true
  defdelegate close(fd), to: File
end
