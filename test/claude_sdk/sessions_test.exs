defmodule ClaudeSDK.SessionsTest do
  use ExUnit.Case, async: false

  alias ClaudeSDK.Sessions

  @moduletag :tmp_dir

  # Helper: create a fake session JSONL file in the expected Claude projects directory structure
  defp setup_session(tmp_dir, session_id, lines) do
    # Sessions stores files at ~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl
    # We set CLAUDE_CONFIG_DIR to tmp_dir so projects_dir = tmp_dir/projects
    # Then the sanitized cwd for our "project_dir" goes under that.
    project_dir = Path.join(tmp_dir, "test-project")
    projects_base = Path.join(tmp_dir, "projects")

    # sanitize_path does Path.expand then replaces "/" with "-"
    sanitized = project_dir |> Path.expand() |> String.replace("/", "-")
    session_dir = Path.join(projects_base, sanitized)
    File.mkdir_p!(session_dir)

    file_path = Path.join(session_dir, "#{session_id}.jsonl")
    content = Enum.join(lines, "\n") <> "\n"
    File.write!(file_path, content)

    {project_dir, file_path}
  end

  defp with_config_dir(tmp_dir, fun) do
    original = System.get_env("CLAUDE_CONFIG_DIR")
    System.put_env("CLAUDE_CONFIG_DIR", tmp_dir)

    try do
      fun.()
    after
      if original,
        do: System.put_env("CLAUDE_CONFIG_DIR", original),
        else: System.delete_env("CLAUDE_CONFIG_DIR")
    end
  end

  describe "list_sessions/1" do
    test "returns empty list when no sessions exist", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert Sessions.list_sessions(directory: "/nonexistent/path") == []
      end)
    end

    test "lists sessions from project directory", %{tmp_dir: tmp_dir} do
      user_line =
        Jason.encode!(%{
          "type" => "user",
          "message" => %{"content" => "Hello"},
          "sessionId" => "s1"
        })

      {project_dir, _} = setup_session(tmp_dir, "session-abc", [user_line])

      with_config_dir(tmp_dir, fn ->
        sessions = Sessions.list_sessions(directory: project_dir)
        assert length(sessions) == 1
        assert hd(sessions).session_id == "session-abc"
      end)
    end

    test "returns sessions sorted by last modified (most recent first)", %{tmp_dir: tmp_dir} do
      line1 = Jason.encode!(%{"type" => "user", "message" => %{"content" => "First"}})
      line2 = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Second"}})

      {project_dir, path1} = setup_session(tmp_dir, "session-old", [line1])
      # Touch first file to be older
      File.touch!(path1, {{2020, 1, 1}, {0, 0, 0}})

      # Create second session (will have current timestamp)
      projects_base = Path.join(tmp_dir, "projects")
      sanitized = project_dir |> Path.expand() |> String.replace("/", "-")
      session_dir = Path.join(projects_base, sanitized)
      File.write!(Path.join(session_dir, "session-new.jsonl"), line2 <> "\n")

      with_config_dir(tmp_dir, fn ->
        sessions = Sessions.list_sessions(directory: project_dir)
        assert length(sessions) == 2
        assert hd(sessions).session_id == "session-new"
      end)
    end

    test "respects limit option", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, _} = setup_session(tmp_dir, "s1", [line])

      # Create a second session in same dir
      projects_base = Path.join(tmp_dir, "projects")
      sanitized = project_dir |> Path.expand() |> String.replace("/", "-")
      session_dir = Path.join(projects_base, sanitized)
      File.write!(Path.join(session_dir, "s2.jsonl"), line <> "\n")

      with_config_dir(tmp_dir, fn ->
        sessions = Sessions.list_sessions(directory: project_dir, limit: 1)
        assert length(sessions) == 1
      end)
    end
  end

  describe "get_session_info/2" do
    test "returns session info for existing session", %{tmp_dir: tmp_dir} do
      user_line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hello world"}})
      title_line = Jason.encode!(%{"type" => "custom-title", "customTitle" => "My Session"})
      tag_line = Jason.encode!(%{"type" => "tag", "tag" => "v1.0"})

      {project_dir, _} = setup_session(tmp_dir, "info-session", [user_line, title_line, tag_line])

      with_config_dir(tmp_dir, fn ->
        info = Sessions.get_session_info("info-session", directory: project_dir)
        assert info != nil
        assert info.session_id == "info-session"
        assert info.custom_title == "My Session"
        assert info.tag == "v1.0"
        assert info.first_prompt == "Hello world"
        assert info.file_size > 0
      end)
    end

    test "returns nil for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert Sessions.get_session_info("nonexistent", directory: "/some/path") == nil
      end)
    end

    test "returns nil for invalid session id (path traversal)", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert Sessions.get_session_info("../../../etc/passwd", directory: "/tmp") == nil
        assert Sessions.get_session_info("foo/bar", directory: "/tmp") == nil
        assert Sessions.get_session_info("foo\\bar", directory: "/tmp") == nil
        assert Sessions.get_session_info("", directory: "/tmp") == nil
      end)
    end

    test "extracts git branch and cwd from metadata", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{
          "type" => "system",
          "gitBranch" => "main",
          "cwd" => "/home/user/project"
        }),
        Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      ]

      {project_dir, _} = setup_session(tmp_dir, "meta-session", lines)

      with_config_dir(tmp_dir, fn ->
        info = Sessions.get_session_info("meta-session", directory: project_dir)
        assert info.git_branch == "main"
        assert info.cwd == "/home/user/project"
      end)
    end

    test "extracts summary from metadata", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}}),
        Jason.encode!(%{"type" => "summary", "summary" => "A chat about Elixir"})
      ]

      {project_dir, _} = setup_session(tmp_dir, "summary-session", lines)

      with_config_dir(tmp_dir, fn ->
        info = Sessions.get_session_info("summary-session", directory: project_dir)
        assert info.summary == "A chat about Elixir"
      end)
    end
  end

  describe "get_session_messages/2" do
    test "returns conversation messages in order", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "system", "session_id" => "s1"}),
        Jason.encode!(%{"type" => "user", "uuid" => "u1", "message" => %{"content" => "Hello"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{"content" => "Hi there"}
        }),
        Jason.encode!(%{"type" => "user", "uuid" => "u2", "message" => %{"content" => "Thanks"}})
      ]

      {project_dir, _} = setup_session(tmp_dir, "msg-session", lines)

      with_config_dir(tmp_dir, fn ->
        messages = Sessions.get_session_messages("msg-session", directory: project_dir)
        assert length(messages) == 3
        assert Enum.at(messages, 0).type == "user"
        assert Enum.at(messages, 1).type == "assistant"
        assert Enum.at(messages, 2).type == "user"
      end)
    end

    test "returns empty list for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert Sessions.get_session_messages("nonexistent", directory: "/some/path") == []
      end)
    end

    test "returns empty list for invalid session id", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert Sessions.get_session_messages("../etc/passwd", directory: "/tmp") == []
      end)
    end

    test "supports limit and offset", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "user", "uuid" => "u1", "message" => %{"content" => "Msg 1"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{"content" => "Reply 1"}
        }),
        Jason.encode!(%{"type" => "user", "uuid" => "u2", "message" => %{"content" => "Msg 2"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a2",
          "message" => %{"content" => "Reply 2"}
        })
      ]

      {project_dir, _} = setup_session(tmp_dir, "paginated", lines)

      with_config_dir(tmp_dir, fn ->
        messages =
          Sessions.get_session_messages("paginated", directory: project_dir, limit: 2, offset: 1)

        assert length(messages) == 2
        assert Enum.at(messages, 0).type == "assistant"
        assert Enum.at(messages, 1).type == "user"
      end)
    end

    test "handles human type messages (alias for user)", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{
          "type" => "human",
          "uuid" => "h1",
          "message" => %{"content" => "Hello human type"}
        })
      ]

      {project_dir, _} = setup_session(tmp_dir, "human-session", lines)

      with_config_dir(tmp_dir, fn ->
        messages = Sessions.get_session_messages("human-session", directory: project_dir)
        assert length(messages) == 1
        assert hd(messages).type == "human"
      end)
    end
  end

  describe "rename_session/3" do
    test "appends custom-title entry to session file", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, file_path} = setup_session(tmp_dir, "rename-session", [line])

      with_config_dir(tmp_dir, fn ->
        assert :ok =
                 Sessions.rename_session("rename-session", "New Title", directory: project_dir)

        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["type"] == "custom-title"
        assert last_entry["customTitle"] == "New Title"
      end)
    end

    test "returns error for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :session_not_found} =
                 Sessions.rename_session("nonexistent", "Title", directory: "/some/path")
      end)
    end

    test "returns error for invalid session id", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :invalid_session_id} =
                 Sessions.rename_session("../etc/passwd", "Title", directory: "/tmp")
      end)
    end

    test "sanitizes unicode in title", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, file_path} = setup_session(tmp_dir, "unicode-session", [line])

      # Zero-width space (U+200B) is a Cf character and should be stripped
      title_with_zwsp = "Hello\u200BWorld"

      with_config_dir(tmp_dir, fn ->
        assert :ok =
                 Sessions.rename_session("unicode-session", title_with_zwsp,
                   directory: project_dir
                 )

        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["customTitle"] == "HelloWorld"
      end)
    end
  end

  describe "tag_session/3" do
    test "appends tag entry to session file", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, file_path} = setup_session(tmp_dir, "tag-session", [line])

      with_config_dir(tmp_dir, fn ->
        assert :ok = Sessions.tag_session("tag-session", "v2.0", directory: project_dir)

        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["type"] == "tag"
        assert last_entry["tag"] == "v2.0"
      end)
    end

    test "clears tag with nil", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, file_path} = setup_session(tmp_dir, "tag-clear", [line])

      with_config_dir(tmp_dir, fn ->
        assert :ok = Sessions.tag_session("tag-clear", nil, directory: project_dir)

        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["type"] == "tag"
        assert last_entry["tag"] == ""
      end)
    end

    test "returns error for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :session_not_found} =
                 Sessions.tag_session("nonexistent", "tag", directory: "/some/path")
      end)
    end

    test "returns error for invalid session id", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :invalid_session_id} =
                 Sessions.tag_session("../evil", "tag", directory: "/tmp")
      end)
    end
  end

  describe "first_prompt extraction" do
    test "extracts first prompt from human type", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "system", "init" => true}),
        Jason.encode!(%{"type" => "human", "message" => %{"content" => "What is Elixir?"}})
      ]

      {project_dir, _} = setup_session(tmp_dir, "human-prompt", lines)

      with_config_dir(tmp_dir, fn ->
        info = Sessions.get_session_info("human-prompt", directory: project_dir)
        assert info.first_prompt == "What is Elixir?"
      end)
    end

    test "truncates long first prompts to 200 chars", %{tmp_dir: tmp_dir} do
      long_prompt = String.duplicate("a", 300)

      lines = [
        Jason.encode!(%{"type" => "user", "message" => %{"content" => long_prompt}})
      ]

      {project_dir, _} = setup_session(tmp_dir, "long-prompt", lines)

      with_config_dir(tmp_dir, fn ->
        info = Sessions.get_session_info("long-prompt", directory: project_dir)
        assert String.length(info.first_prompt) == 200
      end)
    end
  end

  describe "delegate functions on ClaudeSDK" do
    test "list_sessions delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert is_list(ClaudeSDK.list_sessions(directory: "/nonexistent"))
      end)
    end

    test "get_session_info delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert ClaudeSDK.get_session_info("nonexistent", directory: "/nonexistent") == nil
      end)
    end

    test "get_session_messages delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert ClaudeSDK.get_session_messages("nonexistent", directory: "/nonexistent") == []
      end)
    end

    test "rename_session delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, _} =
                 ClaudeSDK.rename_session("nonexistent", "title", directory: "/nonexistent")
      end)
    end

    test "tag_session delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, _} =
                 ClaudeSDK.tag_session("nonexistent", "tag", directory: "/nonexistent")
      end)
    end
  end

  describe "sanitize_unicode edge cases" do
    test "strips private-use characters", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
        {project_dir, file_path} = setup_session(tmp_dir, "unicode-priv", [line])
        title = "Hello\u{E000}World"
        :ok = Sessions.rename_session("unicode-priv", title, directory: project_dir)
        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["customTitle"] == "HelloWorld"
      end)
    end

    test "strips directional marks (Cf category)", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
        {project_dir, file_path} = setup_session(tmp_dir, "unicode-bidi", [line])
        title = "Hello\u200FWorld"
        :ok = Sessions.rename_session("unicode-bidi", title, directory: project_dir)
        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["customTitle"] == "HelloWorld"
      end)
    end
  end

  describe "malformed JSONL" do
    test "skips invalid JSON lines in session file", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        lines = [
          "not valid json",
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "u1",
            "message" => %{"content" => "Hello"}
          }),
          "{broken",
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "a1",
            "message" => %{"content" => "Hi back"}
          })
        ]

        {project_dir, _} = setup_session(tmp_dir, "malformed-session", lines)
        messages = Sessions.get_session_messages("malformed-session", directory: project_dir)
        assert length(messages) == 2
        assert Enum.at(messages, 0).type == "user"
        assert Enum.at(messages, 1).type == "assistant"
      end)
    end
  end

  describe "build_conversation_chain filters" do
    test "filters out non-conversation types", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        lines = [
          Jason.encode!(%{"type" => "system", "data" => "init"}),
          Jason.encode!(%{
            "type" => "user",
            "uuid" => "u1",
            "message" => %{"content" => "Hello"}
          }),
          Jason.encode!(%{"type" => "custom-title", "customTitle" => "My Title"}),
          Jason.encode!(%{"type" => "tag", "tag" => "v1"}),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "a1",
            "message" => %{"content" => "Hi"}
          })
        ]

        {project_dir, _} = setup_session(tmp_dir, "filter-session", lines)
        messages = Sessions.get_session_messages("filter-session", directory: project_dir)
        assert length(messages) == 2
        types = Enum.map(messages, & &1.type)
        assert types == ["user", "assistant"]
      end)
    end
  end

  describe "build_conversation_chain missing fields" do
    test "handles entries with missing message and sessionId", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        lines = [
          Jason.encode!(%{"type" => "user", "uuid" => "u1"}),
          Jason.encode!(%{
            "type" => "assistant",
            "uuid" => "a1",
            "session_id" => "alt-id",
            "message" => %{"content" => "Hi"}
          })
        ]

        {project_dir, _} = setup_session(tmp_dir, "missing-fields", lines)
        messages = Sessions.get_session_messages("missing-fields", directory: project_dir)
        assert length(messages) == 2
        assert Enum.at(messages, 0).message == %{}
        assert Enum.at(messages, 1).session_id == "alt-id"
      end)
    end
  end

  describe "first_prompt with no user messages" do
    test "returns nil when no user/human messages exist", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        lines = [
          Jason.encode!(%{"type" => "system", "data" => "init"}),
          Jason.encode!(%{"type" => "assistant", "message" => %{"content" => "Hello"}})
        ]

        {project_dir, _} = setup_session(tmp_dir, "no-prompt", lines)
        info = Sessions.get_session_info("no-prompt", directory: project_dir)
        assert info.first_prompt == nil
      end)
    end
  end

  describe "find_last_value when no matching type" do
    test "returns nil for custom_title when no custom-title entries", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        lines = [
          Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hello"}}),
          Jason.encode!(%{"type" => "assistant", "message" => %{"content" => "Hi"}})
        ]

        {project_dir, _} = setup_session(tmp_dir, "no-title", lines)
        info = Sessions.get_session_info("no-title", directory: project_dir)
        assert info.custom_title == nil
        assert info.summary == nil
        assert info.tag == nil
      end)
    end
  end

  describe "read_tail_lines with empty file" do
    test "empty file returns no metadata", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        project_dir = Path.join(tmp_dir, "test-project")
        projects_base = Path.join(tmp_dir, "projects")
        sanitized = project_dir |> Path.expand() |> String.replace("/", "-")
        session_dir = Path.join(projects_base, sanitized)
        File.mkdir_p!(session_dir)
        file_path = Path.join(session_dir, "empty-session.jsonl")
        File.write!(file_path, "")
        sessions = Sessions.list_sessions(directory: project_dir)
        assert length(sessions) == 1
        session = hd(sessions)
        assert session.custom_title == nil
        assert session.summary == nil
        assert session.first_prompt == nil
      end)
    end
  end

  describe "delete_session/2" do
    test "deletes an existing session file", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, file_path} = setup_session(tmp_dir, "delete-me", [line])

      with_config_dir(tmp_dir, fn ->
        assert File.exists?(file_path)
        assert :ok = Sessions.delete_session("delete-me", directory: project_dir)
        refute File.exists?(file_path)
      end)
    end

    test "returns error for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :session_not_found} =
                 Sessions.delete_session("nonexistent", directory: "/some/path")
      end)
    end

    test "returns error for invalid session id", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :invalid_session_id} =
                 Sessions.delete_session("../etc/passwd", directory: "/tmp")
      end)
    end

    test "session no longer appears in list after deletion", %{tmp_dir: tmp_dir} do
      line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
      {project_dir, _} = setup_session(tmp_dir, "to-delete", [line])

      with_config_dir(tmp_dir, fn ->
        assert length(Sessions.list_sessions(directory: project_dir)) == 1
        :ok = Sessions.delete_session("to-delete", directory: project_dir)
        assert Sessions.list_sessions(directory: project_dir) == []
      end)
    end
  end

  describe "fork_session/2" do
    test "creates a copy of the session with a new ID", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "user", "uuid" => "u1", "message" => %{"content" => "Hello"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{"content" => "Hi there"}
        })
      ]

      {project_dir, _} = setup_session(tmp_dir, "source-session", lines)

      with_config_dir(tmp_dir, fn ->
        assert {:ok, new_id} = Sessions.fork_session("source-session", directory: project_dir)
        assert is_binary(new_id)
        assert new_id != "source-session"

        # Both sessions should exist
        sessions = Sessions.list_sessions(directory: project_dir)
        ids = Enum.map(sessions, & &1.session_id)
        assert "source-session" in ids
        assert new_id in ids

        # Forked session should have same messages
        messages = Sessions.get_session_messages(new_id, directory: project_dir)
        assert length(messages) == 2
        assert Enum.at(messages, 0).type == "user"
        assert Enum.at(messages, 1).type == "assistant"
      end)
    end

    test "forks up to a specific message UUID", %{tmp_dir: tmp_dir} do
      lines = [
        Jason.encode!(%{"type" => "user", "uuid" => "u1", "message" => %{"content" => "First"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a1",
          "message" => %{"content" => "Reply 1"}
        }),
        Jason.encode!(%{"type" => "user", "uuid" => "u2", "message" => %{"content" => "Second"}}),
        Jason.encode!(%{
          "type" => "assistant",
          "uuid" => "a2",
          "message" => %{"content" => "Reply 2"}
        })
      ]

      {project_dir, _} = setup_session(tmp_dir, "fork-partial", lines)

      with_config_dir(tmp_dir, fn ->
        assert {:ok, new_id} =
                 Sessions.fork_session("fork-partial",
                   directory: project_dir,
                   up_to_message_uuid: "a1"
                 )

        messages = Sessions.get_session_messages(new_id, directory: project_dir)
        assert length(messages) == 2
        assert Enum.at(messages, 0).uuid == "u1"
        assert Enum.at(messages, 1).uuid == "a1"
      end)
    end

    test "returns error for non-existent session", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :session_not_found} =
                 Sessions.fork_session("nonexistent", directory: "/some/path")
      end)
    end

    test "returns error for invalid session id", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, :invalid_session_id} =
                 Sessions.fork_session("../evil", directory: "/tmp")
      end)
    end
  end

  describe "delegate functions for new session operations" do
    test "delete_session delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, _} = ClaudeSDK.delete_session("nonexistent", directory: "/nonexistent")
      end)
    end

    test "fork_session delegates to Sessions", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        assert {:error, _} = ClaudeSDK.fork_session("nonexistent", directory: "/nonexistent")
      end)
    end
  end

  describe "tag_session sanitizes unicode" do
    test "strips zero-width characters from tag", %{tmp_dir: tmp_dir} do
      with_config_dir(tmp_dir, fn ->
        line = Jason.encode!(%{"type" => "user", "message" => %{"content" => "Hi"}})
        {project_dir, file_path} = setup_session(tmp_dir, "tag-unicode", [line])
        :ok = Sessions.tag_session("tag-unicode", "v1\u200B.0", directory: project_dir)
        content = File.read!(file_path)
        lines = String.split(content, "\n", trim: true)
        last_entry = Jason.decode!(List.last(lines))
        assert last_entry["tag"] == "v1.0"
      end)
    end
  end
end
