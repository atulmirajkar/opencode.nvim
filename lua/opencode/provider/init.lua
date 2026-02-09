---@module 'snacks.terminal'

---Provide an integrated `opencode`.
---Providers should ignore manually-started `opencode` instances,
---operating only on those they start themselves.
---@class opencode.Provider
---
---The name of the provider.
---@field name? string
---
---The command to start `opencode`.
---The `--port` flag _must_ be present to expose the server for `opencode.nvim` to connect to.
---`opencode.nvim` will set `--port <opts.port>` if present.
---See all available flags [here](https://opencode.ai/docs/cli/#flags).
---@field cmd? string
---
---@field new? fun(opts: table): opencode.Provider
---
---Toggle `opencode`.
---@field toggle? fun(self: opencode.Provider)
---
---Start `opencode`.
---Called when attempting to interact with `opencode` but none was found.
---`opencode.nvim` then polls for a couple seconds waiting for one to appear.
---Should not steal focus by default, if possible.
---@field start? fun(self: opencode.Provider)
---
---Stop the previously started `opencode`.
---Called when Neovim is exiting.
---@field stop? fun(self: opencode.Provider)
---
---Health check for the provider.
---Should return `true` if the provider is available,
---else a reason string and optional advice (for `vim.health.warn`).
---@field health? fun(): boolean|string, ...string|string[]

---Configure and enable built-in providers.
---@class opencode.provider.Opts
---
---The built-in provider to use, or `false` for none.
---Default order:
---  - `"snacks"` if `snacks.terminal` is available and enabled
---  - `"kitty"` if in a `kitty` session with remote control enabled
---  - `"wezterm"` if in a `wezterm` window
---  - `"tmux"` if in a `tmux` session
---  - `"terminal"` as a fallback
---@field enabled? "terminal"|"snacks"|"kitty"|"wezterm"|"tmux"|false
---
---@field terminal? opencode.provider.terminal.Opts
---@field snacks? opencode.provider.snacks.Opts
---@field kitty? opencode.provider.kitty.Opts
---@field wezterm? opencode.provider.wezterm.Opts
---@field tmux? opencode.provider.tmux.Opts

local M = {}

-- Track if cleanup has been run this session
local cleanup_done = false

---Get all providers.
---@return opencode.Provider[]
function M.list()
  return {
    require("opencode.provider.snacks"),
    require("opencode.provider.kitty"),
    require("opencode.provider.wezterm"),
    require("opencode.provider.tmux"),
    require("opencode.provider.terminal"),
  }
end

---Toggle `opencode` via the configured provider.
function M.toggle()
  local provider = require("opencode.config").provider
  if provider and provider.toggle then
    provider:toggle()
  else
    error("`provider.toggle` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

---Start `opencode` via the configured provider.
function M.start()
  local provider = require("opencode.config").provider
  if provider and provider.start then
    -- Run cleanup once per Neovim session (lazy cleanup on first use)
    if not cleanup_done and provider.cleanup_orphaned_panes then
      local count = provider:cleanup_orphaned_panes()
      if count > 0 then
        vim.notify("Cleaned up " .. count .. " orphaned OpenCode process(es)", 
                   vim.log.levels.INFO, { title = "opencode" })
      end
      cleanup_done = true
    end
    
    -- TODO: Subscribe immediately.
    -- Ideally, providers expose the PID of the process they started.
    -- Then we decompose server.lua code to go PID -> port (OS dependent... windows impl combines this with the PID step currently) -> server -> connect.
    provider:start()
  else
    error("`provider.start` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

---Stop `opencode` via the configured provider.
function M.stop()
  local provider = require("opencode.config").provider
  if provider and provider.stop then
    provider:stop()
    require("opencode.events").disconnect()
  else
    error("`provider.stop` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

---Cleanup orphaned opencode processes via the configured provider.
function M.cleanup()
  local provider = require("opencode.config").provider
  if provider and provider.cleanup_orphaned_panes then
    local ok, result = pcall(provider.cleanup_orphaned_panes, provider)
    if ok then
      local count = result or 0
      if count > 0 then
        vim.notify("Cleaned up " .. count .. " orphaned OpenCode pane(s)", vim.log.levels.INFO, { title = "opencode" })
      else
        vim.notify("No orphaned OpenCode panes found", vim.log.levels.INFO, { title = "opencode" })
      end
    else
      vim.notify("Cleanup failed: " .. tostring(result), vim.log.levels.ERROR, { title = "opencode" })
    end
  else
    vim.notify("Cleanup not supported by current provider", vim.log.levels.WARN, { title = "opencode" })
  end
end

---Check if the provider can auto-start (currently only tmux provider is supported).
---@return boolean
function M.can_auto_start()
  local provider = require("opencode.config").provider
  if not provider or not provider.start then
    return false
  end
  
  -- Only auto-start for tmux provider (safest option)
  if provider.name == "tmux" then
    return true
  end
  
  return false
end

---Attach to the tmux pane of the currently connected server (tmux provider only).
---@return boolean success Whether the attachment was successful
function M.attach_to_connected_server()
  local provider = require("opencode.config").provider
  local connected_server = require("opencode.events").connected_server
  
  if not provider or not connected_server then
    return false
  end
  
  -- Only tmux provider supports attach_to_server
  if provider.name == "tmux" and type(provider.attach_to_server) == "function" then
    return provider:attach_to_server(connected_server)
  end
  
  return false
end

return M
