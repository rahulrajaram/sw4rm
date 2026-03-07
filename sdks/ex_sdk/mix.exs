defmodule Sw4rm.MixProject do
  use Mix.Project

  @version "0.6.0"

  def project do
    [
      app: :sw4rm_sdk,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "SW4RM SDK",
      description: "Elixir SDK for the SW4RM multi-agent coordination protocol",
      source_url: "https://github.com/sw4rm/sw4rm-sdk-elixir",
      package: package(),
      docs: [main: "Sw4rm", extras: ["README.md"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Sw4rm.Application, []}
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.11"},
      {:protobuf, "~> 0.14"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "proto.gen": &proto_gen/1
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/rahulrajaram/sw4rm",
        "Protocol Docs" => "https://github.com/rahulrajaram/sw4rm/tree/master/documentation"
      }
    ]
  end

  defp proto_gen(_args) do
    protos_dir = Path.join([__DIR__, "..", "rust_sdk", "protos"])
    out_dir = Path.join([__DIR__, "lib", "sw4rm", "proto"])

    proto_files =
      Path.wildcard(Path.join(protos_dir, "*.proto"))
      |> Enum.join(" ")

    Mix.shell().cmd(
      "protoc --elixir_out=plugins=grpc:#{out_dir} " <>
        "-I #{protos_dir} " <>
        "-I /usr/local/include " <>
        proto_files
    )
  end
end
