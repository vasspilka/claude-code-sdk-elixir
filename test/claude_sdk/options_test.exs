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
      for mode <- [nil, :default, :accept_edits, :plan, :bypass_permissions] do
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
  end
end
