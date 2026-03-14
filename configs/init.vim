" ============================================================
" Neovim configuration — VS Code dark theme
" ============================================================

" --- Visual ---
set termguicolors
set background=dark
set nonumber
set norelativenumber
set cursorline
set signcolumn=yes
set showmode
set showcmd
set title

" --- Indentation ---
set expandtab
set tabstop=2
set shiftwidth=2
set softtabstop=2
set smartindent
set shiftround

" --- Search ---
set ignorecase
set smartcase
set incsearch
set hlsearch

" --- Navigation ---
set scrolloff=8
set sidescrolloff=8
set splitright
set splitbelow

" --- Performance ---
set lazyredraw
set updatetime=250

" --- Temp directories ---
silent! call mkdir('/tmp/nvim-undo', 'p')
silent! call mkdir('/tmp/nvim-backup', 'p')
silent! call mkdir('/tmp/nvim-swap', 'p')

" --- Files ---
set undofile
set undodir=/tmp/nvim-undo//
set backup
set backupdir=/tmp/nvim-backup//
set directory=/tmp/nvim-swap//
set autoread

" --- Editing ---
set backspace=indent,eol,start
set wildmenu
set wildmode=longest:full,full
set showmatch
set matchtime=2
set nojoinspaces
set formatoptions+=j
set hidden
set confirm

" --- Neovim-specific ---
set inccommand=split

" --- Statusline ---
set laststatus=2

" --- Keymaps ---
" Clear search highlight with Escape
nnoremap <Esc> :nohlsearch<CR>
" Keep selection when indenting in visual mode
vnoremap < <gv
vnoremap > >gv

" --- Plugins (Lua) ---
lua << EOF
require('vscode').setup({
  italic_comments = true,
  underline_links = true,
  terminal_colors = true,
})
vim.cmd.colorscheme "vscode"

require('lualine').setup({
  options = {
    theme = 'vscode',
    section_separators = '',
    component_separators = '',
  },
})
EOF
