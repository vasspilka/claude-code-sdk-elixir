defmodule ClaudeSDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_sdk,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Elixir SDK for the Claude Code CLI",
      package: package(),
      source_url: "https://github.com/vasspilka/claude-code-sdk-elixir"
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/vasspilka/claude-code-sdk-elixir"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
