defmodule ExMP4.Write.File do
  @moduledoc """
  Implementation of the `ExMP4.Write` behaviour using filesystem.
  """

  @behaviour ExMP4.Write

  @tmp_file ".tmp"

  @impl true
  def open(filename), do: File.open(filename, [:binary, :exclusive, :read])

  @impl true
  def write(fd, data), do: IO.binwrite(fd, data)

  @impl true
  def pwrite(fd, location, data, false) do
    case :file.pwrite(fd, location, data) do
      :ok -> :ok
      {:error, reason} -> raise "could not pwrite: #{inspect(reason)}"
    end
  end

  @impl true
  def pwrite(fd, location, data, true) do
    with {:ok, fd_tmp} <- File.open(@tmp_file, [:binary, :exclusive, :read]),
         :ok <- position!(fd, location),
         {:ok, _bytes_copied} <- :file.copy(fd, fd_tmp),
         :ok <- position!(fd, location),
         :ok <- position!(fd_tmp, 0),
         :ok <- :file.truncate(fd),
         :ok <- :file.write(fd, data),
         {:ok, _bytes_copied} <- :file.copy(fd_tmp, fd),
         :ok <- :file.close(fd_tmp),
         :ok <- :file.delete(@tmp_file) do
      :ok
    else
      error -> raise "could not pwrite: #{inspect(error)}"
    end
  end

  @impl true
  def close(fd), do: File.close(fd)

  defp position!(fd, position) do
    case :file.position(fd, position) do
      {:ok, _new_pos} -> :ok
      {:error, reason} -> raise "could not seek into file: #{inspect(reason)}"
    end
  end
end
