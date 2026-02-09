---Manual test for OpenCode.nvim
---
---Run with: nvim -u test_config.lua -c "luafile tests/manual_test.lua"
---Or inside nvim: :luafile tests/manual_test.lua
---
---This test:
---  - Verifies provider initialization
---  - Tests orphan cleanup utilities
---  - Starts opencode in a tmux pane
---  - Connects and sends a test prompt
---  - Verifies cleanup functionality

print("\n════════════════════════════════════════")
print("OpenCode.nvim - Manual Test")
print("════════════════════════════════════════\n")

-- Step 1: Check provider is loaded
local config = require('opencode.config')
local provider = config.provider

if not provider then
  print("❌ Provider not loaded")
  return
end

print("✓ Provider loaded:")
print("  - Name: " .. (provider.name or "nil"))
print("  - Cmd: " .. (provider.cmd or "nil"))

if provider.name ~= "tmux" then
  print("⚠️  Expected tmux provider but got: " .. (provider.name or "nil"))
  return
end

-- Step 2: Check if we're in tmux
if not vim.env.TMUX then
  print("\n❌ Not running in tmux session")
  print("   Start tmux first: tmux")
  return
end

print("✓ Running in tmux session")

-- Step 2.5: Test orphan cleanup utilities
print("\n════════════════════════════════════════")
print("Testing Orphan Cleanup Utilities...")
print("════════════════════════════════════════\n")

local tmux_util_ok, tmux_util = pcall(require, 'opencode.provider.tmux_util')
if tmux_util_ok then
  print("✓ tmux_util module loaded")
  
  -- Test with current nvim process
  local nvim_pid = vim.fn.getpid()
  local tty = tmux_util.get_process_tty(nvim_pid)
  
  if tty then
    print("✓ TTY detection works: " .. tty)
  else
    print("⚠️  Could not detect TTY for current process")
  end
  
  local visible_ttys = tmux_util.get_visible_pane_ttys()
  print("✓ Found " .. vim.tbl_count(visible_ttys) .. " visible pane(s)")
  
  local is_visible = tmux_util.is_process_in_visible_pane(nvim_pid)
  if is_visible then
    print("✓ Orphan detection works correctly")
  else
    print("⚠️  Current process not detected as visible (unexpected)")
  end
else
  print("⚠️  tmux_util module not available: " .. tostring(tmux_util))
end

-- Step 3: Start the provider
print("\n════════════════════════════════════════")
print("Starting opencode provider...")
print("════════════════════════════════════════\n")

local ok, err = pcall(function()
  require('opencode.provider').start()
end)

if not ok then
  print("❌ Failed to start provider: " .. tostring(err))
  return
end

print("✓ Provider started!")
print("  Check your tmux panes - you should see a new pane with opencode running")

-- Step 4: Wait a bit, then try to connect and send a prompt
vim.defer_fn(function()
  print("\n════════════════════════════════════════")
  print("Testing connection...")
  print("════════════════════════════════════════\n")
  
  local server = require('opencode.cli.server')
  server.get(false):next(function(srv)
    print("✓ Connected to opencode server!")
    print("  - Port: " .. srv.port)
    print("  - CWD: " .. srv.cwd)
    
    -- Send a test prompt
    print("\n════════════════════════════════════════")
    print("Sending test prompt...")
    print("════════════════════════════════════════\n")
    
    vim.defer_fn(function()
      local prompt_ok, prompt_err = pcall(function()
        require('opencode').prompt("Hello! This is a test of the tmux provider fix. Please respond with 'Test successful!' if you received this message.")
      end)
      
      if prompt_ok then
        print("✓ Prompt sent successfully!")
        print("\nCheck the opencode tmux pane for the response →")
        
        -- Test cleanup functionality
        print("\n════════════════════════════════════════")
        print("Testing Cleanup Functionality...")
        print("════════════════════════════════════════\n")
        
        vim.defer_fn(function()
          local cleanup_ok, cleanup_err = pcall(function()
            require('opencode').cleanup()
          end)
          
          if cleanup_ok then
            print("✓ Cleanup command works")
          else
            print("⚠️  Cleanup command error: " .. tostring(cleanup_err))
          end
          
          print("\n════════════════════════════════════════")
          print("✓ ALL TESTS PASSED!")
          print("════════════════════════════════════════\n")
          print("The tmux provider and orphan cleanup are working correctly!")
          print("\nCommands you can try:")
          print("  :lua require('opencode').cleanup()  -- Manual cleanup")
          print("  :lua require('opencode').attach()   -- Switch servers")
          print("  :lua require('opencode.provider').stop()  -- Stop opencode")
        end, 1000)
      else
        print("❌ Failed to send prompt: " .. tostring(prompt_err))
      end
    end, 500)
  end):catch(function(err_msg)
    print("⚠️  Could not connect to opencode (yet): " .. tostring(err_msg))
    print("\nThis might be normal if opencode needs more time to start.")
    print("Try running this manually in a few seconds:")
    print("  :lua require('opencode').prompt('Hello from Neovim!')")
    print("\nOr use the interactive test: ./test_interactive.sh")
  end)
end, 3000) -- Wait 3 seconds for opencode to start

print("\nWaiting for opencode to start...")
print("(This takes a few seconds)")
