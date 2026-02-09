local M = {}

function M.select_server()
  return require("opencode.cli.server")
    .select()
    :next(function(server)
      require("opencode.events").connect(server)
      return server
    end)
    :catch(function(err)
      if err then
        vim.notify("Failed to select an `opencode` server: " .. tostring(err), vim.log.levels.WARN)
      end
      -- If err is nil, user cancelled - do nothing
    end)
end

return M
