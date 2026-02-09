---Utility functions for tmux provider operations
---Handles TTY detection and process-to-pane mapping
---
---This module provides low-level utilities for working with tmux panes and processes.
---All functions are pure (no side effects) and return nil/empty on errors.
---
---@module opencode.provider.tmux_util
local M = {}

---Get the TTY device for a process
---
---Uses the `ps` command to get the controlling TTY for a process.
---Returns nil if the process has no TTY (e.g., daemon processes) or if the process doesn't exist.
---
---@param pid number Process ID
---@return string|nil tty The TTY name without /dev/ prefix (e.g., "ttys001"), or nil if none
function M.get_process_tty(pid)
  local ps_result = vim.system({ "ps", "-o", "tty=", "-p", tostring(pid) }, { text = true }):wait()
  if ps_result.code ~= 0 or not ps_result.stdout then
    return nil
  end

  local tty = vim.trim(ps_result.stdout)
  if tty == "" or tty == "??" then
    return nil -- No TTY or detached process
  end

  return tty -- e.g., "ttys001" (no /dev/ prefix)
end

---Get all visible tmux pane TTYs as a set
---
---Queries tmux for all panes across all sessions and returns their TTYs.
---Returns an empty table if tmux is not available or no panes exist.
---
---@return table<string, boolean> Map of TTY names (without /dev/) to true (e.g., {["ttys001"] = true})
function M.get_visible_pane_ttys()
  local result = vim.system({ "tmux", "list-panes", "-a", "-F", "#{pane_tty}" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return {}
  end

  local ttys = {}
  for tty_path in result.stdout:gmatch("[^\r\n]+") do
    -- Strip /dev/ prefix: "/dev/ttys001" -> "ttys001"
    local tty = tty_path:match("^/dev/(.+)$")
    if tty then
      ttys[tty] = true
    end
  end
  return ttys
end

---Check if a process is in a visible tmux pane
---
---Uses TTY-based detection to determine if a process is running in a visible tmux pane.
---A process is considered "in a visible pane" if:
---  1. It has a controlling TTY
---  2. That TTY matches a currently visible tmux pane's TTY
---
---This is useful for detecting "orphaned" processes - processes that were started in tmux panes
---that have since been closed or detached.
---
---@param pid number Process ID
---@return boolean visible True if process is in a visible tmux pane, false otherwise
function M.is_process_in_visible_pane(pid)
  local tty = M.get_process_tty(pid)
  if not tty then
    return false -- No TTY = not in a pane
  end

  local visible_ttys = M.get_visible_pane_ttys()
  return visible_ttys[tty] == true
end

return M
