---Provide `opencode` in a [`tmux`](https://github.com/tmux/tmux) pane in the current window.
---@class opencode.provider.Tmux : opencode.Provider
---
---@field cmd string
---@field opts opencode.provider.tmux.Opts
---
---The `tmux` pane ID where `opencode` is running (internal use only).
---@field pane_id? string
---
---The port where `opencode` is listening (discovered after start).
---@field port? number
local Tmux = {}
Tmux.__index = Tmux
Tmux.name = "tmux"

---@class opencode.provider.tmux.Opts
---
---`tmux` options for creating the pane.
---@field options? string
---
---Focus the opencode pane when created. Default: `false`
---@field focus? boolean
--
---Allow `allow-passthrough` on the opencode pane.
-- When enabled, opencode.nvim will use your configured tmux `allow-passthrough` option on its pane.
-- This allows opencode to use OSC escape sequences, but may leak escape codes to the buffer
-- (e.g., "=31337;OK" appearing in your buffer).
--
-- Limitations of having allow-passthrough disabled in the opencode pane:
-- - can't display images
-- - can't use special (terminal specific; non-system) clipboards
-- - may have issues setting window properties like the title from the pane
--
-- If you enable this, consider also enabling `focus` to auto-focus the pane on creation,
-- which can help avoid OSC code leakage while opencode is sending escape sequences on startup.
--
-- Default: `false` (allow-passthrough is disabled to prevent OSC code leakage)
---@field allow_passthrough? boolean

---@param opts? opencode.provider.tmux.Opts
---@return opencode.provider.Tmux
function Tmux.new(opts)
  local self = setmetatable({}, Tmux)
  self.opts = opts or {}
  self.cmd = nil
  self.pane_id = nil
  self.port = nil
  return self
end

---Check if we're running in a `tmux` session.
function Tmux.health()
  if vim.fn.executable("tmux") ~= 1 then
    return "`tmux` executable not found in `$PATH`.", {
      "Install `tmux` and ensure it's in your `$PATH`.",
    }
  end

  if not vim.env.TMUX then
    return "Not running in a `tmux` session.", {
      "Launch Neovim in a `tmux` session.",
    }
  end

  return true
end

---Get the `tmux` pane ID where we started `opencode`, if it still exists.
---Ideally we'd find existing panes by title or command, but `tmux` doesn't make that straightforward.
---@return string|nil pane_id
function Tmux:get_pane_id()
  local ok = self.health()
  if ok ~= true then
    error(ok, 0)
  end

  if self.pane_id then
    -- Confirm it still exists
    if vim.fn.system("tmux list-panes -t " .. self.pane_id):match("can't find pane") then
      self.pane_id = nil
    end
  end

  return self.pane_id
end

---Create or kill the `opencode` pane.
function Tmux:toggle()
  local pane_id = self:get_pane_id()
  if pane_id then
    self:stop()
  else
    -- Check if there's a connected server we can attach to
    local connected_server = require("opencode.events").connected_server
    if connected_server and connected_server.pid then
      local attached = self:attach_to_server(connected_server)
      if attached then
        vim.notify("Attached to existing OpenCode pane", vim.log.levels.INFO, { title = "opencode" })
        return
      end
    end
    
    -- No connected server or attachment failed, start new pane
    self:start()
  end
end

---Start `opencode` in pane.
function Tmux:start()
  local pane_id = self:get_pane_id()
  if not pane_id then
    -- First, try to discover an existing opencode pane
    pane_id = self:discover_existing_pane()
    
    if pane_id then
      -- Reuse existing pane
      self.pane_id = vim.trim(pane_id)
      vim.notify("Reusing existing OpenCode pane " .. self.pane_id, vim.log.levels.INFO, { title = "opencode" })
      
      -- Discover the port after a short delay
      vim.defer_fn(function()
        self.port = self:discover_port()
        if self.port then
          vim.notify("Connected to OpenCode on port " .. self.port, vim.log.levels.INFO, { title = "opencode" })
        end
      end, 500)  -- Shorter delay since it's already running
    else
      -- Create new pane
      local detach_flag = self.opts.focus and "" or "-d"
      local raw_pane_id = vim.fn.system(
        string.format("tmux split-window %s -P -F '#{pane_id}' %s '%s'", detach_flag, self.opts.options or "", self.cmd)
      )
      self.pane_id = vim.trim(raw_pane_id)  -- FIX: Trim immediately
      
      local disable_passthrough = self.opts.allow_passthrough ~= true
      if disable_passthrough and self.pane_id and self.pane_id ~= "" then
        vim.fn.system(string.format("tmux set-option -t %s -p allow-passthrough off", self.pane_id))
      end
      
      -- Discover the port after opencode starts
      vim.defer_fn(function()
        self.port = self:discover_port()
        if self.port then
          vim.notify("OpenCode started on port " .. self.port, vim.log.levels.INFO, { title = "opencode" })
        end
      end, 2000)  -- Wait 2 seconds for opencode to start
    end
  end
end

---Kill the `opencode` pane.
function Tmux:stop()
  local pane_id = self:get_pane_id()
  if pane_id then
    local result = vim.fn.system("tmux kill-pane -t " .. pane_id)
    if vim.v.shell_error == 0 then
      vim.notify("Stopped OpenCode pane " .. pane_id, vim.log.levels.INFO, { title = "opencode" })
      self.pane_id = nil
      self.port = nil
    else
      vim.notify("Failed to kill pane " .. pane_id .. ": " .. vim.trim(result), vim.log.levels.WARN, { title = "opencode" })
      -- Still clear state since pane is likely gone
      self.pane_id = nil
      self.port = nil
    end
  end
end

---Discover the port that opencode is listening on in our pane
---@return number|nil port
function Tmux:discover_port()
  local pane_id = self:get_pane_id()
  if not pane_id then
    return nil
  end
  
  -- Get the shell PID of the pane
  local pane_pid_result = vim.fn.system(
    string.format("tmux display -p -t %s '#{pane_pid}'", vim.trim(pane_id))
  )
  local pane_pid = tonumber(vim.trim(pane_pid_result))
  if not pane_pid then
    return nil
  end
  
  -- Find opencode child processes
  local pgrep = vim.system(
    { "pgrep", "-P", tostring(pane_pid), "-f", "opencode.*--port" },
    { text = true }
  ):wait()
  
  if pgrep.code ~= 0 or not pgrep.stdout or pgrep.stdout == "" then
    return nil
  end
  
  -- Get first opencode PID
  local opencode_pid = tonumber(vim.split(pgrep.stdout, "\n")[1])
  if not opencode_pid then
    return nil
  end
  
  -- Get port from lsof
  local lsof = vim.system(
    { "lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-a", "-p", tostring(opencode_pid) },
    { text = true }
  ):wait()
  
  if lsof.code ~= 0 or not lsof.stdout then
    return nil
  end
  
  -- Parse lsof output for port
  for line in lsof.stdout:gmatch("[^\r\n]+") do
    local parts = vim.split(line, "%s+")
    if parts[1] ~= "COMMAND" then
      local port_str = parts[9] and parts[9]:match(":(%d+)$")
      if port_str then
        return tonumber(port_str)
      end
    end
  end
  
  return nil
end

---Get the port of the server started by this provider
---@return number|nil port
function Tmux:get_port()
  return self.port
end

---Attach to (select/focus) the tmux pane for a given server
---@param server opencode.cli.server.Server
---@return boolean success Whether the pane was found and selected
function Tmux:attach_to_server(server)
  if not server or not server.pid then
    return false
  end
  
  -- Get TTY for the target process
  local tmux_util = require("opencode.provider.tmux_util")
  local target_tty = tmux_util.get_process_tty(server.pid)
  
  if not target_tty then
    -- No TTY - process might be detached or not in a pane
    return false
  end
  
  -- Find the pane with this TTY
  local result = vim.fn.system("tmux list-panes -a -F '#{pane_tty} #{pane_id}'")
  if vim.v.shell_error ~= 0 then
    return false
  end
  
  local target_pane_id = nil
  for line in result:gmatch("[^\r\n]+") do
    local pane_tty, pane_id = line:match("^(%S+)%s+(.+)$")
    if pane_tty and pane_tty == "/dev/" .. target_tty then
      target_pane_id = pane_id
      break
    end
  end
  
  if target_pane_id then
    -- Select the pane (this will focus it)
    vim.fn.system("tmux select-pane -t " .. target_pane_id)
    
    if vim.v.shell_error == 0 then
      -- Update our internal state
      self.pane_id = target_pane_id
      self.port = server.port
      vim.notify("Attached to OpenCode pane " .. target_pane_id, vim.log.levels.INFO, { title = "opencode" })
      return true
    end
  end
  
  -- Pane not found - server might be in a closed/detached pane, but that's okay
  return false
end

---Find an existing opencode pane in tmux
---Searches current window first (fast path), then all sessions (comprehensive search)
---@return string|nil pane_id
function Tmux:discover_existing_pane()
  -- First, search current window (fast path - better UX)
  local current_pane = self:_search_panes_for_opencode(false)
  if current_pane then
    return current_pane
  end
  
  -- Second, search all sessions (comprehensive search)
  return self:_search_panes_for_opencode(true)
end

---Search for panes running OpenCode
---@param all_sessions boolean If true, search all sessions; if false, search current window only
---@return string|nil pane_id
function Tmux:_search_panes_for_opencode(all_sessions)
  local list_cmd = all_sessions and "tmux list-panes -a" or "tmux list-panes"
  local result = vim.fn.system(list_cmd .. " -F '#{pane_id} #{pane_pid} #{pane_current_command}'")
  
  if vim.v.shell_error ~= 0 then
    return nil
  end
  
  -- Look for panes running opencode
  for line in result:gmatch("[^\r\n]+") do
    local pane_id, pane_pid, command = line:match("^(%S+)%s+(%d+)%s+(.+)$")
    if command and command:match("opencode") then
      local pane_pid_num = tonumber(pane_pid)
      if pane_pid_num then
        -- Case 1: OpenCode is the direct pane command (PID = pane PID)
        -- Check if this PID itself is an opencode process
        local ps_check = vim.system(
          { "ps", "-o", "command=", "-p", tostring(pane_pid_num) },
          { text = true }
        ):wait()
        
        if ps_check.code == 0 and ps_check.stdout and ps_check.stdout:match("opencode.*--port") then
          return pane_id
        end
        
        -- Case 2: OpenCode is a child of the pane shell
        -- Check for opencode children of the pane
        local pgrep = vim.system(
          { "pgrep", "-P", pane_pid, "-f", "opencode.*--port" },
          { text = true }
        ):wait()
        
        if pgrep.code == 0 and pgrep.stdout and pgrep.stdout ~= "" then
          return pane_id
        end
      end
    end
  end
  
  return nil
end

---Kill all orphaned opencode processes (processes whose panes no longer exist)
---
---This function finds OpenCode processes that are NOT in any visible tmux pane.
---Uses TTY-based detection to identify processes in closed/detached panes.
---These are typically processes left over from closed panes or previous Neovim sessions.
---
---**Platform Support:** This is a tmux-specific feature and only works on Unix-like
---systems with tmux installed. Not applicable on Windows.
---
---@return number count Number of processes killed
function Tmux:cleanup_orphaned_panes()
  local tmux_util = require("opencode.provider.tmux_util")
  local count = 0
  
  -- Get all opencode processes
  local pgrep = vim.system({ "pgrep", "-f", "opencode.*--port" }, { text = true }):wait()
  if pgrep.code ~= 0 or not pgrep.stdout or pgrep.stdout == "" then
    return count -- No opencode processes found
  end
  
  -- Kill orphaned processes (not in visible panes)
  for pid_str in pgrep.stdout:gmatch("[^\r\n]+") do
    local pid = tonumber(pid_str)
    if pid and not tmux_util.is_process_in_visible_pane(pid) then
      vim.fn.system("kill " .. pid)
      if vim.v.shell_error == 0 then
        count = count + 1
      end
    end
  end
  
  return count
end

return Tmux
