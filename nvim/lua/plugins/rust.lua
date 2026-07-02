-- Rust: rustaceanvim drives rust-analyzer (LSP, runnables, debuggables, macro
-- expansion, hover actions). The toolchain (rust-analyzer/rustfmt/clippy) comes
-- from rustup in ~/.cargo/bin, so nothing is installed via Mason here.
--
-- Do NOT set up rust_analyzer through lspconfig/mason-lspconfig as well —
-- rustaceanvim owns it, and running both attaches two clients.
return {
  {
    'mrcjkb/rustaceanvim',
    version = '^6',
    lazy = false, -- the plugin manages its own ftplugin loading
    ft = { 'rust' },
    init = function()
      -- Configure before the plugin's ftplugin runs.
      vim.g.rustaceanvim = {
        server = {
          -- nvim-cmp completion against rust-analyzer (matches the other servers).
          capabilities = require('cmp_nvim_lsp').default_capabilities(),
          default_settings = {
            ['rust-analyzer'] = {
              -- Clippy as the on-save linter.
              check = { command = 'clippy' },
              cargo = { allFeatures = true },
              procMacro = { enable = true },
              inlayHints = {
                bindingModeHints = { enable = false },
                closureReturnTypeHints = { enable = 'never' },
                lifetimeElisionHints = { enable = 'never', useParameterNames = false },
                parameterHints = { enable = true },
                typeHints = { enable = true },
              },
            },
          },
        },
        -- dap intentionally unset: rustaceanvim auto-detects the Mason codelldb
        -- already configured in dap.lua.
      }
    end,
  },
  {
    'saecki/crates.nvim',
    event = { 'BufRead Cargo.toml' },
    config = function()
      require('crates').setup {
        completion = {
          cmp = { enabled = true },
        },
      }
    end,
  },
}
