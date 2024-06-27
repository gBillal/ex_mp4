defmodule ExMP4.MixProject do
  use Mix.Project

  @version "0.2.0"
  @github_url "https://github.com/gBillal/ex_mp4"

  def project do
    [
      app: :ex_mp4,
      version: @version,
      elixir: "~> 1.15",
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ratio, "~> 4.0"},
      {:bunch, "~> 1.6"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
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
      extras: ["README.md", "examples/copy_track.livemd", "examples/crop.livemd", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        ExMP4,
        ExMP4.Box,
        ExMP4.Container,
        ExMP4.Read,
        ExMP4.Track,
        ExMP4.Write
      ]
    ]
  end
end
