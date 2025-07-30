defmodule ExMP4.BitStreamFilter.MP4ToAnnexbTest do
  @moduledoc false

  use ExUnit.Case

  alias ExMP4.BitStreamFilter.MP4ToAnnexb
  alias ExMP4.Reader

  @sps <<103, 100, 0, 13, 172, 217, 65, 65, 250, 16, 0, 0, 3, 0, 16, 0, 0, 3, 3, 32,
         241, 66, 153, 96>>
  @pps <<104, 235, 227, 203, 34, 192>>
  @annexb_prefix <<1::32>>

  test "init mp4 to annexb filter" do
    reader = Reader.new!("test/fixtures/minimal.mp4")
    video_track = Enum.find(Reader.tracks(reader), &(&1.type == :video))

    assert {:ok, %MP4ToAnnexb{nalu_prefix_size: 4, vps: [], sps: [@sps], pps: [@pps]}} =
             MP4ToAnnexb.init(video_track, [])
  end

  test "convert mp4 to annexb" do
    reader = Reader.new!("test/fixtures/minimal.mp4")
    video_track = Enum.find(Reader.tracks(reader), &(&1.type == :video))

    assert {:ok, state} = MP4ToAnnexb.init(video_track, [])

    assert {sample, ^state} =
             MP4ToAnnexb.filter(state, Reader.read_sample(reader, video_track.id, 0))

    assert @annexb_prefix <> @sps <> @annexb_prefix <> @pps <> @annexb_prefix <> _rest = sample.payload
  end

  test "convert mp4 to nalus" do
    reader = Reader.new!("test/fixtures/minimal.mp4")
    video_track = Enum.find(Reader.tracks(reader), &(&1.type == :video))

    assert {:ok, state} = MP4ToAnnexb.init(video_track, output_structure: :nalu)

    assert {sample, ^state} =
             MP4ToAnnexb.filter(state, Reader.read_sample(reader, video_track.id, 0))

    assert [@sps, @pps, nalu1, nalu2] = sample.payload

    refute match?(<<0, 0, 0, 1, _rest::binary>>, nalu1)
    refute match?(<<0, 0, 0, 1, _rest::binary>>, nalu2)

    refute match?(<<0, 0, 1, _rest::binary>>, nalu1)
    refute match?(<<0, 0, 1, _rest::binary>>, nalu2)
  end
end
