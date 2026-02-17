-- Agent sandbox default Neovim config.
-- Goal: modern defaults with lazy.nvim and widely used community plugins.

vim.g.mapleader = " "
vim.g.maplocalleader = ","

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.mouse = "a"
opt.termguicolors = true
opt.signcolumn = "yes"
opt.splitbelow = true
opt.splitright = true
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true
opt.smartindent = true
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = "menu,menuone,noinsert,noselect"

if vim.fn.has("clipboard") == 1 then
  opt.clipboard = "unnamedplus"
end

local undo_dir = vim.fn.stdpath("data") .. "/undo"
if vim.fn.isdirectory(undo_dir) == 0 then
  vim.fn.mkdir(undo_dir, "p")
end
opt.undofile = true
opt.undodir = undo_dir

vim.keymap.set("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", { desc = "Explorer" })
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Find buffers" })

if vim.fn.has("nvim-0.8") == 0 then
  vim.schedule(function()
    vim.notify(
      "This config enables lazy.nvim plugins on Neovim >= 0.8. Please upgrade Neovim for full feature set.",
      vim.log.levels.WARN
    )
  end)
  return
end

local fs = vim.uv or vim.loop
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not fs.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
    }, true, {})
    return
  end
end
opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Trendy themes.
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
  { "folke/tokyonight.nvim", priority = 1000 },
  { "rebelot/kanagawa.nvim", priority = 1000 },
  { "rose-pine/neovim", name = "rose-pine", priority = 1000 },

  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        section_separators = "",
        component_separators = "",
      },
    },
  },

  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },
  { "lewis6991/gitsigns.nvim", event = { "BufReadPre", "BufNewFile" }, opts = {} },
  { "numToStr/Comment.nvim", event = "VeryLazy", opts = {} },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFocus" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      hijack_cursor = true,
      update_focused_file = { enable = true },
      view = { width = 34 },
      renderer = { root_folder_label = false },
      filters = { dotfiles = false },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    cmd = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "bash", "json", "lua", "markdown", "python", "toml", "vim", "yaml" },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts_)
      -- Upstream moved setup entrypoint from `nvim-treesitter.configs` to
      -- `nvim-treesitter`. Keep a legacy fallback for older plugin snapshots.
      local ok_new, ts = pcall(require, "nvim-treesitter")
      if ok_new and type(ts.setup) == "function" then
        ts.setup(opts_)
        return
      end

      local ok_legacy, ts_legacy = pcall(require, "nvim-treesitter.configs")
      if ok_legacy and type(ts_legacy.setup) == "function" then
        ts_legacy.setup(opts_)
        return
      end

      vim.schedule(function()
        vim.notify("nvim-treesitter setup module not found. Run :Lazy sync", vim.log.levels.WARN)
      end)
    end,
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "williamboman/mason.nvim", config = true },
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" },
        automatic_installation = true,
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      local servers = { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" }

      -- Prefer Nvim 0.11+ API to avoid deprecated `require("lspconfig")`.
      if vim.lsp and vim.lsp.config and vim.lsp.enable then
        for _, server in ipairs(servers) do
          vim.lsp.config(server, { capabilities = capabilities })
          vim.lsp.enable(server)
        end
      else
        local lspconfig = require("lspconfig")
        for _, server in ipairs(servers) do
          lspconfig[server].setup({ capabilities = capabilities })
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local opts_ = { buffer = event.buf, silent = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts_)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts_)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts_)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts_)
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts_)
        end,
      })
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
          { name = "buffer" },
        }),
      })
    end,
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local disable_lsp_fallback = { c = true, cpp = true }
        return {
          timeout_ms = 500,
          lsp_format = disable_lsp_fallback[vim.bo[bufnr].filetype] and "never" or "fallback",
        }
      end,
      formatters_by_ft = {
        lua = { "stylua" },
        javascript = { "prettierd", "prettier" },
        typescript = { "prettierd", "prettier" },
        json = { "prettierd", "prettier" },
        yaml = { "prettierd", "prettier" },
        sh = { "shfmt" },
        python = { "ruff_format", "black" },
      },
    },
  },
}, {
  change_detection = { notify = false },
})

local schemes = {
  "tokyonight-night",
  "catppuccin-mocha",
  "kanagawa-wave",
  "rose-pine-main",
}

for _, scheme in ipairs(schemes) do
  if pcall(vim.cmd.colorscheme, scheme) then
    break
  end
end
