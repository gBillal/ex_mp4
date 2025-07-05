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
          pps: list(binary())
        }

  defstruct nalu_prefix_size: 0, vps: [], sps: [], pps: []

  @impl true
  def init(%Track{type: :video, media: media} = track, _opts) when media in [:h264, :h265] do
    {:ok, init_module(track)}
  end

  def init(_track, _opts) do
    {:error, :unsupported_codec}
  end

  @impl true
  def filter(state, %Sample{} = sample) do
    payload =
      case sample.sync? do
        true -> get_parameter_sets(state) <> to_annexb(sample.payload, state.nalu_prefix_size)
        false -> to_annexb(sample.payload, state.nalu_prefix_size)
      end

    {%Sample{sample | payload: payload}, state}
  end

  defp init_module(%{priv_data: %ExMP4.Box.Avcc{} = priv_data}) do
    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      sps: Enum.map(priv_data.sps, &(@nalu_prefix <> &1)),
      pps: Enum.map(priv_data.pps, &(@nalu_prefix <> &1))
    }
  end

  defp init_module(%{priv_data: %ExMP4.Box.Hvcc{} = priv_data}) do
    %__MODULE__{
      nalu_prefix_size: priv_data.nalu_length_size,
      vps: Enum.map(priv_data.vps, &(@nalu_prefix <> &1)),
      sps: Enum.map(priv_data.sps, &(@nalu_prefix <> &1)),
      pps: Enum.map(priv_data.pps, &(@nalu_prefix <> &1))
    }
  end

  defp get_parameter_sets(state), do: Enum.join(state.vps ++ state.sps ++ state.pps)

  defp to_annexb(access_unit, nalu_prefix_size) do
    for <<size::size(8 * nalu_prefix_size), nalu::binary-size(size) <- access_unit>>,
      into: <<>>,
      do: @nalu_prefix <> nalu
  end
end
