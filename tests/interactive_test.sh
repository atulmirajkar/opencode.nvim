#!/bin/bash
# Interactive test for OpenCode.nvim
# Creates a split tmux layout for visual testing
#
# Run with: tests/interactive_test.sh (or ./tests/interactive_test.sh from root)

set -e

echo "=========================================="
echo "OpenCode.nvim - Interactive Test"
echo "=========================================="
echo ""

# Check if we're in tmux
if [ -z "$TMUX" ]; then
    echo "❌ Not running inside a tmux session"
    echo "   Starting tmux for you..."
    tmux new-session "$0"
    exit 0
fi

# Get script directory and cd to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

# Create a nice layout - split the window
echo "Setting up test layout..."
tmux split-window -h -l 50%

# In the right pane, show instructions
tmux send-keys -t 1 'clear' C-m
tmux send-keys -t 1 'echo "╔════════════════════════════════════════╗"' C-m
tmux send-keys -t 1 'echo "║   OpenCode Pane Will Appear Here     ║"' C-m
tmux send-keys -t 1 'echo "║                                       ║"' C-m
tmux send-keys -t 1 'echo "║   Watch for the opencode TUI to      ║"' C-m
tmux send-keys -t 1 'echo "║   appear when you start the test     ║"' C-m
tmux send-keys -t 1 'echo "╚════════════════════════════════════════╝"' C-m

# Focus back on left pane
tmux select-pane -t 0

# Create test nvim session
cat > /tmp/interactive_test.lua << 'EOF'
-- Interactive test configuration
vim.g.opencode_opts = {
  provider = {
    enabled = "tmux",
    tmux = {
      options = "-h -l 50%",  -- Split 50% horizontally
      focus = false,
    }
  }
}

vim.o.autoread = true

-- Create a scratch buffer with instructions
vim.cmd('enew')
vim.bo.buftype = 'nofile'
vim.bo.bufhidden = 'hide'
vim.bo.swapfile = false

local lines = {
  "╔════════════════════════════════════════════════════════╗",
  "║        OpenCode.nvim Tmux Provider Test               ║",
  "╚════════════════════════════════════════════════════════╝",
  "",
  "This test will verify the tmux provider fix works correctly.",
  "",
  "STEP 1: Check Provider Status",
  "  Run: :lua print(vim.inspect(require('opencode.config').provider))",
  "  Expected: provider.name = 'tmux', provider.cmd = 'opencode --port'",
  "",
  "STEP 2: Start OpenCode in Tmux Pane",
  "  Run: :lua require('opencode.provider').start()",
  "  Or press: <Space>s",
  "  Expected: New tmux pane appears with opencode TUI",
  "",
  "STEP 3: Send a Test Prompt",
  "  Run: :lua require('opencode').prompt('Hello from Neovim! Please respond.')",
  "  Or press: <Space>t",
  "  Expected: OpenCode receives and responds to the prompt",
  "",
  "STEP 4: Toggle OpenCode",
  "  Press: <C-.>",
  "  Expected: OpenCode pane hides/shows",
  "",
  "════════════════════════════════════════════════════════",
  "",
  "Quick Test Keybindings:",
  "  <Space>s  - Start opencode",
  "  <Space>t  - Send test prompt",
  "  <Space>a  - Ask opencode (custom input)",
  "  <C-.>     - Toggle opencode pane",
  "  <Space>q  - Quit and clean up",
  "",
  "════════════════════════════════════════════════════════",
  "",
  "Status: Ready to test!",
}

vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.bo.modifiable = false

-- Set up test keybindings
vim.keymap.set('n', '<Space>s', function()
  print("Starting opencode provider...")
  local ok, err = pcall(require('opencode.provider').start)
  if ok then
    print("✓ Provider started! Check the tmux pane →")
  else
    print("❌ Error: " .. tostring(err))
  end
end, { desc = "Start opencode" })

vim.keymap.set('n', '<Space>t', function()
  print("Sending test prompt...")
  local ok, err = pcall(require('opencode').prompt, "Hello from Neovim! This is a test of the tmux provider fix. Please respond with a brief confirmation.")
  if ok then
    print("✓ Prompt sent! Check the opencode pane →")
  else
    print("❌ Error: " .. tostring(err))
  end
end, { desc = "Send test prompt" })

vim.keymap.set('n', '<Space>a', function()
  require('opencode').ask("", { submit = false })
end, { desc = "Ask opencode" })

vim.keymap.set({ 'n', 't' }, '<C-.>', function()
  require('opencode').toggle()
end, { desc = "Toggle opencode" })

vim.keymap.set('n', '<Space>q', function()
  print("Cleaning up...")
  pcall(require('opencode.provider').stop)
  vim.cmd('qall!')
end, { desc = "Quit and cleanup" })

-- Show initial status
vim.defer_fn(function()
  local provider = require('opencode.config').provider
  if provider then
    print("\n✓ Provider loaded: " .. provider.name)
    print("✓ Command: " .. (provider.cmd or "nil"))
    print("\nPress <Space>s to start the test!")
  else
    print("❌ Provider not loaded")
  end
end, 100)
EOF

echo ""
echo "Starting interactive test..."
echo ""
echo "Instructions:"
echo "  1. Neovim will open in the left pane"
echo "  2. Follow the on-screen instructions"
echo "  3. Press <Space>s to start opencode"
echo "  4. Press <Space>t to send a test prompt"
echo "  5. Watch the right pane for opencode's response"
echo ""
echo "Press Enter to continue..."
read

# Start nvim in the left pane
nvim -u test_config.lua -c "luafile /tmp/interactive_test.lua"

# Cleanup after nvim exits
echo ""
echo "Test complete!"
echo ""
