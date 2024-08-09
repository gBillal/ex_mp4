defmodule ExMP4.Box.Tfhd do
  @moduledoc """
  A module representing an `tfhd` box.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          base_is_moof?: boolean(),
          track_id: integer(),
          base_data_offset: integer() | nil,
          sample_description_index: integer() | nil,
          default_sample_duration: integer() | nil,
          default_sample_size: integer() | nil,
          default_sample_flags: integer() | nil
        }

  defstruct version: 0,
            flags: 0,
            base_is_moof?: false,
            track_id: 0,
            base_data_offset: 0,
            sample_description_index: nil,
            default_sample_duration: nil,
            default_sample_size: nil,
            default_sample_flags: nil

  defimpl ExMP4.Box do
    @fields_with_mask [
      {:base_data_offset, 0x1, 8},
      {:sample_description_index, 0x2, 4},
      {:default_sample_duration, 0x8, 4},
      {:default_sample_size, 0x10, 4},
      {:default_sample_flags, 0x20, 4}
    ]

    def size(%{flags: flags}) do
      Enum.reduce(@fields_with_mask, ExMP4.full_box_header_size() + 4, fn {_field, mask, size},
                                                                          total ->
        if Bitwise.band(flags, mask) != 0, do: total + size, else: total
      end)
    end

    def parse(box, <<version::8, flags::24, track_id::32, rest::binary>>) do
      {box, <<>>} =
        Enum.reduce(@fields_with_mask, {box, rest}, fn {field, mask, size}, {box, rest} ->
          if Bitwise.band(flags, mask) != 0 do
            <<value::size(8 * size), rest::binary>> = rest
            {Map.put(box, field, value), rest}
          else
            {box, rest}
          end
        end)

      %{
        box
        | version: version,
          flags: flags,
          base_is_moof?: Bitwise.band(flags, 0x1) == 0 and Bitwise.band(flags, 0x20000) != 0,
          track_id: track_id
      }
    end

    def serialize(box) do
      data =
        Enum.reduce(@fields_with_mask, [], fn {field, mask, size}, data ->
          if Bitwise.band(box.flags, mask) != 0 do
            [<<Map.get(box, field)::size(8 * size)>> | data]
          else
            data
          end
        end)

      [
        <<size(box)::32, "tfhd", box.version::8, box.flags::24, box.track_id::32>>,
        Enum.reverse(data)
      ]
    end
  end
end
