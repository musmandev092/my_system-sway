local mason_tools = {

  "lua-language-server",
  "vtsls",
  "eslint-lsp",
  "pyright",
  "ruff",
  "gopls",
  "clangd",
  "bash-language-server",
  "json-lsp",
  "yaml-language-server",
  "taplo",
  "dockerfile-language-server",
  "marksman",
  "tailwindcss-language-server",
  "css-lsp",
  "html-lsp",

  "prettier",
  "black",
  "isort",
  "stylua",
  "shfmt",
  "goimports",
  "gofumpt",
  "clang-format",

  "shellcheck",
  "markdownlint-cli2",
  "hadolint",
}

return {
  { "folke/tokyonight.nvim", opts = { style = "night" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },

  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = mason_tools },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    cmd = { "MasonToolsInstall", "MasonToolsInstallSync", "MasonToolsUpdate", "MasonToolsUpdateSync" },
    event = "VeryLazy",
    opts = {
      ensure_installed = mason_tools,
      run_on_start = true,
      auto_update = false,
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        lua_ls = {},
        vtsls = {},
        eslint = {},
        pyright = {},
        ruff = {},
        gopls = {},
        clangd = {},
        bashls = {},
        jsonls = {},
        yamlls = {},
        taplo = {},
        dockerls = {},
        marksman = {},
        tailwindcss = {},
        cssls = {},
        html = {},
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        html = { "prettier" },
        markdown = { "prettier" },
        ["markdown.mdx"] = { "prettier" },
        yaml = { "prettier" },
        python = { "isort", "black" },
        lua = { "stylua" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        rust = { "rustfmt", lsp_format = "fallback" },
        go = { "goimports", "gofumpt" },
        c = { "clang-format" },
        cpp = { "clang-format" },
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash", "c", "cpp", "cmake", "css", "diff", "dockerfile", "go", "gomod", "gosum", "gowork",
        "git_config", "git_rebase", "gitattributes", "gitcommit", "gitignore", "html", "javascript",
        "jsdoc", "json", "jsonc", "lua", "luadoc", "luap", "make", "markdown", "markdown_inline",
        "ninja", "printf", "python", "query", "regex", "rst", "rust", "scss", "sql", "toml", "tsx",
        "typescript", "vim", "vimdoc", "xml", "yaml",
      },
    },
  },
}
