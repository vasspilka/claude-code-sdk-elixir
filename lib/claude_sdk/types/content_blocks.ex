defmodule ClaudeSDK.Types.TextBlock do
  @moduledoc """
  A text content block from the assistant.

  The most common content block type. Contains the assistant's text response.

  ## Fields

  - `text` — The text content string.
  """

  @type t :: %__MODULE__{
          type: :text,
          text: String.t()
        }

  @enforce_keys [:text]
  defstruct type: :text, text: ""
end

defmodule ClaudeSDK.Types.ThinkingBlock do
  @moduledoc """
  An extended thinking content block.

  Present when the model uses extended thinking. Contains the model's
  internal reasoning before producing its response.

  ## Fields

  - `thinking` — The thinking/reasoning text.
  - `signature` — Cryptographic signature for verification, or nil.
  """

  @type t :: %__MODULE__{
          type: :thinking,
          thinking: String.t(),
          signature: String.t() | nil
        }

  @enforce_keys [:thinking]
  defstruct type: :thinking, thinking: "", signature: nil
end

defmodule ClaudeSDK.Types.ToolUseBlock do
  @moduledoc """
  A tool use request from the assistant.

  Indicates the assistant wants to invoke a tool. The CLI handles tool
  execution; this block appears in the stream to show what tool was called.

  ## Fields

  - `id` — Unique identifier for this tool invocation. Used to correlate
    with the corresponding `ToolResultBlock`.
  - `name` — Tool name (e.g. `"Read"`, `"Bash"`, `"Glob"`).
  - `input` — Map of arguments passed to the tool.
  """

  @type t :: %__MODULE__{
          type: :tool_use,
          id: String.t(),
          name: String.t(),
          input: map()
        }

  @enforce_keys [:id, :name, :input]
  defstruct type: :tool_use, id: "", name: "", input: %{}
end

defmodule ClaudeSDK.Types.ToolResultBlock do
  @moduledoc """
  A tool result returned to the assistant.

  Contains the output from a tool invocation. Appears in the stream
  after the corresponding `ToolUseBlock`.

  ## Fields

  - `tool_use_id` — ID of the `ToolUseBlock` this result corresponds to.
  - `content` — Result content (string or list of content parts).
  - `is_error` — `true` if the tool execution failed.
  """

  @type t :: %__MODULE__{
          type: :tool_result,
          tool_use_id: String.t(),
          content: String.t() | list(),
          is_error: boolean()
        }

  @enforce_keys [:tool_use_id, :content]
  defstruct type: :tool_result, tool_use_id: "", content: "", is_error: false
end
