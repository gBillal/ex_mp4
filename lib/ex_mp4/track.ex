defmodule ExMP4.Track do
  @moduledoc """
  A struct describing an MP4 track.
  """

  alias ExMP4.Container

  @type id :: non_neg_integer()

  @typedoc """
  Struct describing an mp4 track.

  The public fields are:
    * `:id` - the track id
    * `:type` - the type of the media of the track
    * `:media` - the codec used to encode the media.
    * `:duration` - the duration of the track in `:timescale` units.
    * `:timescale` - the timescale used in the track.
    * `:width` - the width of the video frames.
    * `:height` - the height of the video frames.
    * `:sample_count` - the total count of samples.
  """
  @type t :: %__MODULE__{
          id: id(),
          type: :video | :audio | :subtitle | :unknown,
          media: :h264 | :h265 | :aac | :opus | :unknown,
          priv_data: binary(),
          duration: non_neg_integer(),
          timescale: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          sample_count: non_neg_integer(),

          # private fields
          stts: list(),
          ctts: list(),
          stsc: list(),
          stco: list(),
          stsz: list(),
          stss: list(),
          sample_size: non_neg_integer()
        }

  @derive {Inspect,
           only: [:media, :priv_data, :duration, :timescale, :width, :height, :sample_count]}
  defstruct [
    :id,
    :type,
    :media,
    :priv_data,
    :duration,
    :timescale,
    :width,
    :height,
    :sample_count,
    :stts,
    :ctts,
    :stsc,
    :stsz,
    :stco,
    :stss,
    :sample_size
  ]

  @doc false
  @spec new(ExMP4.Container.t()) :: t()
  def new(trak) do
    %__MODULE__{}
    |> get_track_id(trak)
    |> get_track_type(trak)
    |> get_duration(trak)
    |> get_media(trak)
    |> get_sample_count(trak)
    |> get_private_data_structures(trak)
  end

  @doc false
  @spec sample_metadata(t(), non_neg_integer()) :: tuple()
  def sample_metadata(track, sample_id) do
    dts = sample_dts(track.stts, sample_id)
    pts = dts + sample_cts(track.ctts, sample_id)
    sync? = sync_sample?(track.stss, sample_id + 1)
    sample_size = sample_size(track, sample_id)
    sample_offset = sample_offset(track, sample_id)

    {{dts, pts}, sync?, sample_size, sample_offset}
  end

  defp get_track_id(track, trak) do
    %{
      track
      | id: Container.get_box_value(trak, [:trak, :tkhd, :track_id])
    }
  end

  defp get_track_type(track, trak) do
    type =
      case Container.get_box_value(trak, [:trak, :mdia, :hdlr, :handler_type]) do
        "soun" -> :audio
        "vide" -> :video
        _other -> :unknown
      end

    %{track | type: type}
  end

  defp get_duration(track, trak) do
    mdhd = Container.get_box(trak, [:trak, :mdia, :mdhd])

    %{
      track
      | duration: Container.get_box_value(mdhd, [:duration]),
        timescale: Container.get_box_value(mdhd, [:timescale])
    }
  end

  defp get_media(track, trak) do
    stsd = Container.get_box(trak, [:trak, :mdia, :minf, :stbl, :stsd])

    cond do
      hevc = stsd[:children][:hvc1] || stsd[:children][:hev1] ->
        %{
          track
          | media: :h265,
            width: hevc[:fields][:width],
            height: hevc[:fields][:height],
            priv_data: get_in(hevc, [:children, :hvcC, :content])
        }

      avc = stsd[:children][:avc1] || stsd[:children][:avc3] ->
        %{
          track
          | media: :h264,
            width: avc[:fields][:width],
            height: avc[:fields][:height],
            priv_data: get_in(avc, [:children, :avcC, :content])
        }

      mp4a = stsd[:children][:mp4a] ->
        %{
          track
          | media: :aac,
            priv_data: get_in(mp4a, [:children, :esds, :fields, :elementary_stream_descriptor])
        }

      true ->
        track
    end
  end

  defp get_sample_count(track, trak) do
    %{
      track
      | sample_count:
          Container.get_box_value(trak, [:trak, :mdia, :minf, :stbl, :stsz, :sample_count])
    }
  end

  defp get_private_data_structures(track, trak) do
    %{
      track
      | stts: get_box_value(trak, :stts),
        ctts: get_box_value(trak, :ctts) |> List.wrap(),
        stsc: get_box_value(trak, :stsc),
        stsz: get_box_value(trak, :stsz) |> Enum.map(& &1.entry_size),
        stco: get_box_value(trak, :stco) |> List.wrap() |> Enum.map(& &1.chunk_offset),
        stss: get_box_value(trak, :stss) |> List.wrap() |> Enum.map(& &1.sample_number),
        sample_size:
          Container.get_box_value(trak, [:trak, :mdia, :minf, :stbl, :stsz, :sample_size])
    }
  end

  defp get_box_value(trak, box_type) do
    Container.get_box_value(trak, [:trak, :mdia, :minf, :stbl, box_type, :entry_list])
  end

  defp sample_dts(stts, sample_id) do
    Enum.reduce_while(stts, {0, sample_id}, fn
      %{sample_count: count, sample_delta: delta}, {dts, id} when id < count ->
        {:halt, dts + id * delta}

      %{sample_count: count, sample_delta: delta}, {dts, id} ->
        {:cont, {dts + id * delta, id - count}}
    end)
  end

  defp sample_cts([], _sample_id), do: 0

  defp sample_cts(ctts, sample_id) do
    Enum.reduce_while(ctts, sample_id, fn
      %{sample_count: count} = entry, id when id < count ->
        {:halt, entry.sample_composition_offset}

      %{sample_count: count}, id ->
        {:cont, id - count}
    end)
  end

  defp sync_sample?([], _sample_id), do: true
  defp sync_sample?(stss, sample_id), do: Enum.member?(stss, sample_id)

  defp sample_size(%{stsz: [], sample_size: size}, _sample_id), do: size
  defp sample_size(%{stsz: stsz}, sample_id), do: Enum.at(stsz, sample_id)

  defp sample_offset(%{stsc: stsc, stco: stco, stsz: stsz}, sample_id) do
    {chunk_id, first_sample_id, sample_offset} =
      stsc
      |> Enum.chunk_every(2, 1)
      |> Enum.reduce_while(0, fn
        [entry1, entry2], id ->
          chunk_size = entry2.first_chunk - entry1.first_chunk
          max_id = id + chunk_size * entry1.samples_per_chunk

          if sample_id < max_id,
            do: {:halt, calculate_chunk_id(entry1, sample_id, id)},
            else: {:cont, max_id}

        [entry], id ->
          {:halt, calculate_chunk_id(entry, sample_id, id)}
      end)

    chunk_offset = Enum.at(stco, chunk_id - 1)
    offset_in_chunk = Enum.slice(stsz, first_sample_id, sample_offset) |> Enum.sum()

    chunk_offset + offset_in_chunk
  end

  defp calculate_chunk_id(entry, sample_id, current_id) do
    chunk_id = div(sample_id - current_id, entry.samples_per_chunk) + entry.first_chunk
    offset = rem(sample_id - current_id, entry.samples_per_chunk)

    {chunk_id, sample_id - offset, offset}
  end
end
