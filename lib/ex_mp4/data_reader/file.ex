defmodule ExMP4.DataReader.File do
  @moduledoc """
  Implementation of the `ExMP4.DataReader` behaviour using filesystem.
  """

  @behaviour ExMP4.DataReader

  @impl true
  def open({:binary, data}), do: File.open(data, [:binary, :ram, :read])

  def open(filename), do: File.open(filename, [:binary, :raw, :read])

  @impl true
  def read(fd, chars, location \\ nil)

  def read(fd, chars, nil), do: IO.binread(fd, chars)

  def read(fd, chars, location) do
    {:ok, data} = :file.pread(fd, location, chars)
    data
  end

  @impl true
  def seek(fd, location) do
    {:ok, _new_pos} = :file.position(fd, location)
    :ok
  end

  @impl true
  def close(fd), do: File.close(fd)
end
