defmodule ClaudeSDK.Sessions do
  @moduledoc """
  Session management functions for listing, reading, and annotating Claude Code sessions.

  Claude Code stores session transcripts as JSONL files under
  `~/.claude/projects/<sanitized-cwd>/`. This module reads and writes
  those files to provide session introspection and metadata management.

  These functions operate on the filesystem directly — they do not require
  a running CLI subprocess or `ClaudeSDK.Client`.

  ## Examples

      # List all sessions for the current directory
      sessions = ClaudeSDK.Sessions.list_sessions()

      # Get conversation history for a session
      messages = ClaudeSDK.Sessions.get_session_messages("abc123")

      # Annotate sessions
      ClaudeSDK.Sessions.rename_session("abc123", "Auth refactor discussion")
      ClaudeSDK.Sessions.tag_session("abc123", "v1.0-release")
  """

  require Logger

  @type session_info :: %{
          session_id: String.t(),
          file_path: String.t(),
          last_modified: DateTime.t() | nil,
          file_size: non_neg_integer(),
          custom_title: String.t() | nil,
          summary: String.t() | nil,
          first_prompt: String.t() | nil,
          git_branch: String.t() | nil,
          cwd: String.t() | nil,
          tag: String.t() | nil
        }

  @type session_message :: %{
          type: String.t(),
          uuid: String.t() | nil,
          session_id: String.t() | nil,
          message: map(),
          parent_tool_use_id: String.t() | nil
        }

  @doc """
  List available sessions.

  When `directory` is provided, lists sessions for that project directory.
  When `nil`, lists sessions across all projects under `~/.claude/projects/`.

  ## Options

  - `directory` — project directory path (default: current directory)
  - `limit` — max number of sessions to return (default: all)

  ## Returns

  A list of session info maps sorted by last modified (most recent first).
  """
  @spec list_sessions(keyword()) :: [session_info()]
  def list_sessions(opts \\ []) do
    directory = Keyword.get(opts, :directory, File.cwd!())
    limit = Keyword.get(opts, :limit)

    sessions =
      directory
      |> session_dirs()
      |> Enum.flat_map(&read_sessions_from_dir/1)
      |> Enum.sort_by(& &1.last_modified, {:desc, DateTime})

    if limit, do: Enum.take(sessions, limit), else: sessions
  end

  @doc """
  Get the conversation messages for a session.

  Reads the full JSONL transcript and returns user/assistant messages
  in conversation order.

  ## Options

  - `directory` — project directory to search in (default: current directory)
  - `limit` — max number of messages to return
  - `offset` — number of messages to skip (default: 0)
  """
  @spec get_session_messages(String.t(), keyword()) :: [session_message()]
  def get_session_messages(session_id, opts \\ []) do
    directory = Keyword.get(opts, :directory, File.cwd!())
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    case find_session_file(session_id, directory) do
      nil ->
        []

      path ->
        path
        |> read_jsonl()
        |> build_conversation_chain()
        |> Enum.drop(offset)
        |> then(fn msgs -> if limit, do: Enum.take(msgs, limit), else: msgs end)
    end
  end

  @doc """
  Rename a session by setting a custom title.

  Appends a `custom-title` entry to the session's JSONL file.
  """
  @spec rename_session(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def rename_session(session_id, title, opts \\ []) do
    directory = Keyword.get(opts, :directory, File.cwd!())

    entry = %{
      "type" => "custom-title",
      "customTitle" => title,
      "sessionId" => session_id
    }

    append_to_session(session_id, entry, directory)
  end

  @doc """
  Tag a session with a label.

  Appends a `tag` entry to the session's JSONL file. Pass `nil` as tag to clear it.
  """
  @spec tag_session(String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def tag_session(session_id, tag, opts \\ []) do
    directory = Keyword.get(opts, :directory, File.cwd!())

    entry = %{
      "type" => "tag",
      "tag" => tag || "",
      "sessionId" => session_id
    }

    append_to_session(session_id, entry, directory)
  end

  # Private

  defp projects_dir do
    claude_home = System.get_env("CLAUDE_CONFIG_DIR") || Path.join(System.user_home!(), ".claude")
    Path.join(claude_home, "projects")
  end

  defp sanitize_path(directory) do
    directory
    |> Path.expand()
    |> String.replace("/", "-")
  end

  defp session_dirs(directory) do
    sanitized = sanitize_path(directory)
    project_dir = Path.join(projects_dir(), sanitized)

    if File.dir?(project_dir) do
      [project_dir]
    else
      []
    end
  end

  defp read_sessions_from_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.map(fn file ->
          path = Path.join(dir, file)
          session_id = String.trim_trailing(file, ".jsonl")
          read_session_info(session_id, path)
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp read_session_info(session_id, path) do
    case File.stat(path, time: :posix) do
      {:ok, %{size: size, mtime: mtime}} ->
        metadata = read_session_metadata(path)

        %{
          session_id: session_id,
          file_path: path,
          last_modified: posix_to_datetime(mtime),
          file_size: size,
          custom_title: metadata[:custom_title],
          summary: metadata[:summary],
          first_prompt: metadata[:first_prompt],
          git_branch: metadata[:git_branch],
          cwd: metadata[:cwd],
          tag: metadata[:tag]
        }

      {:error, _} ->
        nil
    end
  end

  defp posix_to_datetime(posix) when is_integer(posix) do
    case DateTime.from_unix(posix) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp posix_to_datetime(_), do: nil

  # Read head and tail of JSONL to extract metadata without full parse
  defp read_session_metadata(path) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)
        head = Enum.take(lines, 20)
        tail = lines |> Enum.reverse() |> Enum.take(20)
        all_sample = Enum.uniq(head ++ tail)

        entries =
          Enum.reduce(all_sample, [], fn line, acc ->
            case Jason.decode(line) do
              {:ok, entry} -> [entry | acc]
              _ -> acc
            end
          end)

        first_prompt = find_first_prompt(head)

        %{
          custom_title: find_last_value(entries, "custom-title", "customTitle"),
          summary: find_last_value(entries, "summary", "summary"),
          first_prompt: first_prompt,
          git_branch: find_first_value(entries, "gitBranch"),
          cwd: find_first_value(entries, "cwd"),
          tag: find_last_value(entries, "tag", "tag")
        }

      {:error, _} ->
        %{}
    end
  end

  defp find_first_prompt(head_lines) do
    Enum.find_value(head_lines, fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "human", "message" => %{"content" => content}}}
        when is_binary(content) ->
          String.slice(content, 0, 200)

        {:ok, %{"type" => "user", "message" => %{"content" => content}}}
        when is_binary(content) ->
          String.slice(content, 0, 200)

        _ ->
          nil
      end
    end)
  end

  defp find_last_value(entries, type, key) do
    entries
    |> Enum.filter(&(&1["type"] == type))
    |> List.last()
    |> case do
      nil -> nil
      entry -> entry[key]
    end
  end

  defp find_first_value(entries, key) do
    Enum.find_value(entries, fn entry -> entry[key] end)
  end

  defp find_session_file(session_id, directory) do
    directory
    |> session_dirs()
    |> Enum.find_value(fn dir ->
      path = Path.join(dir, "#{session_id}.jsonl")
      if File.exists?(path), do: path
    end)
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode/1)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, entry} -> entry end)
  end

  defp build_conversation_chain(entries) do
    entries
    |> Enum.filter(fn entry ->
      entry["type"] in ["user", "human", "assistant"]
    end)
    |> Enum.map(fn entry ->
      %{
        type: entry["type"],
        uuid: entry["uuid"],
        session_id: entry["sessionId"] || entry["session_id"],
        message: entry["message"] || %{},
        parent_tool_use_id: entry["parent_tool_use_id"]
      }
    end)
  end

  defp append_to_session(session_id, entry, directory) do
    case find_session_file(session_id, directory) do
      nil ->
        {:error, :session_not_found}

      path ->
        line = Jason.encode!(entry) <> "\n"

        case File.write(path, line, [:append]) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
