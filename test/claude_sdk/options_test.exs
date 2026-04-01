defmodule ClaudeSDK.OptionsTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.Options

  describe "validate/1" do
    test "returns :ok for valid default options" do
      assert :ok = Options.validate(%Options{})
    end

    test "returns :ok for valid options with all fields set" do
      opts = %Options{
        max_turns: 10,
        max_budget_usd: 5.0,
        permission_mode: :bypass_permissions,
        effort: "high"
      }

      assert :ok = Options.validate(opts)
    end

    test "returns error for negative max_turns" do
      assert {:error, msg} = Options.validate(%Options{max_turns: -1})
      assert msg =~ "max_turns must be a positive integer"
    end

    test "returns error for zero max_turns" do
      assert {:error, msg} = Options.validate(%Options{max_turns: 0})
      assert msg =~ "max_turns must be a positive integer"
    end

    test "returns error for non-integer max_turns" do
      assert {:error, msg} = Options.validate(%Options{max_turns: 1.5})
      assert msg =~ "max_turns must be a positive integer"
    end

    test "returns error for negative max_budget_usd" do
      assert {:error, msg} = Options.validate(%Options{max_budget_usd: -1.0})
      assert msg =~ "max_budget_usd must be a positive number"
    end

    test "returns error for zero max_budget_usd" do
      assert {:error, msg} = Options.validate(%Options{max_budget_usd: 0})
      assert msg =~ "max_budget_usd must be a positive number"
    end

    test "returns error for invalid permission_mode" do
      assert {:error, msg} = Options.validate(%Options{permission_mode: :invalid})
      assert msg =~ "permission_mode must be one of"
    end

    test "accepts all valid permission modes" do
      for mode <- [nil, :default, :accept_edits, :plan, :bypass_permissions, :dont_ask] do
        assert :ok = Options.validate(%Options{permission_mode: mode})
      end
    end

    test "returns error for invalid effort" do
      assert {:error, msg} = Options.validate(%Options{effort: "invalid"})
      assert msg =~ "effort must be one of"
    end

    test "accepts all valid effort values" do
      for effort <- [nil, "low", "medium", "high", "max"] do
        assert :ok = Options.validate(%Options{effort: effort})
      end
    end

    test "returns first validation error when multiple fields are invalid" do
      opts = %Options{max_turns: -1, permission_mode: :invalid}
      assert {:error, _msg} = Options.validate(opts)
    end

    test "validates can_use_tool must be nil or function" do
      assert {:error, msg} = Options.validate(%Options{can_use_tool: "not_a_function"})
      assert msg =~ "can_use_tool must be nil or a function"
    end

    test "accepts can_use_tool arity-2 callback" do
      assert :ok = Options.validate(%Options{can_use_tool: fn _t, _i -> :allow end})
    end

    test "accepts can_use_tool arity-3 callback" do
      assert :ok = Options.validate(%Options{can_use_tool: fn _t, _i, _c -> :allow end})
    end

    test "rejects both can_use_tool and permission_prompt_tool_name" do
      opts = %Options{
        can_use_tool: fn _t, _i -> :allow end,
        permission_prompt_tool_name: "my-tool"
      }

      assert {:error, msg} = Options.validate(opts)
      assert msg =~ "cannot set both can_use_tool and permission_prompt_tool_name"
    end

    test "rejects both continue and resume" do
      opts = %Options{continue: true, resume: "session-123"}
      assert {:error, msg} = Options.validate(opts)
      assert msg =~ "cannot set both continue: true and resume:"
    end

    test "rejects both json_schema and output_format" do
      opts = %Options{
        json_schema: %{"type" => "object"},
        output_format: %{"type" => "object"}
      }

      assert {:error, msg} = Options.validate(opts)
      assert msg =~ "cannot set both json_schema and output_format"
    end

    test "accepts json_schema alone" do
      assert :ok = Options.validate(%Options{json_schema: %{"type" => "object"}})
    end

    test "accepts output_format alone" do
      assert :ok = Options.validate(%Options{output_format: %{"type" => "object"}})
    end

    test "validates init_timeout_ms must be positive" do
      assert {:error, msg} = Options.validate(%Options{init_timeout_ms: 0})
      assert msg =~ "init_timeout_ms must be a positive integer"
    end

    test "validates message_timeout_ms must be positive" do
      assert {:error, msg} = Options.validate(%Options{message_timeout_ms: -1})
      assert msg =~ "message_timeout_ms must be a positive integer"
    end

    test "validates control_timeout_ms must be positive" do
      assert {:error, msg} = Options.validate(%Options{control_timeout_ms: 0})
      assert msg =~ "control_timeout_ms must be a positive integer"
    end
  end

  describe "validate_timeout for hook_timeout_ms" do
    test "returns error for invalid hook_timeout_ms" do
      assert {:error, msg} = Options.validate(%Options{hook_timeout_ms: 0})
      assert msg =~ "hook_timeout_ms must be a positive integer"
    end

    test "returns error for non-integer hook_timeout_ms" do
      assert {:error, msg} = Options.validate(%Options{hook_timeout_ms: 1.5})
      assert msg =~ "hook_timeout_ms must be a positive integer"
    end
  end

  describe "validate_setting_sources" do
    test "accepts nil" do
      assert :ok = Options.validate(%Options{setting_sources: nil})
    end

    test "accepts empty list" do
      assert :ok = Options.validate(%Options{setting_sources: []})
    end

    test "accepts valid sources" do
      assert :ok = Options.validate(%Options{setting_sources: ["user", "project", "local"]})
    end

    test "rejects invalid source entries" do
      assert {:error, msg} = Options.validate(%Options{setting_sources: ["user", "invalid"]})
      assert msg =~ "setting_sources"
      assert msg =~ "invalid"
    end

    test "rejects non-list setting_sources" do
      assert {:error, msg} = Options.validate(%Options{setting_sources: "user"})
      assert msg =~ "setting_sources must be nil or a list"
    end
  end

  describe "validate_extra_args" do
    test "accepts nil" do
      assert :ok = Options.validate(%Options{extra_args: nil})
    end

    test "accepts empty list" do
      assert :ok = Options.validate(%Options{extra_args: []})
    end

    test "accepts valid args" do
      assert :ok = Options.validate(%Options{extra_args: ["--verbose", "--debug"]})
    end

    test "rejects restricted args" do
      assert {:error, msg} = Options.validate(%Options{extra_args: ["--permission-mode"]})
      assert msg =~ "extra_args must not contain"
      assert msg =~ "--permission-mode"
    end

    test "rejects multiple restricted args" do
      args = ["--output-format", "--input-format"]
      assert {:error, msg} = Options.validate(%Options{extra_args: args})
      assert msg =~ "extra_args must not contain"
    end

    test "rejects --permission-prompt-tool" do
      assert {:error, msg} =
               Options.validate(%Options{extra_args: ["--permission-prompt-tool"]})

      assert msg =~ "extra_args must not contain"
    end

    test "rejects non-list extra_args" do
      assert {:error, msg} = Options.validate(%Options{extra_args: "--verbose"})
      assert msg =~ "extra_args must be a list of strings"
    end
  end

  describe "validate_can_use_tool arity" do
    test "rejects arity-1 function" do
      assert {:error, msg} = Options.validate(%Options{can_use_tool: fn _x -> :allow end})
      assert msg =~ "can_use_tool must be nil or a function of arity 2 or 3"
    end
  end

  describe "query/2 keyword list conversion" do
    test "rejects unknown keyword keys" do
      assert_raise ArgumentError, ~r/unknown options/, fn ->
        ClaudeSDK.query("hello", bogus_key: true)
      end
    end
  end
end
