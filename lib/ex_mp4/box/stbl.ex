defmodule ExMP4.Box.Stbl do
  @moduledoc """
  A module representing an `stbl` box.

  The sample table contains all the time and data indexing of the media samples in a track.
  Using the tables here, it is possible to locate samples in time, determine their type (e.g. I‐frame or not),
  and determine their size, container, and offset into that container.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box.{Co64, Ctts, Stco, Stsc, Stsd, Stss, Stsz, Stz2, Stts}

  @type t :: %__MODULE__{
          stsd: Stsd.t(),
          stts: Stts.t(),
          ctts: Ctts.t() | nil,
          stss: Stss.t() | nil,
          stsz: Stsz.t() | nil,
          stz2: Stz2.t() | nil,
          stsc: Stsc.t(),
          stco: Stco.t() | nil,
          co64: Co64.t() | nil
        }

  defstruct stsd: %Stsd{},
            stts: %Stts{},
            ctts: nil,
            stss: nil,
            stsz: nil,
            stz2: nil,
            stsc: %Stsc{},
            stco: nil,
            co64: nil

  defimpl ExMP4.Box do
    def size(box) do
      ctts_size = if box.ctts, do: ExMP4.Box.size(box.ctts), else: 0
      stss_size = if box.stss, do: ExMP4.Box.size(box.stss), else: 0
      stsz_size = if box.stsz, do: ExMP4.Box.size(box.stsz), else: 0
      stz2_size = if box.stz2, do: ExMP4.Box.size(box.stz2), else: 0
      stco_size = if box.stco, do: ExMP4.Box.size(box.stco), else: 0
      co64_size = if box.co64, do: ExMP4.Box.size(box.co64), else: 0

      ExMP4.header_size() + ExMP4.Box.size(box.stsd) + ExMP4.Box.size(box.stts) +
        ExMP4.Box.size(box.stsc) +
        ctts_size + stss_size +
        stsz_size + stz2_size +
        stco_size + co64_size
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      ctts_data = if box.ctts, do: ExMP4.Box.serialize(box.ctts), else: <<>>
      stss_data = if box.stss, do: ExMP4.Box.serialize(box.stss), else: <<>>
      stsz_data = if box.stsz, do: ExMP4.Box.serialize(box.stsz), else: <<>>
      stz2_data = if box.stz2, do: ExMP4.Box.serialize(box.stz2), else: <<>>
      stco_data = if box.stco, do: ExMP4.Box.serialize(box.stco), else: <<>>
      co64_data = if box.co64, do: ExMP4.Box.serialize(box.co64), else: <<>>

      [
        <<size(box)::32, "stbl">>,
        ExMP4.Box.serialize(box.stsd),
        ExMP4.Box.serialize(box.stts),
        ctts_data,
        ExMP4.Box.serialize(box.stsc),
        stco_data,
        stsz_data,
        stss_data,
        stz2_data,
        co64_data
      ]
    end

    defp do_parse(box, <<>>), do: box

    defp do_parse(box, data) do
      {box, rest} =
        case parse_header(data) do
          {"stsd", box_data, rest} ->
            box = %{box | stsd: ExMP4.Box.parse(%Stsd{}, box_data)}
            {box, rest}

          {"stts", box_data, rest} ->
            box = %{box | stts: ExMP4.Box.parse(%Stts{}, box_data)}
            {box, rest}

          {"ctts", box_data, rest} ->
            box = %{box | ctts: ExMP4.Box.parse(%Ctts{}, box_data)}
            {box, rest}

          {"stss", box_data, rest} ->
            box = %{box | stss: ExMP4.Box.parse(%Stss{}, box_data)}
            {box, rest}

          {"stsz", box_data, rest} ->
            box = %{box | stsz: ExMP4.Box.parse(%Stsz{}, box_data)}
            {box, rest}

          {"stz2", box_data, rest} ->
            box = %{box | stz2: ExMP4.Box.parse(%Stz2{}, box_data)}
            {box, rest}

          {"stsc", box_data, rest} ->
            box = %{box | stsc: ExMP4.Box.parse(%Stsc{}, box_data)}
            {box, rest}

          {"stco", box_data, rest} ->
            box = %{box | stco: ExMP4.Box.parse(%Stco{}, box_data)}
            {box, rest}

          {"co64", box_data, rest} ->
            box = %{box | co64: ExMP4.Box.parse(%Co64{}, box_data)}
            {box, rest}

          {_box_name, _box_data, rest} ->
            {box, rest}
        end

      do_parse(box, rest)
    end
  end
end
