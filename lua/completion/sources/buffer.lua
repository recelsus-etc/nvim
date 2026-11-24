local M = {}
local compat = require("compat")
local minimum_length = 3
local maximum_lines = 10000
local rescan_interval = 2000
local cache = {}

local function collect(bufnr)
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local now = compat.uv.now()
    local cached = cache[bufnr]
    if cached and (cached.tick == tick or now - cached.time < rescan_interval) then
        return cached.words
    end
    local words = {}
    if vim.api.nvim_buf_line_count(bufnr) <= maximum_lines then
        local seen = {}
        for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
            for word in line:gmatch("[%a_][%w_]*") do
                if #word >= minimum_length and not seen[word] then
                    seen[word] = true
                    words[#words + 1] = word
                end
            end
        end
    end
    cache[bufnr] = { tick = tick, time = now, words = words }
    return words
end

function M.forget(bufnr)
    cache[bufnr] = nil
end

function M.complete(context, callback)
    local prefix = context.before:sub(context.keyword_start + 1)
    local items = {}
    for _, word in ipairs(collect(context.bufnr)) do
        if word ~= prefix then
            items[#items + 1] = { word = word, kind = "Text", menu = "[Buffer]" }
        end
    end
    callback({ start = context.keyword_start, items = items })
end

return M
