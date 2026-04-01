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
  Get info for a single session by ID.

  Returns a session info map or `nil` if the session is not found.

  ## Options

  - `directory` — project directory to search in (default: current directory)
  """
  @spec get_session_info(String.t(), keyword()) :: session_info() | nil
  def get_session_info(session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())

      case find_session_file(session_id, directory) do
        nil -> nil
        path -> read_session_info(session_id, path)
      end
    else
      {:error, :invalid_session_id} -> nil
    end
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
    with :ok <- validate_session_id(session_id) do
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
    else
      {:error, :invalid_session_id} -> []
    end
  end

  @doc """
  Get the full unfiltered transcript for a session.

  Unlike `get_session_messages/2` which only returns user/assistant messages,
  this returns every JSONL entry — including tool results, control requests,
  system messages, metadata entries, and more. Useful for introspecting
  sub-agent sessions to see exactly what tools were called and what happened.

  Each entry is a raw decoded JSON map with its original keys preserved.

  ## Options

  - `directory` — project directory to search in (default: current directory)
  - `limit` — max number of entries to return
  - `offset` — number of entries to skip (default: 0)
  """
  @spec get_session_transcript(String.t(), keyword()) :: [map()]
  def get_session_transcript(session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())
      limit = Keyword.get(opts, :limit)
      offset = Keyword.get(opts, :offset, 0)

      case find_session_file(session_id, directory) do
        nil ->
          []

        path ->
          entries = read_jsonl(path)

          entries
          |> Enum.drop(offset)
          |> then(fn e -> if limit, do: Enum.take(e, limit), else: e end)
      end
    else
      {:error, :invalid_session_id} -> []
    end
  end

  @doc """
  Rename a session by setting a custom title.

  Appends a `custom-title` entry to the session's JSONL file.
  The title is sanitized (NFKC normalization, dangerous Unicode stripped).
  """
  @spec rename_session(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def rename_session(session_id, title, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())

      entry = %{
        "type" => "custom-title",
        "customTitle" => sanitize_unicode(title),
        "sessionId" => session_id
      }

      append_to_session(session_id, entry, directory)
    end
  end

  @doc """
  Tag a session with a label.

  Appends a `tag` entry to the session's JSONL file. Pass `nil` as tag to clear it.
  The tag is sanitized (NFKC normalization, dangerous Unicode stripped).
  """
  @spec tag_session(String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def tag_session(session_id, tag, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())

      entry = %{
        "type" => "tag",
        "tag" => sanitize_unicode(tag || ""),
        "sessionId" => session_id
      }

      append_to_session(session_id, entry, directory)
    end
  end

  @doc """
  Delete a session by removing its JSONL file.

  Returns `:ok` if the file was deleted, or `{:error, reason}` if the session
  was not found or could not be deleted.

  ## Options

  - `directory` — project directory to search in (default: current directory)
  """
  @spec delete_session(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_session(session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())

      case find_session_file(session_id, directory) do
        nil -> {:error, :session_not_found}
        path -> File.rm(path)
      end
    end
  end

  @doc """
  Fork a session by copying its transcript to a new session ID.

  Creates a new session file containing all messages from the source session
  up to (and including) `up_to_message_uuid`, if provided. When `up_to_message_uuid`
  is `nil`, the entire transcript is copied.

  Returns `{:ok, new_session_id}` on success.

  ## Options

  - `directory` — project directory to search in (default: current directory)
  - `up_to_message_uuid` — optional UUID; only copy messages up to this point
  """
  @spec fork_session(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def fork_session(session_id, opts \\ []) do
    with :ok <- validate_session_id(session_id) do
      directory = Keyword.get(opts, :directory, File.cwd!())
      up_to = Keyword.get(opts, :up_to_message_uuid)

      case find_session_file(session_id, directory) do
        nil ->
          {:error, :session_not_found}

        source_path ->
          new_id = generate_session_id()
          dir = Path.dirname(source_path)
          dest_path = Path.join(dir, "#{new_id}.jsonl")

          lines = read_lines_for_fork(source_path, up_to)
          content = Enum.join(lines, "\n") <> "\n"

          case File.write(dest_path, content) do
            :ok -> {:ok, new_id}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  # Private

  # Validate session_id to prevent path traversal attacks.
  # Claude Code uses UUIDs for session IDs; reject anything with
  # path separators or parent-directory references.
  defp validate_session_id(session_id) do
    cond do
      String.contains?(session_id, "/") -> {:error, :invalid_session_id}
      String.contains?(session_id, "\\") -> {:error, :invalid_session_id}
      String.contains?(session_id, "..") -> {:error, :invalid_session_id}
      session_id == "" -> {:error, :invalid_session_id}
      true -> :ok
    end
  end

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

  # Read head and tail of JSONL to extract metadata without loading entire file.
  # Uses streaming for the head and reads the tail by seeking to the end.
  defp read_session_metadata(path) do
    head = read_head_lines(path, 20)
    tail = read_tail_lines(path, 20)
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
  rescue
    _ -> %{}
  end

  defp read_head_lines(path, n) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.take(n)
  end

  defp read_tail_lines(path, n) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > 0 ->
        # Read last ~64KB to get the tail lines (generous for metadata entries)
        chunk_size = min(size, 65_536)
        {:ok, file} = File.open(path, [:read, :binary])

        try do
          {:ok, _} = :file.position(file, {:eof, -chunk_size})

          case :file.read(file, chunk_size) do
            {:ok, data} ->
              data
              |> String.split("\n", trim: true)
              |> Enum.take(-n)

            _ ->
              []
          end
        after
          File.close(file)
        end

      _ ->
        []
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

  # Sanitize a string by applying NFKC normalization and stripping
  # dangerous Unicode characters (format, private-use, unassigned).
  # Matches the Python SDK's _sanitize_unicode() in session_mutations.py.
  @max_sanitize_iterations 10

  defp sanitize_unicode(text) when is_binary(text) do
    text
    |> normalize_nfkc(0)
    |> strip_dangerous_unicode()
  end

  defp sanitize_unicode(text), do: text

  defp normalize_nfkc(text, iteration) when iteration < @max_sanitize_iterations do
    normalized = :unicode.characters_to_nfkc_binary(text)

    if normalized == text do
      text
    else
      normalize_nfkc(normalized, iteration + 1)
    end
  end

  defp normalize_nfkc(text, _iteration), do: text

  # Strip format characters (Cf), private-use (Co), and unassigned (Cn) codepoints.
  # This removes zero-width spaces, directional marks, BOM, and other invisible chars.
  defp strip_dangerous_unicode(text) do
    Regex.replace(~r/[\p{Cf}\p{Co}\p{Cn}]/u, text, "")
  end

  defp generate_session_id do
    hex = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    # Format as UUID-like: 8-4-4-4-12
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = hex

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp read_lines_for_fork(source_path, nil) do
    source_path
    |> File.stream!()
    |> Enum.map(&String.trim_trailing(&1, "\n"))
    |> Enum.reject(&(&1 == ""))
  end

  defp read_lines_for_fork(source_path, up_to_uuid) do
    source_path
    |> File.stream!()
    |> Enum.reduce_while([], fn line, acc ->
      trimmed = String.trim_trailing(line, "\n")

      if trimmed == "" do
        {:cont, acc}
      else
        acc = [trimmed | acc]

        case Jason.decode(trimmed) do
          {:ok, %{"uuid" => ^up_to_uuid}} -> {:halt, acc}
          _ -> {:cont, acc}
        end
      end
    end)
    |> Enum.reverse()
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
