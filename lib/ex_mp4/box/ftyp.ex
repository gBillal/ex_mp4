defmodule ExMP4.Box.Ftyp do
  @moduledoc """
  A module repsenting an `ftyp` box.
  """

  @type t :: %__MODULE__{
          major_brand: String.t(),
          minor_version: integer(),
          compatible_brands: [String.t()]
        }

  defstruct major_brand: "isom",
            minor_version: 512,
            compatible_brands: ["isom", "iso2", "avc1", "mp41"]

  defimpl ExMP4.Box do
    def size(box) do
      ExMP4.header_size() + length(box.compatible_brands) * 4 + 8
    end

    def parse(box, <<major_brand::binary-size(4), version::32, rest::binary>>) do
      %{
        box
        | major_brand: major_brand,
          minor_version: version,
          compatible_brands: for(<<brand::binary-size(4) <- rest>>, do: brand)
      }
    end

    def serialize(box) do
      [
        <<size(box)::32, "ftyp", box.major_brand::binary, box.minor_version::32>>,
        box.compatible_brands
      ]
    end
  end
end
