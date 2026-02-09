local M = {}

---An `opencode` server process and some details about it.
---@class opencode.cli.server.Server
---@field port number
---@field cwd string
---@field title string
---@field pid number

---An `opencode` process.
---Retrieval is platform-dependent.
---@class opencode.cli.server.Process
---@field pid number
---@field port number

---@return boolean
local function is_windows()
  return vim.fn.has("win32") == 1
end

---@return opencode.cli.server.Process[]
local function get_processes_unix()
  -- Find PIDs by command line pattern.
  -- We filter for `--port` to avoid matching other `opencode`-related processes (LSPs etc.)
  local pgrep = vim.system({ "pgrep", "-f", "opencode.*--port" }, { text = true }):wait()
  require("opencode.util").check_system_call(pgrep, "pgrep")

  local processes = {}
  for pgrep_line in pgrep.stdout:gmatch("[^\r\n]+") do
    local pid = tonumber(pgrep_line)
    if pid then
      -- Get the port for the PID
      local lsof = vim
        .system({ "lsof", "-w", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-a", "-p", tostring(pid) }, { text = true })
        :wait()
      require("opencode.util").check_system_call(lsof, "lsof")
      for line in lsof.stdout:gmatch("[^\r\n]+") do
        local parts = vim.split(line, "%s+")
        if parts[1] ~= "COMMAND" then -- Skip header
          local port_str = parts[9] and parts[9]:match(":(%d+)$") -- e.g. "127.0.0.1:12345" -> "12345"
          if port_str then
            local port = tonumber(port_str)
            if port then
              table.insert(processes, {
                pid = pid,
                port = port,
              })
            end
          end
        end
      end
    end
  end
  return processes
end

---@return opencode.cli.server.Process[]
local function get_processes_windows()
  local ps_script = [[
Get-Process -Name '*opencode*' -ErrorAction SilentlyContinue |
ForEach-Object {
  $ports = Get-NetTCPConnection -State Listen -OwningProcess $_.Id -ErrorAction SilentlyContinue
  if ($ports) {
    foreach ($port in $ports) {
      [PSCustomObject]@{pid=$_.Id; port=$port.LocalPort}
    }
  }
} | ConvertTo-Json -Compress
]]
  local ps = vim.system({ "powershell", "-NoProfile", "-Command", ps_script }):wait()
  require("opencode.util").check_system_call(ps, "PowerShell")
  if ps.stdout == "" then
    return {}
  end
  -- The Powershell script should return the response as JSON to ease parsing.
  local ok, processes = pcall(vim.fn.json_decode, ps.stdout)
  if not ok then
    error("Failed to parse PowerShell output: " .. tostring(processes), 0)
  end
  if processes.pid then
    -- A single process was found, so wrap it in a table.
    processes = { processes }
  end
  return processes
end

---@param port number
---@param pid number
---@return Promise<opencode.cli.server.Server>
local function get_server(port, pid)
  local Promise = require("opencode.promise")
  return Promise
    .new(function(resolve, reject)
      require("opencode.cli.client").get_path(port, function(path)
        local cwd = path.directory or path.worktree
        if cwd then
          resolve(cwd)
        else
          reject("No `opencode` responding on port: " .. port)
        end
      end, function()
        reject("No `opencode` responding on port: " .. port)
      end)
    end)
    -- Serial instead of parallel so that `get_path` has verified it's a server
    :next(
      function(cwd) ---@param cwd string
        return Promise.new(function(resolve)
          require("opencode.cli.client").get_sessions(port, function(session)
            -- This will be the most recently interacted session.
            -- Unfortunately `opencode` doesn't provide a way to get the currently selected TUI session.
            -- But they will probably have interacted with the session they want to connect to most recently.
            local title = session[1] and session[1].title or "<No sessions>"
            resolve({ cwd, title })
          end)
        end)
      end
    )
    :next(function(results) ---@param results { [1]: string, [2]: string }
      local cwd = results[1]
      local title = results[2]
      return {
        port = port,
        cwd = cwd,
        title = title,
        pid = pid,
      }
    end)
end

---@return Promise<opencode.cli.server.Server[]>
local function get_all_servers()
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    local processes
    if is_windows() then
      processes = get_processes_windows()
    else
      processes = get_processes_unix()
    end
    if #processes == 0 then
      reject("No `opencode` processes found")
    else
      resolve(processes)
    end
  end):next(function(processes) ---@param processes opencode.cli.server.Process[]
    local get_servers = vim.tbl_map(function(process) ---@param process opencode.cli.server.Process
      return get_server(process.port, process.pid)
    end, processes)
    return Promise.all_settled(get_servers):next(function(results)
      local servers = {}
      for _, result in ipairs(results) do
        -- We expect non-servers to reject
        if result.status == "fulfilled" then
          table.insert(servers, result.value)
        end
      end
      if #servers == 0 then
        error("No `opencode` servers found", 0)
      end
      return servers
    end)
  end)
end

---Check if a server is in a visible tmux pane (not orphaned)
---
---Uses TTY-based detection to determine if an OpenCode process is running
---in a visible tmux pane. Processes without a TTY or with a TTY not matching
---any visible pane are considered orphaned.
---
---**Windows Compatibility:** This is a tmux-specific feature. On Windows,
---this always returns true since tmux is not available, meaning all processes
---will be considered visible (no orphan filtering).
---
---@param server opencode.cli.server.Server
---@return boolean is_visible True if server is in a visible pane (or on Windows)
local function is_in_visible_pane(server)
  if is_windows() then
    return true -- Orphan detection is tmux-only; assume all visible on Windows
  end
  
  if not server.pid then
    return false
  end
  
  local tmux_util = require("opencode.provider.tmux_util")
  return tmux_util.is_process_in_visible_pane(server.pid)
end

---@return Promise<opencode.cli.server.Server[]>
local function get_all_servers_in_nvim_cwd()
  return get_all_servers():next(function(servers) ---@param servers opencode.cli.server.Server[]
    local cwd_matching_servers = {}
    local nvim_cwd = vim.fn.getcwd()
    for _, server in ipairs(servers) do
      -- Filter for servers in the same CWD as Neovim
      local normalized_server_cwd = server.cwd
      local normalized_nvim_cwd = nvim_cwd
      if is_windows() then
        -- On Windows, normalize to backslashes for consistent comparison
        normalized_server_cwd = server.cwd:gsub("/", "\\")
        normalized_nvim_cwd = nvim_cwd:gsub("/", "\\")
      end
      if normalized_nvim_cwd == normalized_server_cwd then
        table.insert(cwd_matching_servers, server)
      end
    end
    
    -- Filter out orphaned servers (not in visible panes)
    -- Only show servers that can actually be attached to
    local visible_servers = {}
    for _, server in ipairs(cwd_matching_servers) do
      if is_in_visible_pane(server) then
        table.insert(visible_servers, server)
      end
    end
    
    if #visible_servers == 0 then
      error("No `opencode` servers found in visible panes in CWD: " .. nvim_cwd, 0)
    end
    return visible_servers
  end)
end

---Find PID for a given port by searching all opencode processes
---@param port number
---@return number|nil pid
local function find_pid_for_port(port)
  local processes
  if is_windows() then
    processes = get_processes_windows()
  else
    processes = get_processes_unix()
  end
  
  for _, process in ipairs(processes) do
    if process.port == port then
      return process.pid
    end
  end
  
  return nil
end

---@return Promise<opencode.cli.server.Server>
local function get_configured_server()
  local configured_port = require("opencode.config").opts.port
  if configured_port then
    local pid = find_pid_for_port(configured_port)
    if pid then
      return get_server(configured_port, pid)
    else
      return require("opencode.promise").reject("No process found for configured port: " .. configured_port)
    end
  else
    return require("opencode.promise").reject("No configured port for `opencode` server")
  end
end

---@return Promise<opencode.cli.server.Server>
local function get_connected_server()
  local connected_server = require("opencode.events").connected_server
  if connected_server then
    -- connected_server already has pid, just return it wrapped in a promise
    return require("opencode.promise").resolve(connected_server)
  else
    return require("opencode.promise").reject("No currently subscribed `opencode` server")
  end
end

---Attempt to get the `opencode` server's port. Tries, in order:
---
---1. The currently subscribed server in `opencode.events`.
---2. The configured port in `require("opencode.config").opts.port`.
---3. Any server in Neovim's CWD, prompting the user to select if multiple are found.
---4. Auto-start a new server if none exist and provider supports it, or show an error.
---
---Upon success, subscribes to the server's events.
---
---@param launch boolean? Whether to launch a new server if none found. Defaults to true.
---@param auto_start boolean? Whether to auto-start without showing picker when no servers exist. Defaults to false.
---@return Promise<opencode.cli.server.Server>
function M.get(launch, auto_start)
  launch = launch ~= false
  auto_start = auto_start or false

  local Promise = require("opencode.promise")
  return get_connected_server()
    :catch(get_configured_server)
    :catch(function(err)
      -- Check if any servers exist in CWD
      return get_all_servers_in_nvim_cwd()
        :catch(function(no_servers_err)
          -- No visible servers found in CWD
          -- This means either no servers exist, or they're all orphaned
          if auto_start and launch and require("opencode.provider").can_auto_start() then
            -- Kill any orphaned processes before starting fresh
            local provider = require("opencode.provider")
            local config_provider = require("opencode.config").provider
            if config_provider and config_provider.cleanup_orphaned_panes then
              local killed = config_provider:cleanup_orphaned_panes()
              if killed > 0 then
                vim.notify("Cleaned up " .. killed .. " orphaned OpenCode process(es)", 
                           vim.log.levels.INFO, { title = "opencode" })
              end
            end
            
            -- Auto-start provider without showing picker
            vim.notify("Starting OpenCode server...", vim.log.levels.INFO, { title = "opencode" })
            return Promise.new(function(resolve, reject)
              local start_ok, start_result = pcall(provider.start)
              if not start_ok then
                return reject("Error starting `opencode`: " .. start_result)
              end

              -- Wait for the provider to start
              vim.defer_fn(function()
                resolve(true)
              end, 2000)
            end):next(function()
              -- After auto-start, directly get the server (should be only one)
              -- Use select with auto_select_if_one=true to avoid showing picker
              return get_all_servers_in_nvim_cwd():next(function(servers)
                if #servers == 1 then
                  return servers[1]
                else
                  -- Multiple servers found, show picker
                  return M.select()
                end
              end)
            end)
          else
            -- Can't auto-start or auto_start disabled, propagate the error
            return Promise.reject(no_servers_err)
          end
        end)
        :next(function(servers)
          -- Servers exist in CWD - show picker
          return M.select()
        end)
    end)
    :catch(function(err)
      if not err then
        -- User cancelled the selection
        return Promise.reject()
      end

      -- Final fallback: try manual launch if enabled and not already tried
      if launch and not auto_start then
        return Promise.new(function(resolve, reject)
          local start_ok, start_result = pcall(require("opencode.provider").start)
          if not start_ok then
            return reject("Error starting `opencode`: " .. start_result)
          end

          -- Wait for the provider to start
          vim.defer_fn(function()
            resolve(true)
          end, 2000)
        end):next(function()
          -- Retry
          return M.get(false, false)
        end)
      else
        -- Propagate the error
        return Promise.reject(err)
      end
    end)
    :next(function(server) ---@param server opencode.cli.server.Server
      require("opencode.events").connect(server)
      
      -- If auto_start is enabled (called from ask/prompt), attach to the pane
      if auto_start then
        require("opencode.provider").attach_to_connected_server()
      end
      
      return server
    end)
end

---Get the tmux pane ID for a given process ID
---@param pid number
---@return string|nil pane_id The tmux pane ID (e.g., "%20") or nil if not found
local function get_tmux_pane_for_pid(pid)
  if is_windows() then
    return nil -- tmux is not available on Windows
  end
  
  -- First, check if the PID is directly a tmux pane's PID
  local result = vim.system({ "tmux", "list-panes", "-a", "-F", "#{pane_pid} #{pane_id}" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    for line in result.stdout:gmatch("[^\r\n]+") do
      local pane_pid_str, pane_id = line:match("^(%d+)%s+(.+)$")
      if pane_pid_str and tonumber(pane_pid_str) == pid then
        return pane_id
      end
    end
  end
  
  -- If not found, check if the PID is a child of a pane's shell
  -- Get the parent PID
  local ps_result = vim.system({ "ps", "-o", "ppid=", "-p", tostring(pid) }, { text = true }):wait()
  if ps_result.code == 0 and ps_result.stdout then
    local ppid = tonumber(ps_result.stdout:match("^%s*(%d+)"))
    if ppid then
      -- Check if the parent is a tmux pane
      local result2 = vim.system({ "tmux", "list-panes", "-a", "-F", "#{pane_pid} #{pane_id}" }, { text = true }):wait()
      if result2.code == 0 and result2.stdout then
        for line in result2.stdout:gmatch("[^\r\n]+") do
          local pane_pid_str, pane_id = line:match("^(%d+)%s+(.+)$")
          if pane_pid_str and tonumber(pane_pid_str) == ppid then
            return pane_id
          end
        end
      end
    end
  end
  
  return nil
end

---Check if a server is the one started by the current provider
---@param server opencode.cli.server.Server
---@return boolean
local function is_provider_server(server)
  local provider = require("opencode.config").provider
  if not provider then
    return false
  end
  
  -- Check if provider has a get_port method (e.g., tmux provider)
  if type(provider.get_port) == "function" then
    local provider_port = provider:get_port()
    if provider_port and provider_port == server.port then
      return true
    end
  end
  
  return false
end

---Check if a server is currently connected
---@param server opencode.cli.server.Server
---@return boolean
local function is_connected_server(server)
  local connected_server = require("opencode.events").connected_server
  if connected_server and connected_server.port == server.port then
    return true
  end
  return false
end

---@param auto_select_if_one boolean?
---@return Promise<opencode.cli.server.Server>
function M.select(auto_select_if_one)
  local Promise = require("opencode.promise")
  return get_all_servers_in_nvim_cwd():next(function(servers) ---@param servers opencode.cli.server.Server[]
    if auto_select_if_one and #servers == 1 then
      -- TODO: Is this the best composition?
      -- Between its use here and in the ui module.
      return servers[1]
    end

    local picker_opts = {
      prompt = "Select an `opencode` server:",
      format_item = function(server) ---@param server opencode.cli.server.Server
        -- Connection indicator - shows which server we're currently connected to
        local connection_marker = is_connected_server(server) and "→ " or "  "
        
        -- Star marker for provider-started servers
        local marker = is_provider_server(server) and "★" or " "
        
        -- Tmux pane indicator
        local pane_info = ""
        if server.pid then
          local pane_id = get_tmux_pane_for_pid(server.pid)
          if pane_id then
            pane_info = string.format("[Tmux %-4s] ", pane_id)
          else
            pane_info = "[Unknown]   "
          end
        else
          pane_info = "[Unknown]   "
        end
        
        -- Session title with fixed width
        local title = server.title or "<No sessions>"
        
        -- Shortened CWD with ~/ for home directory
        local short_cwd = vim.fn.fnamemodify(server.cwd, ":~")
        
        return string.format(
          "%s%s %s%-20s | Port %-5d | %s",
          connection_marker,
          marker,
          pane_info,
          title,
          server.port,
          short_cwd
        )
      end,
      snacks = {
        layout = {
          hidden = { "preview" },
        },
      },
    }
    picker_opts = vim.tbl_deep_extend("keep", picker_opts, require("opencode.config").opts.select or {})

    return Promise.select(servers, picker_opts)
  end)
end

return M
