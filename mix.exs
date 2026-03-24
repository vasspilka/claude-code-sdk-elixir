defmodule ClaudeSDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_sdk,
      version: "0.2.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Elixir SDK for the Claude Code CLI",
      package: package(),
      source_url: "https://github.com/vasspilka/claude-code-sdk-elixir",
      homepage_url: "https://github.com/vasspilka/claude-code-sdk-elixir",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/multi-turn-conversations.md",
        "guides/mcp-servers.md",
        "guides/protocol-and-architecture.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: [
          "guides/getting-started.md",
          "guides/multi-turn-conversations.md",
          "guides/mcp-servers.md",
          "guides/protocol-and-architecture.md"
        ]
      ],
      groups_for_modules: [
        Core: [ClaudeSDK, ClaudeSDK.Client, ClaudeSDK.Sessions],
        MCP: [
          ClaudeSDK.MCP.Server,
          ClaudeSDK.MCP.Tool,
          ClaudeSDK.MCP.StdioServerConfig,
          ClaudeSDK.MCP.SSEServerConfig,
          ClaudeSDK.MCP.HttpServerConfig
        ],
        "Message Types": [
          ClaudeSDK.Types.AssistantMessage,
          ClaudeSDK.Types.UserMessage,
          ClaudeSDK.Types.SystemMessage,
          ClaudeSDK.Types.ResultMessage,
          ClaudeSDK.Types.StreamEvent,
          ClaudeSDK.Types.ControlRequest,
          ClaudeSDK.Types.ControlResponse,
          ClaudeSDK.Types.TaskStartedMessage,
          ClaudeSDK.Types.TaskProgressMessage,
          ClaudeSDK.Types.TaskNotificationMessage,
          ClaudeSDK.Types.RateLimitEvent
        ],
        "Content Blocks": [
          ClaudeSDK.Types.TextBlock,
          ClaudeSDK.Types.ThinkingBlock,
          ClaudeSDK.Types.ToolUseBlock,
          ClaudeSDK.Types.ToolResultBlock
        ],
        Configuration: [
          ClaudeSDK.Types.Options,
          ClaudeSDK.Types.AgentDefinition,
          ClaudeSDK.Types.ThinkingConfig,
          ClaudeSDK.Types.SandboxSettings,
          ClaudeSDK.Types.ToolPermissionContext
        ],
        Errors: [
          ClaudeSDK.CLINotFoundError,
          ClaudeSDK.TransportError,
          ClaudeSDK.ProtocolError,
          ClaudeSDK.QueryError,
          ClaudeSDK.TimeoutError
        ],
        Internal: [
          ClaudeSDK.MessageParser,
          ClaudeSDK.ControlRouter,
          ClaudeSDK.Transport.Subprocess,
          ClaudeSDK.Transport.CommandBuilder,
          ClaudeSDK.Transport.CLIDiscovery,
          ClaudeSDK.Transport.LineBuffer
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib guides .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
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
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
