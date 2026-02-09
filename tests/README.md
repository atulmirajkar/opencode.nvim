# OpenCode.nvim Tests

This directory contains all tests for opencode.nvim, including unit tests, integration tests, and manual/interactive tests.

## Quick Start

### Run All Automated Tests
```bash
./run_tests.sh
```

This runs:
- Unit tests (`tests/tmux_util_spec.lua`) - 14 tests
- Integration tests (`tests/orphan_cleanup_integration_spec.lua`) - 11 tests

**Requirements:**
- Neovim installed
- Running in a tmux session (for full coverage)

---

## Test Structure

### Automated Tests (Recommended)

#### 1. **Unit Tests** (`tests/tmux_util_spec.lua`)
Tests for the `tmux_util` module:
- TTY detection (`get_process_tty`)
- Visible pane enumeration (`get_visible_pane_ttys`)
- Orphan detection (`is_process_in_visible_pane`)

**Run:**
```bash
nvim --headless -u tests/minimal_init.lua -c "luafile tests/tmux_util_spec.lua" -c "qa!"
```

#### 2. **Integration Tests** (`tests/orphan_cleanup_integration_spec.lua`)
Tests for end-to-end functionality:
- Module loading and integration
- Cleanup functionality
- Server.lua and tmux provider integration

**Run:**
```bash
nvim --headless -u tests/minimal_init.lua -c "luafile tests/orphan_cleanup_integration_spec.lua" -c "qa!"
```

---

### Manual Tests (For Development)

#### 3. **Manual Test** (`tests/manual_test.lua`)
Interactive Lua test that:
- Verifies provider initialization
- Tests orphan cleanup utilities
- Starts opencode and sends test prompts
- Checks cleanup functionality

**Run:**
```bash
# From project root
nvim -u test_config.lua -c "luafile tests/manual_test.lua"

# Or inside nvim:
:luafile tests/manual_test.lua
```

#### 4. **Interactive Test** (`tests/interactive_test.sh`)
Visual split-pane test:
- Creates tmux split layout
- Opens nvim with test keybindings
- Shows opencode side-by-side
- Interactive controls for testing

**Run:**
```bash
# From project root
tests/interactive_test.sh

# Or from tests directory
cd tests && ./interactive_test.sh
```

**Keybindings in interactive test:**
- `<Space>s` - Start opencode
- `<Space>t` - Send test prompt
- `<Space>a` - Ask opencode (custom)
- `<C-.>` - Toggle opencode pane
- `<Space>q` - Quit and cleanup

---

## Test Configuration

### `minimal_init.lua`
Minimal Neovim configuration for running automated tests:
- Adds plugin to runtimepath
- Suppresses notifications during tests
- Minimal vim options

### `test_config.lua` (Root)
Minimal configuration for manual testing:
- Full lazy.nvim setup
- Tmux provider configured
- Test keybindings

---

## What Gets Tested

### ✅ Core Functionality
- TTY detection and process tracking
- Orphan process identification
- Cleanup of orphaned opencode processes
- Server filtering (only show visible servers)
- Provider integration (tmux.lua)
- Server module integration (server.lua)

### ✅ Edge Cases
- Headless nvim (no TTY)
- Invalid PIDs
- Non-tmux environments
- Process consistency checks

### ✅ Integrations
- Module loading
- Cross-module communication
- Cleanup triggers (auto and manual)
- End-to-end workflows

---

## Adding New Tests

### For Unit Tests
Add test cases to `tests/tmux_util_spec.lua`:

```lua
test("Your test description", function()
  local result = tmux_util.your_function()
  assert_eq(result, expected_value, "Should do X")
end)
```

### For Integration Tests
Add test cases to `tests/orphan_cleanup_integration_spec.lua`:

```lua
test("Integration: Your scenario", function()
  -- Setup
  local module = require("opencode.your_module")
  
  -- Execute
  local result = module.your_function()
  
  -- Verify
  assert_truthy(result, "Should work correctly")
end)
```

---

## Troubleshooting

### Tests Fail with "Not in tmux"
Some tests require tmux. Start a tmux session first:
```bash
tmux
./run_tests.sh
```

### Tests Can't Find Modules
Make sure you're running from the project root:
```bash
cd /path/to/opencode.nvim
./run_tests.sh
```

### Manual Test Doesn't Show Pane
Check that:
1. You're in a tmux session (`echo $TMUX`)
2. opencode is installed (`which opencode`)
3. Provider is configured correctly (`:checkhealth opencode`)

---

## CI/CD Integration

To run tests in CI:

```yaml
- name: Run Tests
  run: |
    # Install dependencies
    sudo apt-get install tmux neovim
    
    # Start tmux
    tmux new-session -d
    
    # Run tests in tmux
    tmux send-keys "./run_tests.sh" C-m
```

---

## Test Coverage

Current coverage:
- **Unit tests:** 14 tests (100% coverage of tmux_util)
- **Integration tests:** 11 tests (key integrations covered)
- **Manual tests:** Provider initialization, cleanup, prompts

**Total:** 25 automated tests + 2 manual test suites

---

## Questions?

- See main `README.md` for plugin documentation
- Check `:help opencode` for usage
- Run `:checkhealth opencode` for diagnostics
