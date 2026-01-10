return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'nvim-neotest/nvim-nio',
      'mfussenegger/nvim-dap-python',
    },
    keys = {
      { '<leader>dc', function() require('dap').continue() end, desc = 'Debug: Continue' },
      { '<leader>ds', function() require('dap').step_over() end, desc = 'Debug: Step Over' },
      { '<leader>di', function() require('dap').step_into() end, desc = 'Debug: Step Into' },
      { '<leader>do', function() require('dap').step_out() end, desc = 'Debug: Step Out' },
      { '<leader>b', function() require('dap').toggle_breakpoint() end, desc = 'Debug: Toggle Breakpoint' },
      { '<leader>B', function() require('dap').set_breakpoint() end, desc = 'Debug: Set Breakpoint' },
      { '<leader>du', function() require('dapui').toggle() end, desc = 'Debug: Toggle UI' },
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

      -- Setup dap-ui
      dapui.setup()

      -- Setup dap-python (uses debugpy)
      local ok, dap_python = pcall(require, 'dap-python')
      if ok then
        dap_python.setup('python')
      end

      -- Auto open/close dap-ui
      dap.listeners.before.attach.dapui_config = function() dapui.open() end
      dap.listeners.before.launch.dapui_config = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
      dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
    end,
  },
}
