defmodule ClaudeSDK.Types.AssistantMessage do
  @moduledoc "A message from the assistant containing content blocks."

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
  @moduledoc "A user message, either sent by the SDK or echoed back from the CLI."

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
  @moduledoc "A system notification from the CLI (init, heartbeat, etc.)."

  @type t :: %__MODULE__{
          type: :system,
          subtype: String.t(),
          data: map()
        }

  defstruct type: :system, subtype: "", data: %{}
end

defmodule ClaudeSDK.Types.ResultMessage do
  @moduledoc "The final result message indicating the query is complete."

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
  @moduledoc "A streaming event with partial content deltas."

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
  @moduledoc "A control request from the CLI (permission check, hook callback, etc.)."

  @type t :: %__MODULE__{
          type: :control_request,
          request_id: String.t(),
          request: map()
        }

  @enforce_keys [:request_id, :request]
  defstruct type: :control_request, request_id: "", request: %{}
end

defmodule ClaudeSDK.Types.ControlResponse do
  @moduledoc "A control response from the CLI acknowledging a request."

  @type t :: %__MODULE__{
          type: :control_response,
          response: map()
        }

  defstruct type: :control_response, response: %{}
end
