defmodule ExMP4.Box.Stbl do
  @moduledoc """
  A module representing an `stbl` box.

  The sample table contains all the time and data indexing of the media samples in a track.
  Using the tables here, it is possible to locate samples in time, determine their type (e.g. I‐frame or not),
  and determine their size, container, and offset into that container.
  """

  import ExMP4.Box.Utils, only: [parse_header: 1]

  alias ExMP4.Box
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
      ExMP4.header_size() + Box.size(box.stsd) + Box.size(box.stts) +
        Box.size(box.ctts) + Box.size(box.stsc) + Box.size(box.stss) + Box.size(box.stsz) +
        Box.size(box.stz2) + Box.size(box.stco) + Box.size(box.co64)
    end

    def parse(box, data), do: do_parse(box, data)

    def serialize(box) do
      [
        <<size(box)::32, "stbl">>,
        Box.serialize(box.stsd),
        Box.serialize(box.stts),
        Box.serialize(box.ctts),
        Box.serialize(box.stsc),
        Box.serialize(box.stco),
        Box.serialize(box.stsz),
        Box.serialize(box.stss),
        Box.serialize(box.stz2),
        Box.serialize(box.co64)
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
