--[[
  Safety Filter (.sft) Extension for VLC Media Player
  Description: Create and manage .sft filter files that define time segments
               to skip or mute during playback. A companion interface script
               (sft_looper.lua) handles the actual playback monitoring.
--]]

function descriptor()
    return {
        title = "Safety Filter (.sft)",
        version = "2.0",
        author = "VLC SFT Team",
        url = "https://github.com/user/vlc-sft",
        shortdesc = "Safety Filter (.sft) Editor",
        description = "Mark in/out points on video to create .sft filter files for skipping or muting sensitive content.",
        capabilities = {"input-listener", "menu"}
    }
end

-------------------------------------------------------------------------------
-- Pure Lua JSON Module (Embedded — zero external dependencies)
-------------------------------------------------------------------------------
local JSON = {}

function JSON.encode(val, indent)
    indent = indent or ""
    local sub_indent = indent .. "  "
    local t = type(val)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val == math.floor(val) and val < 1e15 and val > -1e15 then
            return string.format("%d", val)
        end
        return string.format("%.2f", val)
    elseif t == "string" then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        local is_array = true
        local max_index = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                is_array = false
                break
            end
            if k > max_index then max_index = k end
        end
        if is_array and max_index > 0 then
            local parts = {}
            for i = 1, max_index do
                table.insert(parts, sub_indent .. JSON.encode(val[i], sub_indent))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        elseif is_array and max_index == 0 then
            return "[]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, sub_indent .. '"' .. tostring(k) .. '": ' .. JSON.encode(v, sub_indent))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    end
    return "null"
end

function JSON.decode(str)
    if not str or str == "" then return nil end
    local pos = 1

    local function skip_ws()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_val

    local function parse_string()
        pos = pos + 1
        local start = pos
        local res = ""
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                res = res .. str:sub(start, pos - 1)
                pos = pos + 1
                return res
            elseif c == '\\' then
                res = res .. str:sub(start, pos - 1)
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == 'n' then res = res .. '\n'
                elseif esc == 'r' then res = res .. '\r'
                elseif esc == 't' then res = res .. '\t'
                elseif esc == '"' then res = res .. '"'
                elseif esc == '\\' then res = res .. '\\'
                else res = res .. esc end
                pos = pos + 1
                start = pos
            else
                pos = pos + 1
            end
        end
        return res
    end

    local function parse_number()
        local start = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c:find("[0-9%.eE%+%-]") then
                pos = pos + 1
            else
                break
            end
        end
        return tonumber(str:sub(start, pos - 1))
    end

    local function parse_array()
        pos = pos + 1
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
        while pos <= #str do
            table.insert(arr, parse_val())
            skip_ws()
            local c = str:sub(pos, pos)
            if c == ']' then pos = pos + 1; return arr
            elseif c == ',' then pos = pos + 1; skip_ws()
            else break end
        end
        return arr
    end

    local function parse_object()
        pos = pos + 1
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
        while pos <= #str do
            skip_ws()
            if str:sub(pos, pos) ~= '"' then break end
            local key = parse_string()
            skip_ws()
            if str:sub(pos, pos) == ':' then pos = pos + 1; skip_ws() end
            obj[key] = parse_val()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == '}' then pos = pos + 1; return obj
            elseif c == ',' then pos = pos + 1; skip_ws()
            else break end
        end
        return obj
    end

    parse_val = function()
        skip_ws()
        if pos > #str then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then return parse_string()
        elseif c == '[' then return parse_array()
        elseif c == '{' then return parse_object()
        elseif c == 't' and str:sub(pos, pos+3) == "true" then pos = pos + 4; return true
        elseif c == 'f' and str:sub(pos, pos+4) == "false" then pos = pos + 5; return false
        elseif c == 'n' and str:sub(pos, pos+3) == "null" then pos = pos + 4; return nil
        elseif c:find("[0-9%-]") then return parse_number()
        end
        return nil
    end

    return parse_val()
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local dlg = nil

local sft_data = {
    sft_version = "1.0",
    metadata = {
        title = "Untitled Movie",
        year = 2024,
        created_by = "VLC SFT Extension"
    },
    filters = {}
}

local current_sft_path = ""

-- Widget references
local w_sft_path = nil
local w_in_time = nil
local w_out_time = nil
local w_action = nil
local w_category = nil
local w_desc = nil
local w_list = nil
local w_status = nil

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function get_time_seconds()
    local input = vlc.object.input()
    if not input then return 0 end

    -- VLC 3.x on macOS: "time" returns microseconds
    local ok_t, raw_time = pcall(vlc.var.get, input, "time")
    if ok_t and raw_time and type(raw_time) == "number" then
        if raw_time > 100000 then
            return raw_time / 1000000.0
        elseif raw_time >= 0 then
            return raw_time
        end
    end

    -- Fallback: position * length
    local ok_p, pos = pcall(vlc.var.get, input, "position")
    local ok_l, len = pcall(vlc.var.get, input, "length")
    if ok_p and ok_l and pos and len and type(pos) == "number" and type(len) == "number" then
        local len_s = (len > 100000) and (len / 1000000.0) or len
        if len_s > 0 and pos >= 0 then
            return pos * len_s
        end
    end

    return 0
end

local function fmt_time(s)
    if not s or s < 0 then s = 0 end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%d:%02d:%05.2f", h, m, sec)
    else
        return string.format("%d:%05.2f", m, sec)
    end
end

-------------------------------------------------------------------------------
-- Filter list display (using add_list widget)
-------------------------------------------------------------------------------
local function refresh_filter_list()
    if not w_list then return end
    w_list:clear()
    for i, f in ipairs(sft_data.filters) do
        local icon = (f.action == "skip") and "SKIP" or "MUTE"
        local cat = f.category and f.category:upper() or "OTHER"
        local desc = (f.description and f.description ~= "") and (" | " .. f.description) or ""
        local line = string.format("#%d  %s  %s -> %s  [%s]%s",
            i, icon, fmt_time(f.start_time), fmt_time(f.end_time), cat, desc)
        w_list:add_value(line, i)
    end
    if dlg then dlg:update() end
end

-------------------------------------------------------------------------------
-- File I/O
-------------------------------------------------------------------------------
local function get_video_sft_path()
    -- Like subtitles: derive the .sft path from the currently playing video
    local ok, item = pcall(function() return vlc.input.item() end)
    if not ok or not item then return nil end
    local ok2, uri = pcall(function() return item:uri() end)
    if not ok2 or not uri then return nil end

    local filepath = uri:gsub("^file://", "")
    filepath = filepath:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    local base = filepath:match("(.+)%.[^%.]+$")
    if base then return base .. ".sft" end
    return nil
end

local function load_sft(path)
    if not path or path == "" then
        if w_status then w_status:set_text("No file path specified.") end
        return false
    end
    local f, err = io.open(path, "r")
    if not f then
        if w_status then w_status:set_text("Cannot open: " .. tostring(err)) end
        return false
    end
    local content = f:read("*all")
    f:close()

    local decoded = JSON.decode(content)
    if not decoded or not decoded.filters then
        if w_status then w_status:set_text("Invalid .sft JSON!") end
        return false
    end

    sft_data = decoded
    current_sft_path = path
    if w_sft_path then w_sft_path:set_text(path) end
    refresh_filter_list()

    if w_status then w_status:set_text("Loaded " .. #sft_data.filters .. " filters from " .. path) end
    if dlg then dlg:update() end
    return true
end

local function save_sft(path)
    if not path or path == "" then
        -- Default: save next to the video (like subtitles)
        path = get_video_sft_path()
    end
    if not path or path == "" then
        local home = os.getenv("HOME") or "/tmp"
        path = home .. "/Desktop/movie.sft"
    end
    if path:sub(1,1) ~= "/" then
        local home = os.getenv("HOME") or "/tmp"
        path = home .. "/Desktop/" .. path
    end

    if #sft_data.filters == 0 then
        if w_status then w_status:set_text("No filters to save!") end
        return false
    end

    local f, err = io.open(path, "w")
    if not f then
        if w_status then w_status:set_text("Cannot save: " .. tostring(err)) end
        return false
    end
    f:write(JSON.encode(sft_data))
    f:close()

    current_sft_path = path
    if w_sft_path then w_sft_path:set_text(path) end

    if w_status then w_status:set_text("Saved " .. #sft_data.filters .. " filters to " .. path) end
    if dlg then dlg:update() end
    return true
end

-------------------------------------------------------------------------------
-- Button callbacks
-------------------------------------------------------------------------------
local function on_browse()
    local script = 'try\nset p to POSIX path of (choose file of type {"sft","json"} with prompt "Select .sft file")\nreturn p\non error\nreturn ""\nend try'
    local cmd = "osascript -e '" .. script:gsub("\n", " ") .. "' 2>/dev/null"
    local h = io.popen(cmd)
    if h then
        local result = h:read("*l")
        h:close()
        if result and result ~= "" then
            result = result:gsub("%s+$", "")
            if w_sft_path then w_sft_path:set_text(result) end
            load_sft(result)
        end
    end
end

local function on_load()
    if w_sft_path then
        load_sft(w_sft_path:get_text())
    end
end

local function on_set_in()
    local t = get_time_seconds()
    if w_in_time then w_in_time:set_text(string.format("%.2f", t)) end
    if w_status then w_status:set_text("IN = " .. fmt_time(t) .. " (" .. string.format("%.2f", t) .. "s)") end
    if dlg then dlg:update() end
end

local function on_set_out()
    local t = get_time_seconds()
    if w_out_time then w_out_time:set_text(string.format("%.2f", t)) end
    if w_status then w_status:set_text("OUT = " .. fmt_time(t) .. " (" .. string.format("%.2f", t) .. "s)") end
    if dlg then dlg:update() end
end

local function on_add_filter()
    if not w_in_time or not w_out_time then return end
    local t_in = tonumber(w_in_time:get_text())
    local t_out = tonumber(w_out_time:get_text())

    if not t_in or not t_out or t_in >= t_out then
        if w_status then w_status:set_text("Error: IN must be less than OUT!") end
        if dlg then dlg:update() end
        return
    end

    local action_val = "skip"
    if w_action and w_action:get_value() == 2 then action_val = "mute" end

    local cats = {"gore", "violence", "nudity", "profanity", "other"}
    local cat_val = "other"
    if w_category then cat_val = cats[w_category:get_value()] or "other" end

    local desc_val = ""
    if w_desc then desc_val = w_desc:get_text() or "" end

    local new_filter = {
        id = #sft_data.filters + 1,
        start_time = t_in,
        end_time = t_out,
        action = action_val,
        category = cat_val,
        description = desc_val
    }
    table.insert(sft_data.filters, new_filter)
    refresh_filter_list()

    if w_status then
        w_status:set_text("Added #" .. new_filter.id .. " " .. action_val:upper() ..
            " " .. fmt_time(t_in) .. " -> " .. fmt_time(t_out))
    end
    if dlg then dlg:update() end
end

local function on_remove_selected()
    if not w_list then return end
    local sel = w_list:get_selection()
    if not sel then
        if w_status then w_status:set_text("Select a filter to remove.") end
        if dlg then dlg:update() end
        return
    end
    local indices = {}
    for idx, _ in pairs(sel) do
        table.insert(indices, idx)
    end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do
        if idx <= #sft_data.filters then
            table.remove(sft_data.filters, idx)
        end
    end
    for i, f in ipairs(sft_data.filters) do f.id = i end
    refresh_filter_list()
    if w_status then w_status:set_text("Removed selected filter(s).") end
    if dlg then dlg:update() end
end

local function on_export()
    if w_sft_path then save_sft(w_sft_path:get_text()) end
end

local function on_clear()
    sft_data.filters = {}
    refresh_filter_list()
    if w_status then w_status:set_text("Cleared all filters.") end
    if dlg then dlg:update() end
end

-------------------------------------------------------------------------------
-- VLC Extension Lifecycle
-------------------------------------------------------------------------------
function menu()
    return {"Open Safety Filter Editor"}
end

function trigger_menu(id)
    if id == 1 then activate() end
end

function activate()
    if dlg then
        dlg:show()
        return
    end

    -- Like subtitles: default .sft path matches the current video filename
    local default_path = get_video_sft_path()
    if not default_path then
        local home = os.getenv("HOME") or "/tmp"
        default_path = home .. "/Desktop/movie.sft"
    end

    dlg = vlc.dialog("Safety Filter (.sft) Manager")

    -- Strict 4-column grid. Every widget uses col_span=1 and row_span=1.
    local row = 1

    -- Row 1: .sft File Path
    dlg:add_label("<b>.sft File:</b>", 1, row, 1, 1)
    w_sft_path = dlg:add_text_input(default_path, 2, row, 1, 1)
    dlg:add_button("Browse", on_browse, 3, row, 1, 1)
    dlg:add_button("Load", on_load, 4, row, 1, 1)

    -- Row 2: IN / OUT time capture
    row = row + 1
    dlg:add_button("Set IN", on_set_in, 1, row, 1, 1)
    w_in_time = dlg:add_text_input("0.00", 2, row, 1, 1)
    dlg:add_button("Set OUT", on_set_out, 3, row, 1, 1)
    w_out_time = dlg:add_text_input("0.00", 4, row, 1, 1)

    -- Row 3: Action + Category
    row = row + 1
    dlg:add_label("<b>Action:</b>", 1, row, 1, 1)
    w_action = dlg:add_dropdown(2, row, 1, 1)
    w_action:add_value("Skip", 1)
    w_action:add_value("Mute", 2)
    dlg:add_label("<b>Category:</b>", 3, row, 1, 1)
    w_category = dlg:add_dropdown(4, row, 1, 1)
    w_category:add_value("Gore", 1)
    w_category:add_value("Violence", 2)
    w_category:add_value("Nudity", 3)
    w_category:add_value("Profanity", 4)
    w_category:add_value("Other", 5)

    -- Row 4: Description + Add button
    row = row + 1
    dlg:add_label("<b>Desc:</b>", 1, row, 1, 1)
    w_desc = dlg:add_text_input("", 2, row, 1, 1)
    dlg:add_button("+ ADD FILTER", on_add_filter, 3, row, 2, 1)

    -- Row 5: Filter list (add_list — the proper scrollable list widget)
    row = row + 1
    w_list = dlg:add_list(1, row, 4, 1)

    -- Row 6: Control buttons
    row = row + 1
    dlg:add_button("Export .sft", on_export, 1, row, 1, 1)
    dlg:add_button("Remove Sel.", on_remove_selected, 2, row, 1, 1)
    dlg:add_button("Clear All", on_clear, 3, row, 1, 1)
    dlg:add_button("Close", close, 4, row, 1, 1)

    -- Row 7: Status
    row = row + 1
    w_status = dlg:add_label("Ready. Play video, pause, click Set IN / Set OUT.", 1, row, 4, 1)

    refresh_filter_list()
    dlg:show()
end

function deactivate()
    if dlg then
        dlg:delete()
        dlg = nil
    end
end

function close()
    deactivate()
end

function input_changed()
    local item = vlc.input.item()
    if not item then return end
    local uri = item:uri()
    if not uri then return end

    local base = uri:match("(.+)%.[^%.]+$")
    if base then
        local sft_uri = base .. ".sft"
        local filepath = sft_uri:gsub("^file://", "")
        filepath = filepath:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        local test = io.open(filepath, "r")
        if test then
            test:close()
            load_sft(filepath)
        end
    end
end
