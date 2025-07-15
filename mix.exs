defmodule ExMP4.MixProject do
  use Mix.Project

  @version "0.10.0"
  @github_url "https://github.com/gBillal/ex_mp4"

  def project do
    [
      app: :ex_mp4,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "MP4 reader and writer",
      package: package(),

      # docs
      name: "MP4 Reader and Writer",
      source_url: @github_url,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ratio, "~> 4.0"},
      {:bunch, "~> 1.6"},
      {:media_codecs, "~> 0.7.0", optional: true},
      {:table_rex, "~> 4.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Billal Ghilas"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "examples/copy_track.livemd",
        "examples/crop.livemd",
        "examples/progressive_to_fragmented.livemd",
        "LICENSE"
      ],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        ExMP4.BitStreamFilter,
        ExMP4.Box,
        ExMP4.Track
      ],
      groups_for_modules: [
        Core: [
          "ExMP4",
          "ExMP4.Track",
          "ExMP4.Reader",
          "ExMP4.Writer",
          "ExMP4.FWriter",
          "ExMP4.Sample",
          "ExMP4.SampleMetadata",
          "ExMP4.Helper"
        ],
        Display: [
          "ExMP4.Reader.Display"
        ],
        Behaviour: [
          ~r/^ExMP4\.DataReader($|\.)/,
          ~r/^ExMP4\.DataWriter($|\.)/,
          ~r/^ExMP4\.FragDataWriter($|\.)/
        ],
        BitStream: ~r/^ExMP4\.BitStreamFilter($|\.)/,
        Box: ~r/^ExMP4\.Box($|\.)/
      ]
    ]
  end
end
