defmodule ClaudeSDK.Internal do
  @moduledoc false

  @doc false
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
