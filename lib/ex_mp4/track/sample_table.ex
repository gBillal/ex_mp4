defmodule ExMP4.Track.SampleTable do
  @moduledoc """
  A module that defines a structure and functions allowing to store samples,
  assemble them into chunks and flush when needed. Its public functions take
  care of recording information required to build a sample table.
  """

  alias ExMP4.Sample

  @type t :: %__MODULE__{
          chunk: [binary],
          chunk_first_dts: non_neg_integer | nil,
          last_dts: non_neg_integer | nil,
          sample_count: non_neg_integer,
          sample_sizes: [pos_integer],
          sync_samples: [pos_integer],
          chunk_offsets: [non_neg_integer],
          decoding_deltas: [
            %{
              sample_delta: Ratio.t(),
              sample_count: pos_integer
            }
          ],
          composition_offsets: [
            %{
              sample_composition_offset: Ratio.t(),
              sample_count: pos_integer
            }
          ],
          samples_per_chunk: [
            %{
              first_chunk: pos_integer,
              sample_count: pos_integer
            }
          ],
          sample_size: non_neg_integer,
          sample_index: non_neg_integer,
          elapsed_duration: non_neg_integer,
          chunk_sample_index: non_neg_integer
        }

  defstruct chunk: [],
            chunk_first_dts: nil,
            last_dts: nil,
            sample_count: 0,
            sample_size: 0,
            sample_sizes: [],
            sync_samples: [],
            chunk_offsets: [],
            decoding_deltas: [],
            composition_offsets: [],
            samples_per_chunk: [],
            # Used for Enumerable
            sample_index: 1,
            elapsed_duration: 0,
            chunk_sample_index: 1

  @doc """
  Store a new sample.
  """
  @spec store_sample(t(), Sample.t()) :: t()
  def store_sample(sample_table, sample) do
    sample_table
    |> maybe_store_first_dts(sample)
    |> do_store_sample(sample)
    |> update_decoding_deltas(sample)
    |> update_composition_offsets(sample)
    |> maybe_store_sync_sample(sample)
    |> store_last_dts(sample)
  end

  @doc """
  Get the total size of the samples in the sample table.
  """
  @spec total_size(t()) :: non_neg_integer()
  def total_size(%{sample_sizes: [], sample_size: size, sample_count: count}), do: size * count
  def total_size(%{sample_sizes: sample_sizes}), do: Enum.sum(sample_sizes)

  @doc """
  Get the current chunk duration.

  Samples are added and buffered in the sample table into chunks, once a chunk duration
  is reached, it can be flushed using `flush_chunk/2`.
  """
  @spec chunk_duration(__MODULE__.t()) :: ExMP4.duration()
  def chunk_duration(%{chunk_first_dts: nil}), do: 0

  def chunk_duration(sample_table) do
    use Numbers, overload_operators: true
    sample_table.last_dts - sample_table.chunk_first_dts
  end

  @doc """
  Flush the current chunk.

  Flushing update the internal structure of the sample table and assemble
  the samples payload into a binary that can be stored.
  """
  @spec flush_chunk(__MODULE__.t(), non_neg_integer) :: {binary, __MODULE__.t()}
  def flush_chunk(%{chunk: []} = sample_table, _chunk_offset),
    do: {<<>>, sample_table}

  def flush_chunk(sample_table, chunk_offset) do
    chunk = sample_table.chunk

    sample_table =
      sample_table
      |> Map.update!(:chunk_offsets, &[chunk_offset | &1])
      |> update_samples_per_chunk(length(chunk))
      |> Map.merge(%{chunk: [], chunk_first_dts: nil})

    chunk = chunk |> Enum.reverse() |> Enum.join()

    {chunk, sample_table}
  end

  @doc false
  @spec reverse(__MODULE__.t()) :: __MODULE__.t()
  def reverse(sample_table) do
    to_reverse = [
      :sample_sizes,
      :sync_samples,
      :chunk_offsets,
      :decoding_deltas,
      :composition_offsets,
      :samples_per_chunk
    ]

    Enum.reduce(to_reverse, sample_table, fn key, sample_table ->
      reversed = sample_table |> Map.fetch!(key) |> Enum.reverse()

      %{sample_table | key => reversed}
    end)
  end

  @doc false
  @spec next_sample(t()) :: {t(), ExMP4.SampleMetadata.t()}
  def next_sample(sample_table) do
    {sample_table, %ExMP4.SampleMetadata{}}
    |> sample_timestamps()
    |> sync_sample()
    |> sample_size()
    |> sample_offset()
  end

  defp do_store_sample(sample_table, %{payload: payload}) do
    Map.merge(sample_table, %{
      chunk: [payload | sample_table.chunk],
      sample_sizes: [byte_size(payload) | sample_table.sample_sizes],
      sample_count: sample_table.sample_count + 1
    })
  end

  defp maybe_store_first_dts(%{chunk: []} = sample_table, %Sample{dts: dts}),
    do: %{sample_table | chunk_first_dts: dts}

  defp maybe_store_first_dts(sample_table, _buffer), do: sample_table

  defp update_decoding_deltas(%{last_dts: nil} = sample_table, _buffer) do
    Map.put(sample_table, :decoding_deltas, [%{sample_count: 1, sample_delta: 0}])
  end

  defp update_decoding_deltas(sample_table, %Sample{dts: dts}) do
    Map.update!(sample_table, :decoding_deltas, fn previous_deltas ->
      use Numbers, overload_operators: true
      new_delta = dts - sample_table.last_dts

      case previous_deltas do
        # there was only one sample in the sample table - we should assume its delta is
        # equal to the one of the second sample
        [%{sample_count: 1, sample_delta: 0}] ->
          [%{sample_count: 2, sample_delta: new_delta}]

        # the delta did not change, simply increase the counter in the last entry to save space
        [%{sample_count: count, sample_delta: ^new_delta} | rest] ->
          [%{sample_count: count + 1, sample_delta: new_delta} | rest]

        #
        [entry | rest] ->
          [
            %{sample_count: 2, sample_delta: new_delta},
            %{entry | sample_count: entry.sample_count - 1} | rest
          ]
      end
    end)
  end

  defp update_composition_offsets(%{last_dts: nil} = sample_table, sample) do
    offset = sample.pts - sample.dts

    Map.put(sample_table, :composition_offsets, [
      %{sample_count: 1, sample_composition_offset: offset}
    ])
  end

  defp update_composition_offsets(sample_table, %Sample{dts: dts, pts: pts}) do
    Map.update!(sample_table, :composition_offsets, fn previous_offsets ->
      new_offset = pts - dts

      case previous_offsets do
        [%{sample_count: count, sample_composition_offset: ^new_offset} | rest] ->
          [%{sample_count: count + 1, sample_composition_offset: new_offset} | rest]

        _different_delta_or_empty ->
          [%{sample_count: 1, sample_composition_offset: new_offset} | previous_offsets]
      end
    end)
  end

  defp maybe_store_sync_sample(sample_table, %Sample{sync?: true}) do
    Map.update!(sample_table, :sync_samples, &[sample_table.sample_count | &1])
  end

  defp maybe_store_sync_sample(sample_table, _buffer), do: sample_table

  defp store_last_dts(sample_table, %Sample{dts: dts}), do: %{sample_table | last_dts: dts}

  defp update_samples_per_chunk(sample_table, sample_count) do
    Map.update!(sample_table, :samples_per_chunk, fn previous_chunks ->
      case previous_chunks do
        [%{first_chunk: _, sample_count: ^sample_count} | _rest] ->
          previous_chunks

        _different_count ->
          [
            %{first_chunk: length(sample_table.chunk_offsets), sample_count: sample_count}
            | previous_chunks
          ]
      end
    end)
  end

  defp sample_timestamps({%{elapsed_duration: duration} = sample_table, element}) do
    {delta, decoding_deltas} =
      case sample_table.decoding_deltas do
        [%{sample_count: 1, sample_delta: delta} | decoding_deltas] ->
          {delta, decoding_deltas}

        [%{sample_count: count, sample_delta: delta} = entry | decoding_deltas] ->
          {delta, [%{entry | sample_count: count - 1} | decoding_deltas]}
      end

    {offset, composition_offsets} =
      case sample_table.composition_offsets do
        [%{sample_count: 1, sample_composition_offset: offset} | composition_offsets] ->
          {offset, composition_offsets}

        [%{sample_count: count, sample_composition_offset: offset} | composition_offsets] ->
          {offset,
           [
             %{sample_count: count - 1, sample_composition_offset: offset}
             | composition_offsets
           ]}
      end

    element = %{element | dts: duration, pts: duration + offset, duration: delta}

    sample_table = %{
      sample_table
      | decoding_deltas: decoding_deltas,
        composition_offsets: composition_offsets,
        elapsed_duration: duration + delta
    }

    {sample_table, element}
  end

  defp sync_sample({%{sample_index: idx} = sample_table, element}) do
    {sync?, sync_samples} =
      case sample_table.sync_samples do
        [] -> {true, []}
        [^idx] -> {true, [idx]}
        [^idx | sync_samples] -> {true, sync_samples}
        sync_samples -> {false, sync_samples}
      end

    {%{sample_table | sync_samples: sync_samples, sample_index: idx + 1},
     %{element | sync?: sync?}}
  end

  defp sample_size({%{sample_sizes: []} = sample_table, element}) do
    {sample_table, %{element | size: sample_table.sample_size}}
  end

  defp sample_size({sample_table, element}) do
    [sample_size | sample_sizes] = sample_table.sample_sizes
    {%{sample_table | sample_sizes: sample_sizes}, %{element | size: sample_size}}
  end

  defp sample_offset({sample_table, element}) do
    %{
      chunk_offsets: chunk_offsets,
      samples_per_chunk: samples_per_chunk,
      chunk_sample_index: index
    } = sample_table

    [chunk_offset | chunk_offsets] = chunk_offsets

    {samples_per_chunk, offset, chunk_offsets, index} =
      case samples_per_chunk do
        [%{samples_per_chunk: ^index} = entry | samples_per_chunk] ->
          samples_per_chunk = [
            %{entry | first_chunk: entry.first_chunk + 1} | samples_per_chunk
          ]

          {samples_per_chunk, chunk_offset, chunk_offsets, 1}

        samples_per_chunk ->
          {samples_per_chunk, chunk_offset, [chunk_offset + element.size | chunk_offsets],
           index + 1}
      end

    samples_per_chunk =
      case samples_per_chunk do
        [%{first_chunk: chunk}, %{first_chunk: chunk} = entry | samples_per_chunk] ->
          [entry | samples_per_chunk]

        samples_per_chunk ->
          samples_per_chunk
      end

    sample_table = %{
      sample_table
      | chunk_offsets: chunk_offsets,
        samples_per_chunk: samples_per_chunk,
        chunk_sample_index: index
    }

    {sample_table, %{element | offset: offset}}
  end
end
