#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-h]

  CHECK_NVIM=<path>  Select the nvim executable (default: nvim on PATH)
  -h, --help         Show this help
EOF
}

case "${1:-}" in
    "") ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
esac

config_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nvim="${CHECK_NVIM:-nvim}"

if ! command -v "$nvim" >/dev/null 2>&1; then
    echo "[NG] nvim: not found (Neovim is required)"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/nvim-check.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
script="$work_dir/check.lua"

cat >"$script" <<'LUA'
local root = vim.env.NVIM_CHECK_ROOT
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local lines = {}
local function out(text) lines[#lines + 1] = text or "" end
local function mark(ok) return ok and "[OK]" or "[--]" end
local function section(title) out(); out("== " .. title) end

local function which(command)
    local path = vim.fn.exepath(command)
    return path ~= "" and path or nil
end

local function find_any(spec)
    for _, command in ipairs(vim.split(spec, "|", { plain = true })) do
        local path = which(command)
        if path then return command, path end
    end
end

local function first_line(command)
    local ok, output = pcall(vim.fn.systemlist, command)
    if not ok or vim.v.shell_error ~= 0 or not output[1] then return nil end
    return vim.trim(output[1])
end

local function check_command(spec, purpose, version_command)
    local command, path = find_any(spec)
    local detail = path or "not found"
    if path and version_command then
        local version = first_line(version_command(command))
        if version then detail = detail .. " (" .. version .. ")" end
    end
    out(("  %s %-22s %-44s %s"):format(mark(path), spec, detail, purpose))
    return path ~= nil
end

local version = vim.version()
local version_text = ("%d.%d.%d"):format(version.major, version.minor, version.patch)
section("Neovim")
out(("  %s nvim %s (%s)"):format(mark(true), version_text, vim.v.progpath))
if vim.fn.has("nvim-0.9") == 0 then
    out("  [NG] Versions before 0.9 are unsupported")
elseif vim.fn.has("nvim-0.12") == 1 then
    out("  [OK] Primary target version (0.12)")
else
    out("  [OK] Supported through compatibility fallbacks (primary target: 0.12)")
end
out("  config: " .. root)

section("Optional commands")
check_command("git", "Git Signs / :MasonBootstrap", function(c) return { c, "--version" } end)
local shell = vim.o.shell
check_command(vim.split(shell, " ", { plain = true })[1], "Terminal ('shell')")

section("Clipboard")
local environment = dofile(root .. "/lua/conf.d/environment.lua").detect()
local flags = {}
for _, name in ipairs({ "is_wsl", "is_windows", "is_macos", "is_tmux", "is_ssh", "has_wayland", "has_x11" }) do
    if environment[name] then flags[#flags + 1] = name end
end
out("  environment: " .. (#flags > 0 and table.concat(flags, ", ") or "(none)"))
out("  [OK] copy : OSC52" .. (vim.base64 and "" or " (compat)") .. " (requires terminal OSC52 support)")
if environment.paste_command then
    local paste = environment.paste_command
    out("  [OK] paste: " .. paste[1] .. (#paste > 1 and " ..." or "") .. " (" .. (which(paste[1]) or "?") .. ")")
else
    out("  [--] paste: Neovim cache only (cannot paste text copied by other applications)")
end

section("Tree-sitter")
local nvim_treesitter = require("tree-sitter.nvim-treesitter")
if not nvim_treesitter.is_supported() then
    out("  [--] nvim-treesitter: requires Neovim 0.10 or later (bundled and installed parsers only)")
else
    local expected = nvim_treesitter.branch()
    local installed = nvim_treesitter.installed_branch()
    if not nvim_treesitter.is_installed() then
        out("  [--] nvim-treesitter: not installed (:TreesitterBootstrap fetches " .. expected .. ")")
    elseif installed ~= expected then
        out(("  [NG] nvim-treesitter: %s is installed; this Neovim requires %s (:TreesitterBootstrap!)")
            :format(tostring(installed), expected))
    else
        out("  [OK] nvim-treesitter (" .. installed .. "): " .. nvim_treesitter.path)
        pcall(nvim_treesitter.load)
    end
    out()
    out("  Parser prerequisites (" .. expected .. ")")
    for _, requirement in ipairs(nvim_treesitter.requirements()) do
        local first = vim.split(requirement, "|", { plain = true })[1]
        check_command(requirement, "fetch and build parsers",
            first == "tree-sitter" and function(c) return { c, "--version" } end or nil)
    end
end

local function find_parser(language)
    return vim.api.nvim_get_runtime_file("parser/" .. language .. ".so", false)[1]
end
local function has_query(language)
    return #vim.api.nvim_get_runtime_file("queries/" .. language .. "/highlights.scm", true) > 0
end
out()
out("  Languages (tree-sitter/languages.lua)")
local configured = {}
for _, language in ipairs(dofile(root .. "/lua/tree-sitter/languages.lua")) do
    configured[language] = true
    local parser = find_parser(language)
    local status = parser and (has_query(language) and parser or parser .. "  (no highlights query)")
        or "not installed"
    out(("  %s %-16s %s"):format(mark(parser and has_query(language)), language, status))
end
local others = {}
for _, file in ipairs(vim.api.nvim_get_runtime_file("parser/*.so", true)) do
    local language = vim.fn.fnamemodify(file, ":t:r")
    if not configured[language] and not vim.tbl_contains(others, language) then
        others[#others + 1] = language
    end
end
if #others > 0 then
    table.sort(others)
    out("  other parsers: " .. table.concat(others, ", "))
end

section("LSP")
local native = type(vim.lsp.config) == "table" and type(vim.lsp.enable) == "function"
out("  [OK] connection method: " .. (native and "vim.lsp.config / vim.lsp.enable" or "vim.lsp.start (lsp/fallback.lua)"))
do
    local mason = require("lsp.mason")
    local mason_root = vim.fn.stdpath("data") .. "/mason"
    if not mason.is_supported() then
        out("  [--] mason.nvim: requires Neovim 0.10 or later (servers on PATH only)")
    elseif mason.is_installed() then
        out("  [OK] mason.nvim: " .. mason.path)
        vim.env.PATH = mason_root .. "/bin:" .. vim.env.PATH
    else
        out("  [--] mason.nvim: not installed (:MasonBootstrap fetches it)")
    end

    out()
    out("  Mason prerequisites" .. (mason.is_supported() and "" or " (unused with this Neovim version)"))
    check_command("git", "fetch mason.nvim")
    check_command("curl|wget", "download packages")
    check_command("tar", "extract archives")
    check_command("gzip", "decompress archives")
    check_command("bash", "run installers")
    check_command("unzip", "extract zip packages")

    local specs = {}
    for _, file in ipairs(vim.fn.glob(root .. "/lua/lsp/servers/*.lua", false, true)) do
        local language = vim.fn.fnamemodify(file, ":t:r")
        local ok, spec = pcall(dofile, file)
        specs[#specs + 1] = { language = language, ok = ok, spec = spec }
    end
    table.sort(specs, function(a, b) return a.language < b.language end)

    local runtimes = {}
    for _, item in ipairs(specs) do
        for _, requirement in ipairs(item.ok and item.spec.requires or {}) do
            runtimes[requirement] = runtimes[requirement] or {}
            table.insert(runtimes[requirement], item.language)
        end
    end
    local requirement_names = vim.tbl_keys(runtimes)
    table.sort(requirement_names)
    local versions = {
        node = function(c) return { c, "--version" } end,
        npm = function(c) return { c, "--version" } end,
        go = function(c) return { c, "version" } end,
        cargo = function(c) return { c, "--version" } end,
        python3 = function(c) return { c, "--version" } end,
        java = function(c) return { "sh", "-c", c .. " -version 2>&1" } end,
    }
    out()
    out("  Runtimes (servers/*.lua requires)")
    local available = {}
    for _, requirement in ipairs(requirement_names) do
        local first = vim.split(requirement, "|", { plain = true })[1]
        available[requirement] = check_command(requirement, "for: " .. table.concat(runtimes[requirement], ", "),
            versions[first])
    end

    out()
    out("  Servers")
    for _, item in ipairs(specs) do
        if not item.ok or type(item.spec) ~= "table" or type(item.spec.config) ~= "table" then
            out(("  [NG] %-11s invalid spec: %s"):format(item.language, tostring(item.spec)))
        else
            local spec = item.spec
            local command = spec.executable or (type(spec.config.cmd) == "table" and spec.config.cmd[1])
            local path = command and which(command)
            local missing = {}
            for _, requirement in ipairs(spec.requires or {}) do
                if not available[requirement] then missing[#missing + 1] = requirement end
            end
            local missing_runtime = {}
            for _, requirement in ipairs(spec.runtime_requires or {}) do
                if not find_any(requirement) then missing_runtime[#missing_runtime + 1] = requirement end
            end
            local status
            if #missing_runtime > 0 then
                status = "needs runtime: " .. table.concat(missing_runtime, ", ")
            elseif path then
                status = "ready: " .. path
            elseif spec.install_hint then
                status = spec.install_hint
            elseif not spec.package then
                status = "not found: " .. tostring(command) .. " (unavailable through Mason; add to PATH)"
            elseif not mason.is_supported() then
                status = "not found: " .. tostring(command) .. " (add to PATH)"
            elseif #missing > 0 then
                status = "needs: " .. table.concat(missing, ", ")
            elseif mason.is_installed() then
                status = "installable: :LspInstall " .. item.language
            else
                status = "installable after :MasonBootstrap"
            end
            out(("  %s %-11s %-14s %s"):format(mark(path and #missing_runtime == 0), item.language, spec.name, status))
        end
    end
end

io.stdout:write(table.concat(lines, "\n") .. "\n")
LUA

NVIM_CHECK_ROOT="$config_root" XDG_STATE_HOME="$work_dir/state" "$nvim" --headless -u NONE -i NONE -n \
    -c "luafile $script" -c "qa!" 2>&1
