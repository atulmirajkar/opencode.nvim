---Minimal init for running tests
---This file sets up the minimum configuration needed to load opencode.nvim for testing

-- Add current directory to runtimepath so we can load the plugin
vim.opt.runtimepath:append(".")

-- Add snacks.nvim if available (required dependency)
local snacks_path = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
if vim.fn.isdirectory(snacks_path) == 1 then
  vim.opt.runtimepath:append(snacks_path)
end

-- Suppress notifications during tests (less noisy output)
vim.notify = function(msg, level, opts)
  -- Silent during tests unless explicitly enabled
  if vim.env.VERBOSE_TESTS then
    print(string.format("[%s] %s", level or "INFO", msg))
  end
end

-- Set up basic vim options
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
