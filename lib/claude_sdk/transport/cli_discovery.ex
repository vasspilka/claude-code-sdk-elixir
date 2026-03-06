defmodule ClaudeSDK.Transport.CLIDiscovery do
  @moduledoc """
  Finds the Claude CLI binary on the system.

  This is an internal module used by `ClaudeSDK.Transport.Subprocess`.
  You do not need to use it directly -- the CLI is discovered automatically.

  Resolution order:
  1. Explicit path provided via `Options.cli_path` (if it exists on disk).
  2. `System.find_executable/1` searching the system PATH.
  3. Known installation locations (`/usr/local/bin/claude`, `/usr/bin/claude`,
     `/opt/homebrew/bin/claude`).

  Raises `ClaudeSDK.CLINotFoundError` if the binary cannot be found.
  """

  @known_locations [
    "/usr/local/bin/claude",
    "/usr/bin/claude",
    "/opt/homebrew/bin/claude"
  ]

  @doc """
  Find the Claude CLI binary path.

  Resolution order:
  1. Explicit path (if provided and exists)
  2. `System.find_executable/1` on PATH
  3. Known installation locations
  """
  @spec find_cli(String.t() | nil) :: {:ok, String.t()} | {:error, :not_found}
  def find_cli(explicit_path \\ nil)

  def find_cli(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, path}
      _ -> {:error, :not_found}
    end
  end

  def find_cli(nil) do
    case System.find_executable("claude") do
      nil -> search_known_locations()
      path -> {:ok, path}
    end
  end

  @doc """
  Find the CLI or raise `CLINotFoundError`.
  """
  @spec find_cli!(String.t() | nil) :: String.t()
  def find_cli!(explicit_path \\ nil) do
    case find_cli(explicit_path) do
      {:ok, path} -> path
      {:error, :not_found} -> raise ClaudeSDK.CLINotFoundError, path: explicit_path
    end
  end

  @doc """
  Get the CLI version string by running `claude -v`.
  """
  @spec version(String.t()) :: {:ok, String.t()} | {:error, term()}
  def version(cli_path) do
    case System.cmd(cli_path, ["-v"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, {:exit_code, code, output}}
    end
  rescue
    e in ErlangError -> {:error, {:spawn_failed, e}}
  end

  defp search_known_locations do
    Enum.find_value(@known_locations, {:error, :not_found}, fn path ->
      case File.stat(path) do
        {:ok, %File.Stat{type: :regular}} -> {:ok, path}
        _ -> nil
      end
    end)
  end
end
