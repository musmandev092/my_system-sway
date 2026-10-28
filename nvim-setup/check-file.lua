local buf = vim.api.nvim_get_current_buf()
local name = vim.fn.expand("%:t")
local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

local attached = vim.wait(90000, function()
  return #vim.lsp.get_clients({ bufnr = buf }) > 0
end, 200)

vim.wait(5000, function() return false end, 200)

local clients = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = buf }))
local formatters = vim.tbl_map(function(f) return f.name end, require("conform").list_formatters_to_run(buf))

vim.cmd("write")
local after = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

io.stdout:write(("[%s] lsp_attached=%s clients=%s formatters=%s formatted=%s\n"):format(
  name,
  tostring(attached),
  table.concat(clients, ","),
  table.concat(formatters, ","),
  tostring(before ~= after)
))
io.stdout:write(after .. "\n---\n")
vim.cmd("qa!")
