defmodule ExMP4.Box.DataEntryURL do
  @moduledoc """
  Module representing a `url ` box in an MP4 file.
  """

  import ExMP4, only: [full_box_header_size: 0]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          flags: non_neg_integer(),
          location: String.t() | nil
        }

  defstruct version: 0, flags: 1, location: nil

  defimpl ExMP4.Box do
    def size(%{flags: 1}), do: full_box_header_size()
    def size(box), do: full_box_header_size() + byte_size(box.location)

    def parse(box, <<0::8, 1::24>>), do: box

    def parse(box, <<0::8, flags::24, location::binary>>),
      do: %{box | flags: flags, location: location}

    def serialize(box) do
      location = if box.flags == 1, do: <<>>, else: box.location
      <<size(box)::32, "url ", box.version::8, box.flags::24, location::binary>>
    end
  end
end
