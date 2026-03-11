" ============================================================
" Neovim configuration — built-in only (no plugin manager)
" Complements the p10k rainbow prompt theme with 'industry'
" ============================================================

" --- Visual ---
set termguicolors
set background=dark
colorscheme industry
set nonumber
set norelativenumber
set cursorline
set signcolumn=yes
set colorcolumn=120
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
set mouse=a
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
set clipboard=unnamedplus
set inccommand=split

" --- Statusline ---
set laststatus=2
set statusline=
set statusline+=%#PmenuSel#
set statusline+=\ %{toupper(mode())}\
set statusline+=%#LineNr#
set statusline+=\ %f
set statusline+=%m
set statusline+=%=
set statusline+=\ %y
set statusline+=\ %l:%c
set statusline+=\ %p%%\

" --- Keymaps ---
" Clear search highlight with Escape
nnoremap <Esc> :nohlsearch<CR>
" Keep selection when indenting in visual mode
vnoremap < <gv
vnoremap > >gv
