defmodule ClaudeSDK.Transport.LineBufferTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.LineBuffer

  describe "new/0" do
    test "creates empty buffer" do
      buf = LineBuffer.new()
      assert buf.buffer == ""
    end
  end

  describe "parse_line/1" do
    test "parses valid JSON" do
      assert {:ok, %{"type" => "system"}} = LineBuffer.parse_line(~s({"type":"system"}))
    end

    test "parses JSON with surrounding whitespace" do
      assert {:ok, %{"key" => "val"}} = LineBuffer.parse_line(~s(  {"key":"val"}  ))
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = LineBuffer.parse_line("not json")
    end

    test "returns error for empty string" do
      assert {:error, :empty} = LineBuffer.parse_line("")
    end

    test "returns error for whitespace-only string" do
      assert {:error, :empty} = LineBuffer.parse_line("   ")
    end
  end

  describe "append/2" do
    test "parses a single complete JSON line" do
      buf = LineBuffer.new()
      {new_buf, messages} = LineBuffer.append(buf, ~s({"type":"system"}\n))

      assert new_buf.buffer == ""
      assert [%{"type" => "system"}] = messages
    end

    test "parses multiple JSON lines at once" do
      buf = LineBuffer.new()
      data = ~s({"type":"system"}\n{"type":"result"}\n)
      {new_buf, messages} = LineBuffer.append(buf, data)

      assert new_buf.buffer == ""
      assert [%{"type" => "system"}, %{"type" => "result"}] = messages
    end

    test "buffers partial data without newline" do
      buf = LineBuffer.new()
      {new_buf, messages} = LineBuffer.append(buf, ~s({"type":"sys))

      assert new_buf.buffer == ~s({"type":"sys)
      assert messages == []
    end

    test "completes partial data across two appends" do
      buf = LineBuffer.new()
      {buf2, []} = LineBuffer.append(buf, ~s({"type":))
      {buf3, messages} = LineBuffer.append(buf2, ~s("system"}\n))

      assert buf3.buffer == ""
      assert [%{"type" => "system"}] = messages
    end

    test "handles mixed complete and partial lines" do
      buf = LineBuffer.new()
      data = ~s({"a":1}\n{"b":)
      {new_buf, messages} = LineBuffer.append(buf, data)

      assert new_buf.buffer == ~s({"b":)
      assert [%{"a" => 1}] = messages
    end

    test "skips empty lines" do
      buf = LineBuffer.new()
      {new_buf, messages} = LineBuffer.append(buf, ~s(\n\n{"type":"x"}\n\n))

      assert new_buf.buffer == ""
      assert [%{"type" => "x"}] = messages
    end

    test "skips non-JSON lines" do
      buf = LineBuffer.new()
      data = ~s(some debug output\n{"type":"ok"}\n)
      {_buf, messages} = LineBuffer.append(buf, data)

      assert [%{"type" => "ok"}] = messages
    end

    @tag :capture_log
    test "discards buffer when exceeding max size limit" do
      buf = LineBuffer.new()
      # Create data exceeding 10MB limit
      large_data = String.duplicate("x", 10_485_761)
      {new_buf, messages} = LineBuffer.append(buf, large_data)

      assert new_buf.buffer == ""
      assert messages == []
    end
  end

  describe "accumulate/2" do
    test "returns {:ok, buffer} for normal chunks" do
      buf = LineBuffer.new()
      assert {:ok, new_buf} = LineBuffer.accumulate(buf, "partial data")
      assert new_buf.buffer == "partial data"
    end

    test "accumulates across multiple calls" do
      buf = LineBuffer.new()
      {:ok, buf2} = LineBuffer.accumulate(buf, "part1")
      {:ok, buf3} = LineBuffer.accumulate(buf2, "part2")
      assert buf3.buffer == "part1part2"
    end

    @tag :capture_log
    test "returns error on buffer overflow" do
      buf = LineBuffer.new()
      large_chunk = String.duplicate("x", 10_485_761)
      assert {:error, :buffer_overflow} = LineBuffer.accumulate(buf, large_chunk)
    end
  end
end
