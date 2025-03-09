defmodule ExMP4.Box.Sidx do
  @moduledoc """
  A module representing `sidx` box.

  This box provides a compact index of one media stream within the media segment to which it applies
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          reference_id: integer() | nil,
          timescale: integer() | nil,
          earliest_presentation_time: integer(),
          first_offset: integer(),
          entries: [
            %{
              :reference_type => integer(),
              :referenced_size => integer(),
              :subsegment_duration => integer(),
              :starts_with_sap => integer(),
              :sap_type => integer(),
              :sap_delta_time => integer()
            }
          ]
        }

  defstruct version: 0,
            flags: 0,
            reference_id: nil,
            timescale: nil,
            earliest_presentation_time: 0,
            first_offset: 0,
            entries: []

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.full_box_header_size() + 12 + length(box.entries) * 12 + (box.version + 1) * 8
    end

    def parse(
          box,
          <<version::8, flags::24, reference_id::32, timescale::32,
            earliest_presentation_time::(version + 1)*32, first_offset::(version + 1)*32, 0::16,
            _reference_count::16, rest::binary>>
        ) do
      entries =
        for <<reference_type::1, reference_size::31, subsegment_duration::32, starts_with_sap::1,
              sap_type::3, sap_delta_time::28 <- rest>> do
          %{
            reference_type: reference_type,
            referenced_size: reference_size,
            subsegment_duration: subsegment_duration,
            starts_with_sap: starts_with_sap,
            sap_type: sap_type,
            sap_delta_time: sap_delta_time
          }
        end

      %{
        box
        | version: version,
          flags: flags,
          reference_id: reference_id,
          timescale: timescale,
          earliest_presentation_time: earliest_presentation_time,
          first_offset: first_offset,
          entries: entries
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "sidx", box.version::8, box.flags::24, box.reference_id::32,
          box.timescale::32, box.earliest_presentation_time::(box.version + 1)*32,
          box.first_offset::(box.version + 1)*32, 0::16, length(box.entries)::16>>,
        Enum.map(
          box.entries,
          &<<&1.reference_type::1, &1.referenced_size::31, &1.subsegment_duration::32,
            &1.starts_with_sap::1, &1.sap_type::3, &1.sap_delta_time::28>>
        )
      ]
    end
  end
end
