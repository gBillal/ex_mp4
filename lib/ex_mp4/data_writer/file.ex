defmodule ExMP4.DataWriter.File do
  @moduledoc """
  Implementation of the `ExMP4.DataWriter` behaviour using filesystem (single file).
  """

  @behaviour ExMP4.DataWriter

  @impl true
  def open({filename, modes}), do: do_open(filename, modes ++ [:binary, :read])

  def open(filename), do: do_open(filename, [:binary, :exclusive, :read])

  @impl true
  def write(_state, data, loc \\ nil, insert? \\ false)

  def write({fd, _filename}, data, nil, _insert?) do
    :ok = :file.write(fd, data)
  end

  def write({fd, _filename}, data, loc, false) do
    :ok = :file.pwrite(fd, loc, data)
  end

  def write({fd, filename}, data, loc, true) do
    tmp_file = filename <> ".tmp"

    with {:ok, fd_tmp} <- File.open(tmp_file, [:binary, :exclusive, :read]),
         :ok <- position!(fd, loc),
         {:ok, _bytes_copied} <- :file.copy(fd, fd_tmp),
         :ok <- position!(fd, loc),
         :ok <- position!(fd_tmp, 0),
         :ok <- :file.truncate(fd),
         :ok <- :file.write(fd, data),
         {:ok, _bytes_copied} <- :file.copy(fd_tmp, fd),
         :ok <- :file.close(fd_tmp),
         :ok <- :file.delete(tmp_file) do
      :ok
    else
      error -> raise "cannot pwrite: #{inspect(error)}"
    end
  end

  @impl true
  def close({fd, _filename}) do
    :ok = File.close(fd)
  end

  defp do_open(filename, modes) do
    with {:ok, fd} <- File.open(filename, modes) do
      {:ok, {fd, filename}}
    end
  end

  defp position!(fd, position) do
    case :file.position(fd, position) do
      {:ok, _new_pos} -> :ok
      {:error, reason} -> raise "cannot seek into file: #{inspect(reason)}"
    end
  end
end
