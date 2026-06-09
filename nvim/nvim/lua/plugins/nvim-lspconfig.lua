return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      -- Keymaps when LSP attaches
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('grn', vim.lsp.buf.rename, 'Rename')
          map('gra', vim.lsp.buf.code_action, 'Code Action', { 'n', 'x' })
          map('grr', require('telescope.builtin').lsp_references, 'References')
          map('gri', require('telescope.builtin').lsp_implementations, 'Implementation')
          map('grd', require('telescope.builtin').lsp_definitions, 'Definition')
          map('grD', vim.lsp.buf.declaration, 'Declaration')
          map('gO', require('telescope.builtin').lsp_document_symbols, 'Document Symbols')
          map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Workspace Symbols')
          map('grt', require('telescope.builtin').lsp_type_definitions, 'Type Definition')
          map('K', function()
            vim.lsp.buf.hover { border = 'rounded' }
          end, 'Hover Documentation')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          -- Attach nvim-navic for winbar breadcrumbs
          if client and client.server_capabilities.documentSymbolProvider then
            require('nvim-navic').attach(client, event.buf)
          end

          local function supports(method)
            return client
              and (vim.fn.has 'nvim-0.11' == 1 and client:supports_method(method, event.buf) or client.supports_method(method, { bufnr = event.buf }))
          end

          -- Highlight references
          if supports(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local hl = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = hl,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = hl,
              callback = vim.lsp.buf.clear_references,
            })
            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
              callback = function(e)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = e.buf }
              end,
            })
          end

          -- Toggle inlay hints
          if supports(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, 'Toggle Inlay Hints')
          end
        end,
      })

      -- LSP hover and signature help with borders
      vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, {
        border = 'rounded',
      })
      vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, {
        border = 'rounded',
      })

      -- Diagnostics
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
        virtual_text = { source = 'if_many', spacing = 2 },
      }

      -- Capabilities (for nvim-cmp)
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      -- Servers
      local servers = {
        clangd = {
          cmd = { 'clangd', '--background-index', '--clang-tidy' },
          filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
        },
        pyright = {
          filetypes = { 'python' },
          settings = {
            python = {
              analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly',
              },
            },
          },
        },
        lua_ls = {
          settings = {
            Lua = {
              completion = { callSnippet = 'Replace' },
              -- diagnostics = { disable = { "missing-fields" } },
            },
          },
        },
        -- Hardware development LSPs
        rust_hdl = {
          filetypes = { 'vhdl', 'verilog', 'systemverilog' },
        },
        verible = {
          filetypes = { 'verilog', 'systemverilog' },
        },
      }

      -- Install servers & tools
      -- Filter out hardware LSPs that may not be available in Mason
      local mason_servers = {}
      for server_name, _ in pairs(servers) do
        if server_name ~= 'rust_hdl' and server_name ~= 'verible' then
          table.insert(mason_servers, server_name)
        end
      end
      local ensure_installed = mason_servers
      vim.list_extend(ensure_installed, { 'stylua', 'clangd', 'pyright' })
      -- Note: rust_hdl, verible, and vsg need manual installation:
      -- rust_hdl: Install via cargo: cargo install rust_hdl
      -- verible: Download from https://github.com/chipsalliance/verible/releases or install via package manager
      -- vsg: Install via pip: pip install vsg
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      -- Setup servers
      require('mason-lspconfig').setup {
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
          -- Custom handler for pyright to detect venv
          pyright = function()
            -- Helper function to log to a debug file
            local function log_debug(msg)
              local log_file = vim.fn.stdpath('state') .. '/pyright-venv-debug.log'
              local timestamp = os.date('%Y-%m-%d %H:%M:%S')
              local log_line = string.format('[%s] %s\n', timestamp, msg)
              local file = io.open(log_file, 'a')
              if file then
                file:write(log_line)
                file:close()
              else
                -- Fallback: try to create directory if it doesn't exist
                vim.fn.mkdir(vim.fn.stdpath('state'), 'p')
                file = io.open(log_file, 'a')
                if file then
                  file:write(log_line)
                  file:close()
                end
              end
            end

            log_debug('=== Pyright handler called ===')
            
            local server = servers.pyright or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})

            log_debug('Setting up on_new_config callback')

            -- Helper function to check if a file exists in a directory
            local function dir_has_file(dir, filename)
              local filepath = dir .. '/' .. filename
              return vim.fn.filereadable(filepath) == 1
            end

            -- Detect venv and set pythonPath in on_new_config
            server.on_new_config = function(new_config, root_dir)
              local ok, err = pcall(function()
                log_debug('=== Pyright venv detection started ===')
                log_debug('Root directory: ' .. tostring(root_dir))
              
              if dir_has_file(root_dir, 'poetry.lock') then
                log_debug('Found poetry.lock, using poetry')
                vim.notify_once 'Running `pyright` with `poetry`'
                new_config.cmd = { 'poetry', 'run', 'pyright-langserver', '--stdio' }
              elseif dir_has_file(root_dir, 'Pipfile') then
                log_debug('Found Pipfile, using pipenv')
                vim.notify_once 'Running `pyright` with `pipenv`'
                new_config.cmd = { 'pipenv', 'run', 'pyright-langserver', '--stdio' }
              else
                log_debug('No poetry.lock or Pipfile found, checking for venv directories')
                -- Auto-detect venv in project root (check common venv directory names)
                local venv_names = { '.venv', 'venv', 'env', '.env' }
                local venv_found = false
                
                for _, venv_name in ipairs(venv_names) do
                  local venv_path = root_dir .. '/' .. venv_name
                  local python_path = venv_path .. '/bin/python'
                  
                  log_debug('Checking venv: ' .. venv_name)
                  log_debug('  venv_path: ' .. venv_path)
                  log_debug('  python_path: ' .. python_path)
                  
                  local is_dir = vim.fn.isdirectory(venv_path)
                  local is_executable = vim.fn.executable(python_path)
                  
                  log_debug('  isdirectory(' .. venv_path .. '): ' .. tostring(is_dir))
                  log_debug('  executable(' .. python_path .. '): ' .. tostring(is_executable))
                  
                  if is_dir == 1 and is_executable == 1 then
                    log_debug('  ✓ Venv found and python executable exists!')
                    new_config.settings = new_config.settings or {}
                    new_config.settings.python = new_config.settings.python or {}
                    -- Use both pythonPath (older) and defaultInterpreterPath (newer) for compatibility
                    new_config.settings.python.pythonPath = python_path
                    new_config.settings.python.defaultInterpreterPath = python_path
                    new_config.settings.python.venvPath = root_dir
                    new_config.settings.python.venv = venv_name
                    log_debug('  Set pythonPath to: ' .. python_path)
                    log_debug('  Set venvPath to: ' .. root_dir)
                    log_debug('  Set venv to: ' .. venv_name)
                    vim.notify('Pyright: Using venv at ' .. venv_path .. ' (pythonPath: ' .. python_path .. ')', vim.log.levels.INFO)
                    venv_found = true
                    break
                  else
                    log_debug('  ✗ Venv check failed')
                  end
                end
                
                if not venv_found then
                  log_debug('No venv found in any of the checked directories')
                end
              end
              
              log_debug('=== Pyright venv detection finished ===\n')
              end) -- end pcall
              
              if not ok then
                log_debug('ERROR in on_new_config: ' .. tostring(err))
                vim.notify('Pyright venv detection error: ' .. tostring(err), vim.log.levels.ERROR)
              end
            end

            log_debug('Calling lspconfig.pyright.setup()')
            require('lspconfig').pyright.setup(server)
            log_debug('Pyright setup complete\n')
          end,
          -- Disable pylsp since we use pyright for Python
          pylsp = function() end,
        },
      }
    end,
  },
}
