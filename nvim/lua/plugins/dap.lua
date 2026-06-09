return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'nvim-neotest/nvim-nio',
      'mfussenegger/nvim-dap-python',
      'theHamsta/nvim-dap-virtual-text',
      -- Install codelldb (C/C++/Rust debugger) via mason
      { 'jay-babu/mason-nvim-dap.nvim', dependencies = 'mason-org/mason.nvim' },
    },
    keys = {
      -- Stepping / control
      { '<leader>dc', function() require('dap').continue() end,      desc = 'Debug: Continue / Start' },
      { '<leader>ds', function() require('dap').step_over() end,     desc = 'Debug: Step Over' },
      { '<leader>di', function() require('dap').step_into() end,     desc = 'Debug: Step Into' },
      { '<leader>do', function() require('dap').step_out() end,      desc = 'Debug: Step Out' },
      { '<leader>dr', function() require('dap').repl.toggle() end,   desc = 'Debug: Toggle REPL' },
      { '<leader>dt', function() require('dap').terminate() end,     desc = 'Debug: Terminate' },
      { '<leader>dl', function() require('dap').run_last() end,      desc = 'Debug: Run Last' },
      { '<leader>du', function() require('dapui').toggle() end,      desc = 'Debug: Toggle UI' },
      { '<leader>b',  function() require('dap').toggle_breakpoint() end, desc = 'Debug: Toggle Breakpoint' },
      { '<leader>B',  function()
            vim.ui.input({ prompt = 'Breakpoint condition: ' }, function(cond)
              if cond then require('dap').set_breakpoint(cond) end
            end)
          end, desc = 'Debug: Conditional Breakpoint' },
      -- Fast non-leader
      { '<F9>',  function() require('dap').toggle_breakpoint() end, desc = 'Debug: Toggle Breakpoint' },
      { '<F10>', function() require('dap').step_over() end,         desc = 'Debug: Step Over' },
      { '<F11>', function() require('dap').step_into() end,         desc = 'Debug: Step Into' },
      { '<F12>', function() require('dap').step_out() end,          desc = 'Debug: Step Out' },
      -- Python launcher kept from before
      { '<leader>R', function()
          require('dap').run({
            type = 'python',
            request = 'launch',
            name = 'Launch file',
            program = '${file}',
            console = 'integratedTerminal',
            cwd = vim.fn.getcwd(),
          })
        end, desc = 'Debug: Run Python File' },
    },
    config = function()
      local dap = require('dap')
      local dapui = require('dapui')

      dapui.setup()
      require('nvim-dap-virtual-text').setup({ commented = true })

      -- mason-nvim-dap: auto-install codelldb (and cpptools as fallback)
      require('mason-nvim-dap').setup({
        ensure_installed = { 'codelldb' },
        automatic_installation = true,
        handlers = {
          function(config)
            require('mason-nvim-dap').default_setup(config)
          end,
        },
      })

      -- Python
      local ok, dap_python = pcall(require, 'dap-python')
      if ok then dap_python.setup('python') end

      ----------------------------------------------------------------------
      -- C / C++ via codelldb
      ----------------------------------------------------------------------
      local mason_path = vim.fn.stdpath('data') .. '/mason'
      local codelldb_path = mason_path .. '/packages/codelldb/extension/adapter/codelldb'

      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = codelldb_path,
          args = { '--port', '${port}' },
        },
      }

      -- Fallback adapter: gdb (works without codelldb; needs gdb >= 14)
      dap.adapters.gdb = {
        type = 'executable',
        command = 'gdb',
        args = { '--interpreter=dap', '--eval-command', 'set print pretty on' },
      }

      -- Pick the binary to debug. Cache per-cwd.
      local last_program = {}
      local function pick_program()
        local cwd = vim.fn.getcwd()
        local default = last_program[cwd] or (cwd .. '/')
        local path = vim.fn.input('Path to executable: ', default, 'file')
        if path and path ~= '' then last_program[cwd] = path end
        return path
      end

      local c_configs = {
        {
          name = 'codelldb: launch executable',
          type = 'codelldb',
          request = 'launch',
          program = pick_program,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = function()
            local s = vim.fn.input('argv: ', '')
            if s == '' then return {} end
            -- naive split on spaces
            local t = {}
            for w in s:gmatch('%S+') do table.insert(t, w) end
            return t
          end,
        },
        {
          name = 'gdb: launch executable',
          type = 'gdb',
          request = 'launch',
          program = pick_program,
          cwd = '${workspaceFolder}',
          stopAtBeginningOfMainSubprogram = false,
        },
      }

      dap.configurations.c = c_configs
      dap.configurations.cpp = c_configs

      -- Auto open/close dap-ui
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end

      -- Pretty signs
      vim.fn.sign_define('DapBreakpoint',          { text = '●', texthl = 'DiagnosticError' })
      vim.fn.sign_define('DapBreakpointCondition', { text = '◆', texthl = 'DiagnosticWarn' })
      vim.fn.sign_define('DapLogPoint',            { text = '◆', texthl = 'DiagnosticInfo' })
      vim.fn.sign_define('DapStopped',             { text = '▶', texthl = 'DiagnosticOk', linehl = 'Visual' })
    end,
  },
}
