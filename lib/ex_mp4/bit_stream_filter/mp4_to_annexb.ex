defmodule ExMP4.BitStreamFilter.MP4ToAnnexb do
  @moduledoc """
  An module implementing `ExMP4.BitStreamFilter` behavior to convert H264/H265
  from elementary stream to Annex B format.

  In Addition to converting the format, it also get the parameter sets VPS/SPS/PPS NALUs
  from the track `stsd` box and append them to each keyframe.

  In a future version, the filter should also get parameter sets from the
  samples and cache them to append to the next keyframes.
  """

  @behaviour ExMP4.BitStreamFilter

  alias ExMP4.{Sample, Track}

  @nalu_prefix <<0, 0, 0, 1>>

  @type t :: %__MODULE__{
          nalu_prefix_size: integer(),
          vps: list(binary()),
          sps: list(binary()),
          pps: list(binary()),
          output_structure: :annexb | :nalu
        }

  defstruct nalu_prefix_size: 0, vps: [], sps: [], pps: [], output_structure: :annexb

  @impl true
  def init(%Track{type: :video, media: media} = track, opts) when media in [:h264, :h265] do
    {:ok, init_module(track, opts)}
  end

  def init(_track, _opts) do
    {:error, :unsupported_codec}
  end

  @impl true
  def filter(state, %Sample{} = sample) do
    nalus =
      case sample.sync? do
        true ->
          Enum.concat([
            state.vps,
            state.sps,
            state.pps,
            get_nalus(sample.payload, state.nalu_prefix_size)
          ])

        false ->
          get_nalus(sample.payload, state.nalu_prefix_size)
      end

    case state.output_structure do
      :nalu ->
        {%Sample{sample | payload: nalus}, state}

      :annexb ->
        {%Sample{sample | payload: to_annexb(nalus)}, state}
    end
  end

  defp init_module(%{priv_data: %ExMP4.Box.Avcc{} = priv_data}, opts) do
    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      sps: priv_data.sps,
      pps: priv_data.pps,
      output_structure: Keyword.get(opts, :output_structure, :annexb)
    }
  end

  defp init_module(%{priv_data: %ExMP4.Box.Hvcc{} = priv_data}, opts) do
    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      vps: priv_data.vps,
      sps: priv_data.sps,
      pps: priv_data.pps,
      output_structure: Keyword.get(opts, :output_structure, :annexb)
    }
  end

  defp to_annexb(nalus) do
    for nalu <- nalus, into: <<>>, do: @nalu_prefix <> nalu
  end

  defp get_nalus(access_unit, nalu_prefix_size) do
    for <<size::size(8 * nalu_prefix_size), nalu::binary-size(size) <- access_unit>>, do: nalu
  end
end
