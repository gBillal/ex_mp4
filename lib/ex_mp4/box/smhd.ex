defmodule ExMP4.Box.Smhd do
  @moduledoc """
  A module representing a `smhd` box.

  The sound media header contains general presentation information, independent of the coding, for audio media.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          balance: integer()
        }

  defstruct version: 0, flags: 0, balance: 0

  defimpl ExMP4.Box do
    def size(_box), do: MP4.full_box_header_size() + 4

    def parse(box, <<version::8, flags::24, balance::16, 0::16>>) do
      %{
        box
        | version: version,
          flags: flags,
          balance: balance
      }
    end

    def serialize(box) do
      <<size(box)::32, "smhd", box.version::8, box.flags::24, box.balance::16, _reserved = 0::16>>
    end
  end
end
