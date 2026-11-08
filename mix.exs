defmodule LlmToolkit.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/fosferon/llm_toolkit"

  def project do
    [
      app: :llm_toolkit,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Base code tools for agentic LLM execution — read, write, edit, bash, grep, glob, tree, http_get, and composable tool resolver architecture."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "LlmToolkit",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/{path}#L{line}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Tool Core": [LlmToolkit.Tool, LlmToolkit.Tool.Call, LlmToolkit.Tool.Result],
        Resolvers: [LlmToolkit.CodeTools, LlmToolkit.AgentResolver, LlmToolkit.Composition],
        Session: [LlmToolkit.SessionTools],
        Schema: [LlmToolkit.Trace]
      ]
    ]
  end

  defp deps do
    [
      # HTTP client (for http_get tool)
      {:req, "~> 0.5"},
      # Schema & changesets (tool_traces)
      {:ecto, "~> 3.12"},
      # Docs
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      # Test
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
