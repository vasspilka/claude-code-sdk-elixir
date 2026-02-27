defmodule ClaudeSDK.Types.AssistantMessage do
  @moduledoc """
  A message from the assistant containing content blocks.

  Yielded during streaming when the CLI produces a response. The `message.content`
  list contains typed blocks: `TextBlock`, `ThinkingBlock`, or `ToolUseBlock`.

  ## Fields

  - `message` — Map with `:content` (list of content blocks) and `:model` (model ID string or nil).
  - `parent_tool_use_id` — When non-nil, indicates this message is a nested response
    within a tool-use flow.
  - `error` — Error map if the CLI reported an error with this message.

  ## Pattern Matching

      Enum.each(stream, fn
        %AssistantMessage{message: %{content: blocks}} ->
          Enum.each(blocks, fn
            %TextBlock{text: text} -> IO.puts(text)
            %ThinkingBlock{thinking: thought} -> IO.puts("[thinking] \#{thought}")
            %ToolUseBlock{name: name} -> IO.puts("[tool] \#{name}")
            _ -> :ok
          end)
        _ -> :ok
      end)
  """

  alias ClaudeSDK.Types.{TextBlock, ThinkingBlock, ToolUseBlock}

  @type content_block :: TextBlock.t() | ThinkingBlock.t() | ToolUseBlock.t()

  @type t :: %__MODULE__{
          type: :assistant,
          message: %{
            content: [content_block()],
            model: String.t() | nil
          },
          parent_tool_use_id: String.t() | nil,
          error: map() | nil
        }

  defstruct type: :assistant,
            message: %{content: [], model: nil},
            parent_tool_use_id: nil,
            error: nil
end

defmodule ClaudeSDK.Types.UserMessage do
  @moduledoc """
  A user message, either sent by the SDK or echoed back from the CLI.

  Appears in the stream when the CLI echoes back a user message. Useful for
  tracking message UUIDs when using `ClaudeSDK.Client.rewind_files/2`.

  ## Fields

  - `message` — Map with `:role` (always `:user`) and `:content` (string or list).
  - `session_id` — The session this message belongs to.
  - `uuid` — Unique message identifier assigned by the CLI. Pass this to
    `ClaudeSDK.Client.rewind_files/2` to rewind to this point.
  - `parent_tool_use_id` — Non-nil when this is a nested user message in a tool-use flow.
  """

  @type t :: %__MODULE__{
          type: :user,
          message: %{
            role: :user,
            content: String.t() | list()
          },
          session_id: String.t(),
          uuid: String.t() | nil,
          parent_tool_use_id: String.t() | nil
        }

  defstruct type: :user,
            message: %{role: :user, content: ""},
            session_id: "default",
            uuid: nil,
            parent_tool_use_id: nil
end

defmodule ClaudeSDK.Types.SystemMessage do
  @moduledoc """
  A system notification from the CLI (init, heartbeat, etc.).

  These are informational messages emitted by the CLI during its lifecycle.
  They are not part of the conversation content.

  ## Fields

  - `subtype` — The notification kind (e.g. `"init"`, `"heartbeat"`).
  - `data` — Additional data specific to the subtype.
  """

  @type t :: %__MODULE__{
          type: :system,
          subtype: String.t(),
          data: map()
        }

  defstruct type: :system, subtype: "", data: %{}
end

defmodule ClaudeSDK.Types.ResultMessage do
  @moduledoc """
  The final result message indicating the query is complete.

  Always the last message in a query stream. Contains cost, timing, and
  the final text result. When `json_schema` is set in Options, the `result`
  field contains a JSON string matching the schema.

  ## Fields

  - `subtype` — Result kind, typically `"success"` or `"error"`.
  - `duration_ms` — Total wall-clock duration of the query.
  - `duration_api_ms` — Time spent in API calls.
  - `is_error` — `true` if the query ended in error.
  - `num_turns` — Number of agentic turns completed.
  - `session_id` — Session identifier for the completed query.
  - `total_cost_usd` — Total cost in USD.
  - `usage` — Token usage breakdown map.
  - `result` — Final text result string, or structured JSON when using `json_schema`.
  """

  @type t :: %__MODULE__{
          type: :result,
          subtype: String.t(),
          duration_ms: non_neg_integer() | nil,
          duration_api_ms: non_neg_integer() | nil,
          is_error: boolean(),
          num_turns: non_neg_integer() | nil,
          session_id: String.t() | nil,
          total_cost_usd: float() | nil,
          usage: map(),
          result: String.t() | nil
        }

  defstruct type: :result,
            subtype: "success",
            duration_ms: nil,
            duration_api_ms: nil,
            is_error: false,
            num_turns: nil,
            session_id: nil,
            total_cost_usd: nil,
            usage: %{},
            result: nil
end

defmodule ClaudeSDK.Types.StreamEvent do
  @moduledoc """
  A streaming event with partial content deltas.

  Only present when `include_partial_messages: true` is set in Options.
  Contains incremental updates as the assistant generates its response.

  ## Fields

  - `uuid` — Event identifier.
  - `session_id` — Session this event belongs to.
  - `event` — Map containing the delta payload (content type and partial data).
  - `parent_tool_use_id` — Non-nil for events within a tool-use flow.
  """

  @type t :: %__MODULE__{
          type: :stream_event,
          uuid: String.t() | nil,
          session_id: String.t() | nil,
          event: map(),
          parent_tool_use_id: String.t() | nil
        }

  defstruct type: :stream_event,
            uuid: nil,
            session_id: nil,
            event: %{},
            parent_tool_use_id: nil
end

defmodule ClaudeSDK.Types.ControlRequest do
  @moduledoc """
  A control request from the CLI (permission check, MCP call, etc.).

  Control requests are intercepted by `ClaudeSDK.ControlRouter` during streaming.
  If a handler is registered for the request's subtype (e.g. `"can_use_tool"`,
  `"mcp_message"`), it is handled automatically and a `ControlResponse` is sent
  back. Unhandled requests are forwarded to the caller as regular stream messages.

  ## Fields

  - `request_id` — Unique ID for correlating the response.
  - `request` — Map containing `"subtype"` and subtype-specific fields.
  """

  @type t :: %__MODULE__{
          type: :control_request,
          request_id: String.t(),
          request: map()
        }

  @enforce_keys [:request_id, :request]
  defstruct type: :control_request, request_id: "", request: %{}
end

defmodule ClaudeSDK.Types.ControlResponse do
  @moduledoc """
  A control response acknowledging a control request.

  Sent by the SDK back to the CLI after handling a `ControlRequest`, or
  received from the CLI to acknowledge SDK-initiated requests (e.g. `initialize`).

  ## Fields

  - `response` — Map containing the response payload. Structure depends on
    the original request subtype.
  """

  @type t :: %__MODULE__{
          type: :control_response,
          response: map()
        }

  defstruct type: :control_response, response: %{}
end
