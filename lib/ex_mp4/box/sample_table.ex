defmodule ExMP4.Box.SampleTable do
  @moduledoc false

  alias ExMP4.{Container, Track}
  alias ExMP4.Track.SampleTable

  @spec assemble(Track.t()) :: Container.t()
  def assemble(track) do
    table = track.sample_table

    sample_description = assemble_sample_description(track)
    sample_deltas = table.decoding_deltas
    maybe_sample_sync = maybe_sample_sync(table)
    sample_to_chunk = assemble_sample_to_chunk(table)
    sample_sizes = assemble_sample_sizes(table)
    chunk_offsets = assemble_chunk_offsets(table)

    [
      stbl: %{
        children:
          [
            stsd: %{
              children: sample_description,
              fields: %{
                entry_count: length(sample_description),
                flags: 0,
                version: 0
              }
            },
            stts: %{
              fields: %{
                version: 0,
                flags: 0,
                entry_count: length(sample_deltas),
                entry_list: sample_deltas
              }
            }
          ] ++
            maybe_sample_sync ++
            [
              stsc: %{
                fields: %{
                  version: 0,
                  flags: 0,
                  entry_count: length(sample_to_chunk),
                  entry_list: sample_to_chunk
                }
              },
              stsz: %{
                fields: %{
                  version: 0,
                  flags: 0,
                  sample_size: 0,
                  sample_count: table.sample_count,
                  entry_list: sample_sizes
                }
              },
              stco: %{
                fields: %{
                  version: 0,
                  flags: 0,
                  entry_count: length(chunk_offsets),
                  entry_list: chunk_offsets
                }
              }
            ],
        fields: %{}
      }
    ]
  end

  defp assemble_sample_description(%Track{media: media} = track) when media in [:h264, :h265] do
    {codec_tag, content_tag} = if media == :h264, do: {:avc1, :avcC}, else: {:hvc1, :hvcC}

    [
      {codec_tag,
       %{
         children: [
           {content_tag,
            %{
              content: track.priv_data
            }},
           pasp: %{
             children: [],
             fields: %{h_spacing: 1, v_spacing: 1}
           }
         ],
         fields: %{
           compressor_name: <<0::size(32)-unit(8)>>,
           depth: 24,
           flags: 0,
           frame_count: 1,
           height: track.height,
           horizresolution: {0, 0},
           num_of_entries: 1,
           version: 0,
           vertresolution: {0, 0},
           width: track.width
         }
       }}
    ]
  end

  defp assemble_sample_description(%Track{media: :aac} = track) do
    [
      mp4a: %{
        children: %{
          esds: %{
            fields: %{
              elementary_stream_descriptor: track.priv_data,
              flags: 0,
              version: 0
            }
          }
        },
        fields: %{
          channel_count: track.channels,
          compression_id: 0,
          data_reference_index: 1,
          encoding_revision: 0,
          encoding_vendor: 0,
          encoding_version: 0,
          packet_size: 0,
          sample_size: 16,
          sample_rate: {track.sample_rate, 0}
        }
      }
    ]
  end

  # defp assemble_sample_description(%Opus{channels: channels}) do
  #   [
  #     Opus: %{
  #       children: %{
  #         dOps: %{
  #           fields: %{
  #             version: 0,
  #             output_channel_count: channels,
  #             pre_skip: 413,
  #             input_sample_rate: 0,
  #             output_gain: 0,
  #             channel_mapping_family: 0
  #           }
  #         }
  #       },
  #       fields: %{
  #         data_reference_index: 0,
  #         channel_count: channels,
  #         sample_size: 16,
  #         sample_rate: Bitwise.bsl(48_000, 16)
  #       }
  #     }
  #   ]
  # end

  # defp assemble_sample_deltas(%{timescale: timescale, decoding_deltas: decoding_deltas}),
  #   do:
  #     Enum.map(decoding_deltas, fn %{sample_count: count, sample_delta: delta} ->
  #       %{sample_count: count, sample_delta: Helper.timescalify(delta, timescale)}
  #     end)

  defp maybe_sample_sync(%{sync_samples: []}), do: []

  defp maybe_sample_sync(%{sync_samples: sync_samples}) do
    sync_samples
    |> Enum.map(&%{sample_number: &1})
    |> then(
      &[
        stss: %{
          fields: %{
            version: 0,
            flags: 0,
            entry_count: length(&1),
            entry_list: &1
          }
        }
      ]
    )
  end

  defp assemble_sample_to_chunk(%{samples_per_chunk: samples_per_chunk}),
    do:
      Enum.map(
        samples_per_chunk,
        &%{
          first_chunk: &1.first_chunk,
          samples_per_chunk: &1.sample_count,
          sample_description_index: 1
        }
      )

  defp assemble_sample_sizes(%{sample_sizes: sample_sizes}),
    do: Enum.map(sample_sizes, &%{entry_size: &1})

  defp assemble_chunk_offsets(%{chunk_offsets: chunk_offsets}),
    do: Enum.map(chunk_offsets, &%{chunk_offset: &1})

  @spec unpack(%{children: Container.t(), fields: map()}) :: SampleTable.t()
  def unpack(%{children: boxes}) do
    %SampleTable{
      sample_count: boxes[:stsz].fields.sample_count,
      sample_sizes: unpack_sample_sizes(boxes[:stsz]),
      sample_size: unpack_sample_size(boxes[:stsz]),
      chunk_offsets: unpack_chunk_offsets(boxes[:stco] || boxes[:co64]),
      decoding_deltas: boxes[:stts].fields.entry_list,
      composition_offsets: get_composition_offsets(boxes),
      samples_per_chunk: boxes[:stsc].fields.entry_list
    }
  end

  defp get_composition_offsets(boxes) do
    if :ctts in Keyword.keys(boxes) do
      boxes[:ctts].fields.entry_list
    else
      # if no :ctts box is available, assume that the offset between
      # composition time and the decoding time is equal to 0
      Enum.map(boxes[:stts].fields.entry_list, fn entry ->
        %{sample_count: entry.sample_count, sample_composition_offset: 0}
      end)
    end
  end

  defp unpack_chunk_offsets(%{fields: %{entry_list: offsets}}) do
    offsets |> Enum.map(fn %{chunk_offset: offset} -> offset end)
  end

  defp unpack_sample_size(%{fields: %{sample_size: size}}), do: size

  defp unpack_sample_sizes(%{fields: %{entry_list: sizes}}) do
    sizes |> Enum.map(fn %{entry_size: size} -> size end)
  end
end
