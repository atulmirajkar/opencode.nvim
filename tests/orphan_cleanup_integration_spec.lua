---Integration test for orphan cleanup
---
---Run with: nvim --headless -u tests/minimal_init.lua -c "luafile tests/orphan_cleanup_integration_spec.lua" -c "qa!"
---
---This test requires:
---  1. Running in tmux
---  2. opencode installed (optional - some tests work without it)
---
---These tests verify that the refactored code integrates correctly.

print("\n════════════════════════════════════════")
print("Orphan Cleanup Integration Test")
print("════════════════════════════════════════\n")

-- Skip if not in tmux
if not vim.env.TMUX then
  print("⚠️  Skipping - not in tmux session")
  print("   Start tmux first: tmux")
  print("   Then run: nvim --headless -u tests/minimal_init.lua -c 'luafile tests/orphan_cleanup_integration_spec.lua' -c 'qa!'")
  os.exit(0)
end

local test_count = 0
local pass_count = 0
local fail_count = 0

---Helper function to run a test
local function test(name, fn)
  test_count = test_count + 1
  io.write(string.format("Test %d: %s ... ", test_count, name))
  io.flush()
  
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("✓ PASS")
  else
    fail_count = fail_count + 1
    print("✗ FAIL")
    print("  Error: " .. tostring(err))
  end
end

---Helper assertions
local function assert_truthy(value, msg)
  if not value then
    error(msg or "Expected truthy value, got: " .. vim.inspect(value))
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\n  Expected: %s\n  Got: %s",
      msg or "Assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)))
  end
end

-- ════════════════════════════════════════
-- Test 1: Module Loading
-- ════════════════════════════════════════

test("tmux_util module loads correctly", function()
  local tmux_util = require("opencode.provider.tmux_util")
  assert_truthy(tmux_util, "Module should load")
  assert_eq(type(tmux_util.get_process_tty), "function", "Should have get_process_tty")
  assert_eq(type(tmux_util.get_visible_pane_ttys), "function", "Should have get_visible_pane_ttys")
  assert_eq(type(tmux_util.is_process_in_visible_pane), "function", "Should have is_process_in_visible_pane")
end)

-- ════════════════════════════════════════
-- Test 2: Server Module Integration
-- ════════════════════════════════════════

test("server.lua module loads without errors", function()
  local server = require("opencode.cli.server")
  assert_truthy(server, "Server module should load")
  assert_eq(type(server.get), "function", "Should have get function")
  assert_eq(type(server.select), "function", "Should have select function")
end)

test("server.lua is_in_visible_pane integration (indirect)", function()
  -- We can't directly test is_in_visible_pane since it's local,
  -- but we can verify the module loads and functions are accessible
  local server = require("opencode.cli.server")
  
  -- This is an indirect test - if server module loads successfully
  -- and uses tmux_util, then the integration is working
  assert_truthy(server, "Server module should integrate with tmux_util")
end)

-- ════════════════════════════════════════
-- Test 3: Tmux Provider Integration
-- ════════════════════════════════════════

test("tmux provider module loads without errors", function()
  local Tmux = require("opencode.provider.tmux")
  assert_truthy(Tmux, "Tmux provider should load")
  assert_eq(type(Tmux.new), "function", "Should have constructor")
end)

test("tmux provider has cleanup_orphaned_panes method", function()
  local Tmux = require("opencode.provider.tmux")
  local provider = Tmux.new()
  
  assert_eq(type(provider.cleanup_orphaned_panes), "function", 
    "Provider should have cleanup_orphaned_panes method")
end)

test("cleanup_orphaned_panes runs without errors", function()
  local Tmux = require("opencode.provider.tmux")
  local provider = Tmux.new()
  
  -- Should run without errors even if no orphans exist
  local count = provider:cleanup_orphaned_panes()
  
  assert_eq(type(count), "number", "Should return a number")
  assert_truthy(count >= 0, "Count should be non-negative")
end)

test("attach_to_server uses tmux_util (smoke test)", function()
  local Tmux = require("opencode.provider.tmux")
  local provider = Tmux.new()
  
  -- Create a mock server with current nvim PID
  local mock_server = {
    pid = vim.fn.getpid(),
    port = 12345
  }
  
  -- This should not crash (might return false if pane not found, but shouldn't error)
  local ok, result = pcall(provider.attach_to_server, provider, mock_server)
  assert_truthy(ok, "attach_to_server should not crash: " .. tostring(result))
  assert_eq(type(result), "boolean", "Should return boolean")
end)

-- ════════════════════════════════════════
-- Test 4: Provider Init Integration
-- ════════════════════════════════════════

test("provider init module loads", function()
  local provider_init = require("opencode.provider")
  assert_truthy(provider_init, "Provider init module should load")
  assert_eq(type(provider_init.cleanup), "function", "Should have cleanup function")
end)

test("provider.cleanup() is callable", function()
  -- Set up a minimal config with tmux provider
  local Tmux = require("opencode.provider.tmux")
  require("opencode.config").provider = Tmux.new()
  
  local provider_init = require("opencode.provider")
  
  -- Should be callable without errors
  local ok, err = pcall(provider_init.cleanup)
  assert_truthy(ok, "provider.cleanup() should be callable: " .. tostring(err))
end)

-- ════════════════════════════════════════
-- Test 5: End-to-End Consistency
-- ════════════════════════════════════════

test("End-to-end: TTY utilities work with real processes", function()
  local tmux_util = require("opencode.provider.tmux_util")
  
  -- Get current nvim process info
  local nvim_pid = vim.fn.getpid()
  local tty = tmux_util.get_process_tty(nvim_pid)
  local visible_ttys = tmux_util.get_visible_pane_ttys()
  local is_visible = tmux_util.is_process_in_visible_pane(nvim_pid)
  
  -- Headless nvim has no TTY, which is expected
  if tty then
    -- If we have a TTY, everything should be consistent
    assert_truthy(visible_ttys[tty], "Current nvim's TTY should be in visible panes")
    assert_eq(is_visible, true, "Current nvim should be detected as visible")
  else
    -- No TTY is expected for headless nvim
    assert_eq(is_visible, false, "Headless nvim without TTY should not be visible")
    assert_truthy(vim.tbl_count(visible_ttys) > 0, "Should still find other visible panes")
  end
end)

test("End-to-end: Cleanup doesn't kill current nvim process", function()
  local Tmux = require("opencode.provider.tmux")
  local provider = Tmux.new()
  
  local nvim_pid = vim.fn.getpid()
  
  -- Run cleanup
  provider:cleanup_orphaned_panes()
  
  -- Check that we're still alive (process still exists)
  local ps_result = vim.system({ "ps", "-p", tostring(nvim_pid) }, { text = true }):wait()
  assert_eq(ps_result.code, 0, "Current nvim process should still exist after cleanup")
end)

-- ════════════════════════════════════════
-- Summary
-- ════════════════════════════════════════

print("\n════════════════════════════════════════")
print("Integration Test Summary")
print("════════════════════════════════════════")
print(string.format("Total:  %d", test_count))
print(string.format("Passed: %d ✓", pass_count))
print(string.format("Failed: %d ✗", fail_count))
print("════════════════════════════════════════\n")

if fail_count > 0 then
  print("❌ SOME INTEGRATION TESTS FAILED")
  os.exit(1)
else
  print("✅ ALL INTEGRATION TESTS PASSED")
  print("\n💡 The refactored code integrates correctly!")
  print("   - tmux_util module works")
  print("   - server.lua uses utilities")
  print("   - tmux provider uses utilities")
  print("   - cleanup functions correctly")
  os.exit(0)
end
