local function log(msg) io.stdout:write(msg .. "\n") end

require("lazy").load({ plugins = { "mason.nvim" } })
local registry = require("mason-registry")
registry.refresh()
local wanted = vim.deepcopy(LazyVim.opts("mason.nvim").ensure_installed or {})

local failed, pkgs = {}, {}
for _, name in ipairs(wanted) do
  local ok, pkg = pcall(registry.get_package, name)
  if not ok then
    table.insert(failed, name .. " (not in registry)")
  else
    pkgs[name] = pkg
    if not pkg:is_installed() and not pkg:is_installing() then
      pkg:install({}, function(success, err)
        if not success then table.insert(failed, name .. ": " .. tostring(err)) end
      end)
    end
  end
end
vim.wait(1800000, function()
  for _, pkg in pairs(pkgs) do
    if pkg:is_installing() then return false end
  end
  return true
end, 1000)
for name, pkg in pairs(pkgs) do
  if not pkg:is_installed() then table.insert(failed, name .. " (not installed)") end
end
log(("mason: %d wanted, failures: %s"):format(#wanted, #failed > 0 and table.concat(failed, "; ") or "none"))

require("lazy").load({ plugins = { "nvim-treesitter" } })
local parsers = LazyVim.opts("nvim-treesitter").ensure_installed or {}
local ts = require("nvim-treesitter")
if ts.install then
  ts.install(parsers, { summary = true }):wait(1800000)
else
  vim.cmd("TSInstallSync " .. table.concat(parsers, " "))
end
local missing = {}
for _, p in ipairs(parsers) do
  if not pcall(vim.treesitter.language.add, p) then table.insert(missing, p) end
end
log(("treesitter: %d parsers, missing: %s"):format(#parsers, #missing > 0 and table.concat(missing, ",") or "none"))
vim.cmd("qa!")
