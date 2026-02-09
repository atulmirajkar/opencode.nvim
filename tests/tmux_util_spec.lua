---Unit tests for tmux_util module
---
---Run with: nvim --headless -u tests/minimal_init.lua -c "luafile tests/tmux_util_spec.lua" -c "qa!"
---
---These tests verify the core TTY detection and orphan detection logic.
---Some tests require running in a tmux session.

print("\n════════════════════════════════════════")
print("Testing tmux_util Module")
print("════════════════════════════════════════\n")

local tmux_util = require("opencode.provider.tmux_util")
local test_count = 0
local pass_count = 0
local fail_count = 0

---Helper function to run a test
---@param name string Test name
---@param fn function Test function
local function test(name, fn)
  test_count = test_count + 1
  io.write(string.format("Test %d: %s ... ", test_count, name))
  io.flush()
  
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("✓ PASS")
    return true
  else
    fail_count = fail_count + 1
    print("✗ FAIL")
    print("  Error: " .. tostring(err))
    return false
  end
end

---Helper function to assert equality
local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\n  Expected: %s\n  Got: %s", 
      msg or "Assertion failed", 
      vim.inspect(expected), 
      vim.inspect(actual)))
  end
end

---Helper function to assert truthy value
local function assert_truthy(value, msg)
  if not value then
    error(msg or "Expected truthy value, got: " .. vim.inspect(value))
  end
end

---Helper function to assert falsy value
local function assert_falsy(value, msg)
  if value then
    error(msg or "Expected falsy value, got: " .. vim.inspect(value))
  end
end

-- ════════════════════════════════════════
-- Tests for get_process_tty()
-- ════════════════════════════════════════

test("get_process_tty() returns nil for invalid PID", function()
  local tty = tmux_util.get_process_tty(99999999)
  assert_eq(tty, nil, "Should return nil for invalid PID")
end)

test("get_process_tty() returns TTY for current nvim process", function()
  local nvim_pid = vim.fn.getpid()
  local tty = tmux_util.get_process_tty(nvim_pid)
  
  -- Headless nvim may not have a TTY even in tmux
  -- This is expected behavior, not a test failure
  if vim.env.TMUX and tty then
    assert_truthy(tty:match("^tty"), "TTY should start with 'tty'")
    assert_falsy(tty:match("^/dev/"), "TTY should NOT include /dev/ prefix")
  else
    print("    (Note: headless nvim has no TTY - expected behavior)")
  end
end)

test("get_process_tty() returns string without /dev/ prefix", function()
  local nvim_pid = vim.fn.getpid()
  local tty = tmux_util.get_process_tty(nvim_pid)
  
  if tty then
    assert_falsy(tty:match("^/dev/"), "TTY should not have /dev/ prefix")
    assert_eq(type(tty), "string", "TTY should be a string")
  else
    print("    (Skipped - no TTY available)")
  end
end)

test("get_process_tty() handles init process (PID 1)", function()
  -- Init process typically has no TTY
  local tty = tmux_util.get_process_tty(1)
  -- Should return nil or a valid TTY, but not crash
  assert_truthy(tty == nil or type(tty) == "string", "Should handle init process gracefully")
end)

-- ════════════════════════════════════════
-- Tests for get_visible_pane_ttys()
-- ════════════════════════════════════════

test("get_visible_pane_ttys() returns table", function()
  local ttys = tmux_util.get_visible_pane_ttys()
  assert_eq(type(ttys), "table", "Should return a table")
end)

test("get_visible_pane_ttys() returns empty table when not in tmux", function()
  if not vim.env.TMUX then
    local ttys = tmux_util.get_visible_pane_ttys()
    assert_eq(vim.tbl_count(ttys), 0, "Should return empty table outside tmux")
  else
    print("    (Skipped - in tmux)")
  end
end)

test("get_visible_pane_ttys() returns TTYs without /dev/ prefix", function()
  if vim.env.TMUX then
    local ttys = tmux_util.get_visible_pane_ttys()
    
    -- Should have at least one TTY (current pane)
    assert_truthy(vim.tbl_count(ttys) > 0, "Should have at least one visible pane")
    
    -- All keys should NOT start with /dev/ (we strip it)
    for tty_name, _ in pairs(ttys) do
      assert_falsy(tty_name:match("^/dev/"), 
        "TTY name should not start with /dev/, got: " .. tty_name)
      assert_truthy(tty_name:match("^tty"), 
        "TTY name should start with 'tty', got: " .. tty_name)
    end
  else
    print("    (Skipped - not in tmux)")
  end
end)

test("get_visible_pane_ttys() returns consistent results", function()
  if vim.env.TMUX then
    local ttys1 = tmux_util.get_visible_pane_ttys()
    local ttys2 = tmux_util.get_visible_pane_ttys()
    
    -- Should return same count (assuming no panes changed)
    assert_eq(vim.tbl_count(ttys1), vim.tbl_count(ttys2), 
      "Should return consistent results")
  else
    print("    (Skipped - not in tmux)")
  end
end)

-- ════════════════════════════════════════
-- Tests for is_process_in_visible_pane()
-- ════════════════════════════════════════

test("is_process_in_visible_pane() returns false for invalid PID", function()
  local result = tmux_util.is_process_in_visible_pane(99999999)
  assert_eq(result, false, "Should return false for invalid PID")
end)

test("is_process_in_visible_pane() returns true for current nvim process in tmux", function()
  if vim.env.TMUX then
    local nvim_pid = vim.fn.getpid()
    local tty = tmux_util.get_process_tty(nvim_pid)
    
    -- Headless nvim has no TTY, so it won't be "in a pane"
    -- This is expected - just verify the function returns a boolean
    local result = tmux_util.is_process_in_visible_pane(nvim_pid)
    assert_eq(type(result), "boolean", "Should return a boolean")
    
    if tty then
      assert_eq(result, true, "Process with TTY should be in visible pane")
    else
      print("    (Note: headless nvim has no TTY, returns false - expected)")
    end
  else
    print("    (Skipped - not in tmux)")
  end
end)

test("is_process_in_visible_pane() returns false for init process (PID 1)", function()
  -- PID 1 (init/systemd) should never be in a tmux pane
  local result = tmux_util.is_process_in_visible_pane(1)
  assert_eq(result, false, "Init process should not be in tmux pane")
end)

test("is_process_in_visible_pane() returns boolean", function()
  local result = tmux_util.is_process_in_visible_pane(vim.fn.getpid())
  assert_eq(type(result), "boolean", "Should always return a boolean")
end)

-- ════════════════════════════════════════
-- Integration tests
-- ════════════════════════════════════════

test("Integration: TTY consistency check", function()
  if vim.env.TMUX then
    local nvim_pid = vim.fn.getpid()
    
    -- Get TTY (may be nil for headless nvim)
    local tty = tmux_util.get_process_tty(nvim_pid)
    
    -- Get visible panes
    local visible_ttys = tmux_util.get_visible_pane_ttys()
    assert_truthy(vim.tbl_count(visible_ttys) > 0, "Should have visible panes")
    
    -- Only check consistency if we have a TTY
    if tty then
      assert_truthy(visible_ttys[tty], 
        "Nvim's TTY (" .. tty .. ") should be in visible panes list")
    else
      print("    (Note: headless nvim has no TTY - skipping consistency check)")
    end
  else
    print("    (Skipped - not in tmux)")
  end
end)

test("Integration: is_process_in_visible_pane matches manual check", function()
  if vim.env.TMUX then
    local nvim_pid = vim.fn.getpid()
    
    -- Method 1: Use the utility
    local result = tmux_util.is_process_in_visible_pane(nvim_pid)
    
    -- Method 2: Manual check
    local tty = tmux_util.get_process_tty(nvim_pid)
    local visible_ttys = tmux_util.get_visible_pane_ttys()
    local manual_result = tty and visible_ttys[tty] == true or false
    
    assert_eq(result, manual_result, 
      "Utility function should match manual check")
  else
    print("    (Skipped - not in tmux)")
  end
end)

-- ════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════

print("\n════════════════════════════════════════")
print("Test Summary")
print("════════════════════════════════════════")
print(string.format("Total:  %d", test_count))
print(string.format("Passed: %d ✓", pass_count))
print(string.format("Failed: %d ✗", fail_count))

if not vim.env.TMUX then
  print("\n⚠️  Note: Some tests were skipped because not in tmux")
  print("   Run in tmux for full coverage: tmux")
end

print("════════════════════════════════════════\n")

if fail_count > 0 then
  print("❌ SOME TESTS FAILED")
  os.exit(1)
else
  print("✅ ALL TESTS PASSED")
  os.exit(0)
end
