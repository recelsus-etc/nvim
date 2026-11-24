local M = {}
local nvim_treesitter = require("tree-sitter.nvim-treesitter")

local function start_highlighting(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_buf_is_loaded(buffer) then
        return
    end
    if vim.b[buffer].ex_treesitter then
        vim.treesitter.stop(buffer)
        vim.b[buffer].ex_treesitter = nil
    end
    if vim.bo[buffer].buftype ~= "" and vim.bo[buffer].buftype ~= "help" then
        return
    end
    local filetype = vim.bo[buffer].filetype
    local language = vim.treesitter.language.get_lang(filetype) or (filetype ~= "" and filetype or nil)
    if not language then
        return
    end
    local loaded, available, add_error = pcall(vim.treesitter.language.add, language)
    if not loaded or available == false or add_error then
        return
    end
    local queried, query = pcall(vim.treesitter.query.get, language, "highlights")
    if not queried or not query then
        return
    end
    local syntax = vim.bo[buffer].syntax
    local started = pcall(vim.treesitter.start, buffer, language)
    if started then
        vim.b[buffer].ex_treesitter = true
    else
        pcall(vim.treesitter.stop, buffer)
        vim.bo[buffer].syntax = syntax
    end
end

local function refresh_buffers()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        start_highlighting(buffer)
    end
end

local function install(languages)
    if not nvim_treesitter.is_loaded() then
        vim.notify("Parser installation skipped: run :TreesitterBootstrap first", vim.log.levels.INFO,
            { title = "Tree-sitter" })
        return
    end
    if #languages == 0 then
        languages = require("tree-sitter.languages")
    end
    nvim_treesitter.install(languages, function(err)
        if err then
            local level = tostring(err):match("^Missing commands:") and vim.log.levels.INFO or vim.log.levels.ERROR
            vim.notify(tostring(err), level, { title = "Tree-sitter" })
        end
        refresh_buffers()
    end)
end

local function create_commands()
    vim.api.nvim_create_user_command("TreesitterBootstrap", function(options)
        nvim_treesitter.bootstrap(options.bang, function(loaded)
            if loaded then
                vim.notify("Run :TreesitterInstall to install parsers", vim.log.levels.INFO,
                    { title = "Tree-sitter" })
            end
        end)
    end, { bang = true, desc = "Install nvim-treesitter (! to reinstall)" })
    vim.api.nvim_create_user_command("TreesitterInstall", function(options)
        install(options.fargs)
    end, {
        nargs = "*",
        desc = "Install tree-sitter parsers via nvim-treesitter",
        complete = function()
            return vim.deepcopy(require("tree-sitter.languages"))
        end,
    })
end

function M.setup()
    if not (vim.treesitter and vim.treesitter.start) then
        return
    end
    if nvim_treesitter.is_supported() then
        if nvim_treesitter.is_installed() then
            nvim_treesitter.load()
        end
        create_commands()
    end
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ex_treesitter", { clear = true }),
        callback = function(options) start_highlighting(options.buf) end,
    })
    refresh_buffers()
end

return M
