-- Minimal test configuration for opencode.nvim with tmux provider
-- Run with: nvim -u test_config.lua

-- Set up package path for local testing
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Configure opencode.nvim
require("lazy").setup({
  {
    dir = vim.fn.getcwd(), -- Use current directory
    dependencies = {
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        provider = {
          enabled = "tmux",
          tmux = {
            options = "-h",  -- horizontal split
            focus = false,   -- keep focus in nvim
          }
        }
      }

      vim.o.autoread = true

      -- Test keymaps
      vim.keymap.set({ "n", "t" }, "<C-.>", function() 
        require("opencode").toggle() 
      end, { desc = "Toggle opencode" })
      
      vim.keymap.set({ "n", "x" }, "<C-a>", function() 
        require("opencode").ask("@this: ", { submit = true }) 
      end, { desc = "Ask opencode…" })

      print("\n✓ opencode.nvim loaded with tmux provider")
      print("✓ Press <C-.> to toggle opencode")
      print("✓ Press <C-a> to ask opencode")
      print("\nRun :checkhealth opencode to verify setup\n")
    end,
  }
})

-- Set up some basic options for testing
vim.opt.number = true
vim.opt.signcolumn = "yes"
