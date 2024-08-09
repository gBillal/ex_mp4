defmodule ExMP4.Box.Mehd do
  @moduledoc """
  A module representing an `mehd` box.

  The Movie Extends Header is optional, and provides the overall duration, including fragments,
  of a fragmented movie. If this box is not present, the overall duration must be computed
  by examining each fragment.
  """

  @type t :: %__MODULE__{
          version: integer(),
          flags: integer(),
          fragment_duration: integer()
        }

  defstruct version: 0, flags: 0, fragment_duration: 0

  defimpl ExMP4.Box do
    def size(%{version: 0}), do: ExMP4.full_box_header_size() + 4
    def size(%{version: 1}), do: ExMP4.full_box_header_size() + 8

    def parse(box, <<version::8, flags::24, fragment_duration::size(32 * (version + 1))>>) do
      %{box | version: version, flags: flags, fragment_duration: fragment_duration}
    end

    def serialize(box) do
      <<size(box)::32, "mehd", box.version::8, box.flags::24,
        box.fragment_duration::size(32 * (box.version + 1))>>
    end
  end
end
