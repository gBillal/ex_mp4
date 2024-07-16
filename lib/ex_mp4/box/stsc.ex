defmodule ExMP4.Box.Stsc do
  @moduledoc """
  A module representing an `stsc` box.

  Samples within the media data are grouped into chunks. Chunks can be of different sizes,
  and the samples within a chunk can have different sizes. This table can be used to find the chunk
  that contains a sample, its position, and the associated sample description.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          entries: [
            %{
              :first_chunk => integer(),
              :samples_per_chunk => integer(),
              :sample_description_index => integer(),
              :first_sample => integer() | nil
            }
          ]
        }

  defstruct version: 0, flags: 0, entries: []

  defimpl ExMP4.Box do
    def size(box), do: MP4.full_box_header_size() + 4 + 12 * length(box.entries)

    def parse(box, <<version::8, flags::24, 0::32>>) do
      %{box | version: version, flags: flags}
    end

    def parse(box, <<version::8, flags::24, entry_count::32, entries::binary>>) do
      {entries, _first_sample, <<>>} =
        Enum.reduce(1..entry_count, {[], 1, entries}, fn _idx, {entries, first_sample, data} ->
          <<first_chunk::32, samples_per_chunk::32, sample_description_index::32, rest::binary>> =
            data

          first_sample =
            case entries do
              [] ->
                first_sample

              [entry | _rest] ->
                (first_chunk - entry.first_chunk) * entry.samples_per_chunk + first_sample
            end

          entry = %{
            first_chunk: first_chunk,
            samples_per_chunk: samples_per_chunk,
            sample_description_index: sample_description_index,
            first_sample: first_sample
          }

          {[entry | entries], first_sample, rest}
        end)

      %{
        box
        | version: version,
          flags: flags,
          entries: Enum.reverse(entries)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "stsc", box.version::8, box.flags::24, length(box.entries)::32>>,
        Enum.map(
          box.entries,
          &<<&1.first_chunk::32, &1.samples_per_chunk::32, &1.sample_description_index::32>>
        )
      ]
    end
  end
end
