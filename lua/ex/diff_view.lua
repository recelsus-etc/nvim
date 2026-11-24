local M = {}
local compat = require("compat")
local session
local request_generation = 0

local function valid_window(window)
    return window and vim.api.nvim_win_is_valid(window)
end

local function is_file_buffer(buffer)
    return vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].buflisted and vim.bo[buffer].buftype == ""
        and vim.api.nvim_buf_get_name(buffer) ~= ""
end

local function file_buffers()
    local buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if is_file_buffer(buffer) then
            buffers[#buffers + 1] = buffer
        end
    end
    table.sort(buffers, function(left, right)
        return vim.api.nvim_buf_get_name(left) < vim.api.nvim_buf_get_name(right)
    end)
    return buffers
end

local function display_name(buffer)
    local path = vim.api.nvim_buf_get_name(buffer)
    local name = vim.fn.fnamemodify(path, ":.")
    return name .. (vim.bo[buffer].modified and " [+]" or "")
end

local function select_buffers(origin_buffer, callback)
    local buffers = file_buffers()
    if #buffers < 2 then
        vim.notify("Open two file buffers before starting Diff View", vim.log.levels.INFO,
            { title = "Diff View" })
        return
    end
    local function select_right(left)
        local choices = {}
        for _, buffer in ipairs(buffers) do
            if buffer ~= left then choices[#choices + 1] = buffer end
        end
        vim.ui.select(choices, {
            prompt = "Compare with " .. display_name(left) .. ": ",
            format_item = display_name,
        }, function(right)
            if right then callback(left, right) end
        end)
    end
    if is_file_buffer(origin_buffer) then
        select_right(origin_buffer)
    else
        vim.ui.select(buffers, {
            prompt = "Left file: ", format_item = display_name,
        }, function(left)
            if left then select_right(left) end
        end)
    end
end

local function leave_diff(window)
    if valid_window(window) and vim.wo[window].diff then
        vim.api.nvim_win_call(window, function() vim.cmd("diffoff") end)
    end
end

local function clear_window_labels(window)
    if valid_window(window) then
        vim.wo[window].winbar = ""
        vim.wo[window].statusline = ""
    end
end

local function configure_window(window, buffer, side, mode)
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":.")
        :gsub("%%", "%%%%"):gsub("[%c]", " ")
    vim.wo[window].winbar = (" %%#ExDiffViewTitle# %s  %s %%*"):format(side, name)
    vim.wo[window].statusline = " DIFF " .. mode .. " %m | :w | :DiffViewClose "
    compat.set_window_local(window, "number", true)
    compat.set_window_local(window, "relativenumber", false)
    compat.set_window_local(window, "wrap", false)
    vim.api.nvim_win_call(window, function() vim.cmd("diffthis") end)
end

local function start_session(mode, origin_window, left_buffer, right_buffer)
    if not valid_window(origin_window) or not is_file_buffer(left_buffer)
        or not is_file_buffer(right_buffer) or left_buffer == right_buffer
    then
        vim.notify("Selected buffers are no longer available", vim.log.levels.INFO,
            { title = "Diff View" })
        return
    end
    local current = {
        mode = mode,
        origin_window = origin_window,
        origin_tabpage = vim.api.nvim_win_get_tabpage(origin_window),
        origin_view = vim.api.nvim_win_call(origin_window, vim.fn.winsaveview),
        left_buffer = left_buffer,
        right_buffer = right_buffer,
    }
    vim.api.nvim_set_current_win(origin_window)
    if mode == "tab" then
        vim.cmd.tabnew()
        current.diff_tabpage = vim.api.nvim_get_current_tabpage()
    else
        vim.cmd("botright split")
    end
    current.left_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(current.left_window, left_buffer)
    vim.cmd("rightbelow vsplit")
    current.right_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(current.right_window, right_buffer)
    configure_window(current.left_window, left_buffer, "LEFT", mode)
    configure_window(current.right_window, right_buffer, "RIGHT", mode)
    local cursor = vim.api.nvim_win_get_cursor(origin_window)
    local row = math.min(cursor[1], vim.api.nvim_buf_line_count(left_buffer))
    local line = vim.api.nvim_buf_get_lines(left_buffer, row - 1, row, false)[1] or ""
    vim.api.nvim_win_set_cursor(current.left_window, {
        row, math.min(cursor[2], #line),
    })
    vim.api.nvim_set_current_win(current.left_window)
    session = current
end

function M.close()
    local current = session
    if not current then
        vim.notify("No Diff View is open", vim.log.levels.INFO, { title = "Diff View" })
        return
    end
    leave_diff(current.left_window)
    leave_diff(current.right_window)
    if current.mode == "tab" then
        if vim.api.nvim_tabpage_is_valid(current.diff_tabpage) then
            vim.api.nvim_set_current_tabpage(current.diff_tabpage)
            if #vim.api.nvim_list_tabpages() > 1 then
                local ok, close_error = pcall(vim.cmd, "tabclose")
                if not ok then
                    vim.notify(tostring(close_error), vim.log.levels.ERROR, { title = "Diff View" })
                    return
                end
            else
                if valid_window(current.right_window) then
                    if valid_window(current.left_window) then
                        vim.api.nvim_win_close(current.right_window, false)
                    else
                        clear_window_labels(current.right_window)
                    end
                end
                clear_window_labels(current.left_window)
            end
        end
        if vim.api.nvim_tabpage_is_valid(current.origin_tabpage) then
            vim.api.nvim_set_current_tabpage(current.origin_tabpage)
        end
    else
        if vim.api.nvim_tabpage_is_valid(current.origin_tabpage) then
            vim.api.nvim_set_current_tabpage(current.origin_tabpage)
        end
        if valid_window(current.right_window) then
            if valid_window(current.left_window) or valid_window(current.origin_window) then
                vim.api.nvim_win_close(current.right_window, false)
            else
                clear_window_labels(current.right_window)
            end
        end
        if valid_window(current.left_window) then
            if valid_window(current.origin_window) then
                vim.api.nvim_win_close(current.left_window, false)
            else
                clear_window_labels(current.left_window)
            end
        end
        if valid_window(current.origin_window) then
            vim.api.nvim_set_current_win(current.origin_window)
            pcall(vim.api.nvim_win_call, current.origin_window, function()
                vim.fn.winrestview(current.origin_view)
            end)
        end
    end
    session = nil
end

function M.update()
    local current = session
    if not current then
        vim.notify("No Diff View is open", vim.log.levels.INFO, { title = "Diff View" })
        return
    end
    local window = valid_window(current.left_window) and current.left_window or current.right_window
    if valid_window(window) then
        vim.api.nvim_win_call(window, function() vim.cmd("diffupdate") end)
    end
end

function M.open(mode)
    mode = mode == "" and "tab" or mode
    if mode ~= "tab" and mode ~= "split" then
        vim.notify("Usage: :DiffView [tab|split]", vim.log.levels.INFO, { title = "Diff View" })
        return
    end
    if session then M.close() end
    local origin_window = vim.api.nvim_get_current_win()
    local origin_buffer = vim.api.nvim_win_get_buf(origin_window)
    if mode == "split" and (vim.bo[origin_buffer].buftype ~= "" or compat.is_winfixbuf(origin_window)) then
        vim.notify("Start the split view from an editing window", vim.log.levels.INFO,
            { title = "Diff View" })
        return
    end
    if mode == "split" then
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.wo[window].diff then
                vim.notify("Close the existing diff in this tab before opening a split view",
                    vim.log.levels.INFO, { title = "Diff View" })
                return
            end
        end
    end
    request_generation = request_generation + 1
    local generation = request_generation
    select_buffers(origin_buffer, function(left, right)
        if generation == request_generation then
            start_session(mode, origin_window, left, right)
        end
    end)
end

function M.setup()
    local function set_highlights()
        vim.api.nvim_set_hl(0, "ExDiffViewTitle", {
            fg = "#87cefa", bg = "#263a4b", bold = true, default = true,
        })
    end
    set_highlights()
    local group = vim.api.nvim_create_augroup("ex_diff_view", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = set_highlights,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(options)
            local current = session
            local closed = tonumber(options.match)
            if current and (closed == current.left_window or closed == current.right_window) then
                vim.schedule(function()
                    if session == current then M.close() end
                end)
            end
        end,
    })
    vim.api.nvim_create_user_command("DiffView", function(options) M.open(options.args) end, {
        nargs = "?", complete = function() return { "tab", "split" } end,
        desc = "Compare two open file buffers",
    })
    vim.api.nvim_create_user_command("DiffViewClose", M.close, {
        desc = "Close the buffer comparison",
    })
    vim.api.nvim_create_user_command("DiffViewUpdate", M.update, {
        desc = "Refresh the buffer comparison",
    })
    vim.keymap.set("n", "<leader>ds", function() M.open("split") end,
        { desc = "diff view: split comparison" })
    vim.keymap.set("n", "<leader>dt", function() M.open("tab") end,
        { desc = "diff view: tab comparison" })
    vim.keymap.set("n", "<leader>du", M.update,
        { desc = "diff view: update comparison" })
end

return M
