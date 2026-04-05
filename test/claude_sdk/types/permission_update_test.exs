defmodule ClaudeSDK.Types.PermissionUpdateTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.PermissionUpdate, as: PU

  describe "add_rules/3" do
    test "builds addRules map with allow behavior and session destination" do
      rules = [%{tool_name: "Read"}, %{tool_name: "Glob"}]

      assert PU.add_rules(rules, :allow, :session) == %{
               "type" => "addRules",
               "rules" => rules,
               "behavior" => "allow",
               "destination" => "session"
             }
    end

    test "encodes deny behavior and user destination" do
      assert %{"behavior" => "deny", "destination" => "userSettings"} =
               PU.add_rules([], :deny, :user)
    end

    test "encodes ask behavior and project destination" do
      assert %{"behavior" => "ask", "destination" => "projectSettings"} =
               PU.add_rules([], :ask, :project)
    end

    test "encodes local_settings destination" do
      assert %{"destination" => "localSettings"} =
               PU.add_rules([], :allow, :local_settings)
    end

    test "passes through string behaviors and destinations" do
      assert %{"behavior" => "custom", "destination" => "custom-dest"} =
               PU.add_rules([], "custom", "custom-dest")
    end
  end

  describe "replace_rules/3" do
    test "builds replaceRules map" do
      rules = [%{tool_name: "Bash"}]

      assert PU.replace_rules(rules, :allow, :session) == %{
               "type" => "replaceRules",
               "rules" => rules,
               "behavior" => "allow",
               "destination" => "session"
             }
    end
  end

  describe "remove_rules/3" do
    test "builds removeRules map" do
      rules = [%{tool_name: "Write"}]

      assert PU.remove_rules(rules, :deny, :project) == %{
               "type" => "removeRules",
               "rules" => rules,
               "behavior" => "deny",
               "destination" => "projectSettings"
             }
    end
  end

  describe "set_mode/1" do
    test "encodes atom modes to CLI camelCase strings" do
      assert PU.set_mode(:default) == %{"type" => "setMode", "mode" => "default"}
      assert PU.set_mode(:accept_edits) == %{"type" => "setMode", "mode" => "acceptEdits"}
      assert PU.set_mode(:plan) == %{"type" => "setMode", "mode" => "plan"}

      assert PU.set_mode(:bypass_permissions) == %{
               "type" => "setMode",
               "mode" => "bypassPermissions"
             }

      assert PU.set_mode(:dont_ask) == %{"type" => "setMode", "mode" => "dontAsk"}
    end

    test "passes through string modes unchanged" do
      assert PU.set_mode("acceptEdits") == %{"type" => "setMode", "mode" => "acceptEdits"}
    end
  end

  describe "add_directories/2" do
    test "builds addDirectories map" do
      assert PU.add_directories(["/tmp/work", "/var/log"], :session) == %{
               "type" => "addDirectories",
               "directories" => ["/tmp/work", "/var/log"],
               "destination" => "session"
             }
    end
  end

  describe "remove_directories/2" do
    test "builds removeDirectories map" do
      assert PU.remove_directories(["/tmp/work"], :user) == %{
               "type" => "removeDirectories",
               "directories" => ["/tmp/work"],
               "destination" => "userSettings"
             }
    end
  end
end
