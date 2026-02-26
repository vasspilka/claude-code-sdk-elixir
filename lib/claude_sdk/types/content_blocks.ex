defmodule ClaudeSDK.Types.TextBlock do
  @moduledoc "A text content block from the assistant."

  @type t :: %__MODULE__{
          type: :text,
          text: String.t()
        }

  @enforce_keys [:text]
  defstruct type: :text, text: ""
end

defmodule ClaudeSDK.Types.ThinkingBlock do
  @moduledoc "An extended thinking content block."

  @type t :: %__MODULE__{
          type: :thinking,
          thinking: String.t(),
          signature: String.t() | nil
        }

  @enforce_keys [:thinking]
  defstruct type: :thinking, thinking: "", signature: nil
end

defmodule ClaudeSDK.Types.ToolUseBlock do
  @moduledoc "A tool use request from the assistant."

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
  @moduledoc "A tool result returned to the assistant."

  @type t :: %__MODULE__{
          type: :tool_result,
          tool_use_id: String.t(),
          content: String.t() | list(),
          is_error: boolean()
        }

  @enforce_keys [:tool_use_id, :content]
  defstruct type: :tool_result, tool_use_id: "", content: "", is_error: false
end
