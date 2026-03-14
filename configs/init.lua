-- luacheck: globals vim
-- ============================================================
-- Neovim configuration — VS Code dark theme + AI assistant
-- ============================================================

-- --- Visual ---
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.showmode = true
vim.opt.showcmd = true
vim.opt.title = true

-- --- Indentation ---
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.smartindent = true
vim.opt.shiftround = true

-- --- Search ---
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- --- Navigation ---
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.splitright = true
vim.opt.splitbelow = true

-- --- Performance ---
vim.opt.lazyredraw = true
vim.opt.updatetime = 250

-- --- Temp directories ---
vim.fn.mkdir("/tmp/nvim-undo", "p")
vim.fn.mkdir("/tmp/nvim-backup", "p")
vim.fn.mkdir("/tmp/nvim-swap", "p")

-- --- Files ---
vim.opt.undofile = true
vim.opt.undodir = "/tmp/nvim-undo//"
vim.opt.backup = true
vim.opt.backupdir = "/tmp/nvim-backup//"
vim.opt.directory = "/tmp/nvim-swap//"
vim.opt.autoread = true

-- --- Editing ---
vim.opt.backspace = "indent,eol,start"
vim.opt.wildmenu = true
vim.opt.wildmode = "longest:full,full"
vim.opt.showmatch = true
vim.opt.matchtime = 2
vim.opt.joinspaces = false
vim.opt.formatoptions:append("j")
vim.opt.hidden = true
vim.opt.confirm = true

-- --- Neovim-specific ---
vim.opt.inccommand = "split"

-- --- Keymaps ---
-- Clear search highlight with Escape
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
-- Keep selection when indenting in visual mode
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- ============================================================
-- Bootstrap avante OAuth from env var
-- ============================================================
local oauth_token = vim.env.CLAUDE_CODE_OAUTH_TOKEN
if oauth_token and oauth_token ~= "" then
  local avante_data = vim.fn.stdpath("data") .. "/avante"
  vim.fn.mkdir(avante_data, "p")
  local auth_file = avante_data .. "/claude-auth.json"
  local token_json = vim.json.encode({
    access_token = oauth_token,
    refresh_token = oauth_token,
    expires_at = os.time() + 3600,
  })
  local f = io.open(auth_file, "w")
  if f then
    f:write(token_json)
    f:close()
    local uv = vim.uv or vim.loop
    uv.fs_chmod(auth_file, 384) -- 0600
  end
end

-- ============================================================
-- Plugin manager: lazy.nvim
-- ============================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- VS Code Dark+ theme
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("vscode").setup({
        italic_comments = true,
        underline_links = true,
        terminal_colors = true,
      })
      vim.cmd.colorscheme("vscode")
    end,
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "vscode",
          section_separators = "",
          component_separators = "",
        },
      })
    end,
  },

  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    opts = {},
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-p>"] = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = "avante" },
        }),
      })
    end,
  },

  -- AI assistant (Cursor-like)
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    build = "make",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "MeanderingProgrammer/render-markdown.nvim",
      "nvim-tree/nvim-web-devicons",
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = { insert_mode = true },
            use_absolute_path = true,
          },
        },
      },
    },
    opts = {
      provider = "claude",
      file_selector = {
        provider = "telescope",
      },
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com",
          model = "claude-sonnet-4-20250514",
          auth_type = "max",
          timeout = 30000,
          extra_request_body = {
            temperature = 0.75,
            max_tokens = 20480,
          },
        },
      },
    },
  },
})
