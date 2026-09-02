-- Safety Filter (.sft) Extension for VLC Media Player
-- Manages .sft filter files that define time segments to skip or mute during playback.

function descriptor()
    return {
        title       = "Safety Filter (.sft)",
        version     = "2.0",
        author      = "VLC SFT Team",
        url         = "https://github.com/user/vlc-sft",
        shortdesc   = "Safety Filter (.sft) Editor",
        description = "Mark in/out points on video to create .sft filter files.",
        capabilities = {"menu"}
    }
end

-------------------------------------------------------------------------------
-- Pure Lua JSON (local functions only -- Lua 5.1 safe)
-------------------------------------------------------------------------------
local function json_encode(val, indent)
    indent = indent or ""
    local sub = indent .. "  "
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val == math.floor(val) and val < 1e15 and val > -1e15 then
            return string.format("%d", val)
        end
        return string.format("%.4f", val)
    elseif t == "string" then
        local s = val
        s = s:gsub("\\", "\\\\")
        s = s:gsub('"', '\\"')
        s = s:gsub("\n", "\\n")
        s = s:gsub("\r", "\\r")
        s = s:gsub("\t", "\\t")
        return '"' .. s .. '"'
    elseif t == "table" then
        local is_arr = true
        local max_n = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                is_arr = false
                break
            end
            if k > max_n then max_n = k end
        end
        if is_arr and max_n > 0 then
            local parts = {}
            for i = 1, max_n do
                parts[#parts + 1] = sub .. json_encode(val[i], sub)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        elseif is_arr then
            return "[]"
        else
            local parts = {}
            for k, v in pairs(val) do
                parts[#parts + 1] = sub .. '"' .. tostring(k) .. '": ' .. json_encode(v, sub)
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    end
    return "null"
end

local function json_decode(str)
    if not str or str == "" then return nil end
    local pos = 1
    local slen = #str

    local function skip_ws()
        while pos <= slen do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function parse_str()
        pos = pos + 1
        local buf = {}
        while pos <= slen do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(buf)
            elseif c == "\\" then
                pos = pos + 1
                local e = str:sub(pos, pos)
                if e == "n" then buf[#buf+1] = "\n"
                elseif e == "r" then buf[#buf+1] = "\r"
                elseif e == "t" then buf[#buf+1] = "\t"
                elseif e == '"' then buf[#buf+1] = '"'
                elseif e == "\\" then buf[#buf+1] = "\\"
                else buf[#buf+1] = e end
                pos = pos + 1
            else
                buf[#buf+1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end

    local function parse_num()
        local start = pos
        if str:sub(pos, pos) == "-" then pos = pos + 1 end
        while pos <= slen and str:sub(pos,pos):find("[0-9%.eE%+%-]") do
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos - 1))
    end

    local pval

    local function parse_arr()
        pos = pos + 1
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while pos <= slen do
            arr[#arr+1] = pval()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "]" then pos = pos + 1; return arr
            elseif c == "," then pos = pos + 1; skip_ws()
            else break end
        end
        return arr
    end

    local function parse_obj()
        pos = pos + 1
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while pos <= slen do
            skip_ws()
            if str:sub(pos, pos) ~= '"' then break end
            local key = parse_str()
            skip_ws()
            if str:sub(pos, pos) == ":" then pos = pos + 1; skip_ws() end
            obj[key] = pval()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "}" then pos = pos + 1; return obj
            elseif c == "," then pos = pos + 1
            else break end
        end
        return obj
    end

    pval = function()
        skip_ws()
        if pos > slen then return nil end
        local c = str:sub(pos, pos)
        if c == '"' then return parse_str()
        elseif c == "[" then return parse_arr()
        elseif c == "{" then return parse_obj()
        elseif c == "t" then pos = pos + 4; return true
        elseif c == "f" then pos = pos + 5; return false
        elseif c == "n" then pos = pos + 4; return nil
        elseif c == "-" or (c >= "0" and c <= "9") then return parse_num()
        end
        return nil
    end

    return pval()
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local dlg = nil

local sft_data = {
    sft_version = "1.0",
    metadata    = { title = "Untitled Movie", year = 2024, created_by = "VLC SFT Extension" },
    filters     = {}
}

local current_sft_path = ""
local function check_is_windows()
    if os and os.getenv then
        return (os.getenv("WINDIR") ~= nil or os.getenv("APPDATA") ~= nil)
    end
    return false
end

local w_sft_path   = nil
local w_in_time    = nil
local w_out_time   = nil
local w_action     = nil
local w_category   = nil
local w_desc       = nil
local w_list       = nil
local w_status     = nil
local w_live_time  = nil
local w_toggle_btn = nil

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function get_time_seconds()
    local input = vlc.object.input()
    if not input then return 0 end
    local ok_t, raw_time = pcall(vlc.var.get, input, "time")
    if ok_t and raw_time and type(raw_time) == "number" then
        if raw_time > 100000 then return raw_time / 1000000.0
        elseif raw_time >= 0 then return raw_time end
    end
    local ok_p, pos2 = pcall(vlc.var.get, input, "position")
    local ok_l, lng  = pcall(vlc.var.get, input, "length")
    if ok_p and ok_l and pos2 and lng then
        local ls = (lng > 100000) and (lng / 1000000.0) or lng
        if ls > 0 and pos2 >= 0 then return pos2 * ls end
    end
    return 0
end

local function fmt_time(s)
    if not s or s < 0 then s = 0 end
    local h   = math.floor(s / 3600)
    local m   = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%d:%02d:%05.2f", h, m, sec)
    else
        return string.format("%d:%05.2f", m, sec)
    end
end

local function refresh_filter_list()
    if not w_list then return end
    w_list:clear()
    for i, f in ipairs(sft_data.filters) do
        local icon = (f.action == "skip") and "SKIP" or "MUTE"
        local cat  = f.category and f.category:upper() or "OTHER"
        local note = (f.description and f.description ~= "") and (" | " .. f.description) or ""
        local line = string.format("#%d  %s  %s -> %s  [%s]%s",
            i, icon, fmt_time(f.start_time), fmt_time(f.end_time), cat, note)
        w_list:add_value(line, i)
    end
    if dlg then dlg:update() end
end

-------------------------------------------------------------------------------
-- File I/O
-------------------------------------------------------------------------------
local function get_video_sft_path()
    local ok, item = pcall(function() return vlc.input.item() end)
    if not ok or not item then return nil end
    local ok2, uri = pcall(function() return item:uri() end)
    if not ok2 or not uri then return nil end
    local filepath = uri:gsub("^file://", "")
    filepath = filepath:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
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
    local decoded = json_decode(content)
    if not decoded or not decoded.filters then
        if w_status then w_status:set_text("Invalid .sft file.") end
        return false
    end
    sft_data = decoded
    current_sft_path = path
    if w_sft_path then w_sft_path:set_text(path) end
    refresh_filter_list()
    if w_status then w_status:set_text("Loaded " .. #sft_data.filters .. " filters.") end
    if dlg then dlg:update() end
    return true
end

local function save_sft(path)
    if not path or path == "" then path = get_video_sft_path() end
    if not path or path == "" then
        local home = os.getenv("HOME") or "/tmp"
        path = home .. "/Desktop/movie.sft"
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
    f:write(json_encode(sft_data))
    f:close()
    current_sft_path = path
    if w_sft_path then w_sft_path:set_text(path) end
    if w_status then w_status:set_text("Saved " .. #sft_data.filters .. " filters to: " .. path) end
    if dlg then dlg:update() end
    return true
end

-------------------------------------------------------------------------------
-- Filter status flag
-------------------------------------------------------------------------------
local function get_user_data_dir()
    if check_is_windows() then
        local appdata = os.getenv("APPDATA") or "C:\\"
        return appdata .. "\\vlc\\lua\\extensions\\userdata"
    else
        local home = os.getenv("HOME") or "/tmp"
        return home .. "/Library/Application Support/org.videolan.vlc/lua/extensions/userdata"
    end
end

local function get_flag_path()
    local dir = get_user_data_dir()
    local sep = check_is_windows() and "\\" or "/"
    return dir .. sep .. "sft_disabled.flag"
end

local function is_filtering_enabled()
    local f = io.open(get_flag_path(), "r")
    if f then f:close(); return false end
    return true
end

local function set_filtering_enabled(enabled)
    local path = get_flag_path()
    if enabled then
        os.remove(path)
    else
        local dir = get_user_data_dir()
        if check_is_windows() then
            os.execute("if not exist \"" .. dir .. "\" mkdir \"" .. dir .. "\"")
        else
            os.execute("mkdir -p \"" .. dir .. "\"")
        end
        local f = io.open(path, "w")
        if f then f:write("disabled"); f:close() end
    end
end

-------------------------------------------------------------------------------
-- Button callbacks
-------------------------------------------------------------------------------
local function on_browse()
    local result = nil
    if check_is_windows() then
        local cmd = [[powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'Safety Filter (*.sft)|*.sft'; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.FileName }"]]
        local h = io.popen(cmd)
        if h then result = h:read("*l"); h:close() end
    else
        local h = io.popen("osascript -e 'try' -e 'POSIX path of (choose file with prompt \"Select .sft file\")' -e 'on error' -e '\"\"' -e 'end try' 2>/dev/null")
        if h then result = h:read("*l"); h:close() end
    end
    if result and result ~= "" then
        result = result:gsub("%s+$", "")
        if w_sft_path then w_sft_path:set_text(result) end
        load_sft(result)
    end
end

local function on_load()
    if w_sft_path then load_sft(w_sft_path:get_text()) end
end

local function on_set_in()
    local t = get_time_seconds()
    if w_in_time then w_in_time:set_text(string.format("%.2f", t)) end
    if w_status  then w_status:set_text("IN = " .. fmt_time(t)) end
    if dlg then dlg:update() end
end

local function on_set_out()
    local t = get_time_seconds()
    if w_out_time then w_out_time:set_text(string.format("%.2f", t)) end
    if w_status   then w_status:set_text("OUT = " .. fmt_time(t)) end
    if dlg then dlg:update() end
end

local function on_add_filter()
    if not w_in_time or not w_out_time then return end
    local t_in  = tonumber(w_in_time:get_text())
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
    local filt = {
        id          = #sft_data.filters + 1,
        start_time  = t_in,
        end_time    = t_out,
        action      = action_val,
        category    = cat_val,
        description = desc_val
    }
    table.insert(sft_data.filters, filt)
    refresh_filter_list()
    if w_status then
        w_status:set_text("Added #" .. filt.id .. " " .. action_val:upper() ..
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
    for idx, _ in pairs(sel) do indices[#indices+1] = idx end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do
        if idx <= #sft_data.filters then table.remove(sft_data.filters, idx) end
    end
    for i, f in ipairs(sft_data.filters) do f.id = i end
    refresh_filter_list()
    if w_status then w_status:set_text("Removed selected filter(s).") end
    if dlg then dlg:update() end
end

local function on_save()
    if w_sft_path then save_sft(w_sft_path:get_text()) end
end

local function on_save_as()
    local sel = nil
    if check_is_windows() then
        local cmd = [[powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.SaveFileDialog; $f.Filter = 'Safety Filter (*.sft)|*.sft'; $f.DefaultExt = 'sft'; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.FileName }"]]
        local h = io.popen(cmd)
        if h then sel = h:read("*l"); h:close() end
    else
        local dname = "movie.sft"
        if w_sft_path then
            local p = w_sft_path:get_text()
            if p and p ~= "" then dname = p:match("([^/]+)$") or "movie.sft" end
        end
        local h = io.popen("osascript -e 'try' -e 'POSIX path of (choose file name default name \"" .. dname .. "\" with prompt \"Save .sft As:\")' -e 'on error' -e '\"\"' -e 'end try' 2>/dev/null")
        if h then sel = h:read("*l"); h:close() end
    end
    if sel and sel ~= "" then
        sel = sel:gsub("%s+$", "")
        if sel:sub(-4) ~= ".sft" then sel = sel .. ".sft" end
        if w_sft_path then w_sft_path:set_text(sel) end
        save_sft(sel)
    end
end

local function on_toggle_filtering()
    local new_state = not is_filtering_enabled()
    set_filtering_enabled(new_state)
    if w_toggle_btn then w_toggle_btn:set_text(new_state and "Enabled" or "Disabled") end
    if w_status then
        w_status:set_text(new_state and "Filter: Enabled (Active)" or "Filter: Disabled (Bypassed)")
    end
    if dlg then dlg:update() end
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
    if dlg then dlg:show(); return end

    local default_path = get_video_sft_path()
    if not default_path then
        local home = os.getenv("HOME") or "/tmp"
        default_path = home .. "/Desktop/movie.sft"
    end

    dlg = vlc.dialog("Safety Filter (.sft) Manager")
    local row = 1

    -- ZONE 1: Header
    local cur_t = get_time_seconds()
    w_live_time  = dlg:add_label("<b>Position:</b> " .. fmt_time(cur_t), 1, row, 2, 1)
    dlg:add_label("<b>Status:</b>", 3, row, 1, 1)
    local tog_title = is_filtering_enabled() and "Enabled" or "Disabled"
    w_toggle_btn = dlg:add_button(tog_title, on_toggle_filtering, 4, row, 1, 1)

    -- ZONE 2: Mark Filter Segment
    row = row + 1
    dlg:add_label("<b>Mark Filter Segment</b>", 1, row, 4, 1)

    row = row + 1
    dlg:add_button("Set IN",  on_set_in,  1, row, 1, 1)
    w_in_time  = dlg:add_text_input("0.00", 2, row, 1, 1)
    dlg:add_button("Set OUT", on_set_out, 3, row, 1, 1)
    w_out_time = dlg:add_text_input("0.00", 4, row, 1, 1)

    row = row + 1
    dlg:add_label("<b>Action:</b>", 1, row, 1, 1)
    w_action = dlg:add_dropdown(2, row, 1, 1)
    w_action:add_value("Skip", 1)
    w_action:add_value("Mute", 2)
    dlg:add_label("<b>Category:</b>", 3, row, 1, 1)
    w_category = dlg:add_dropdown(4, row, 1, 1)
    w_category:add_value("Gore",      1)
    w_category:add_value("Violence",  2)
    w_category:add_value("Nudity",    3)
    w_category:add_value("Profanity", 4)
    w_category:add_value("Other",     5)

    row = row + 1
    dlg:add_label("<b>Note:</b>", 1, row, 1, 1)
    w_desc = dlg:add_text_input("", 2, row, 2, 1)
    dlg:add_button("Add Filter", on_add_filter, 4, row, 1, 1)

    -- ZONE 3: Active Filters
    row = row + 1
    dlg:add_label("<b>Active Filters</b>", 1, row, 4, 1)

    row = row + 1
    w_list = dlg:add_list(1, row, 4, 1)

    row = row + 1
    dlg:add_button("Remove Selected", on_remove_selected, 1, row, 2, 1)
    dlg:add_button("Clear All",       on_clear,           3, row, 2, 1)

    -- ZONE 4: File Details
    row = row + 1
    dlg:add_label("<b>File Details</b>", 1, row, 4, 1)

    row = row + 1
    w_sft_path = dlg:add_text_input(default_path, 1, row, 2, 1)
    dlg:add_button("Browse", on_browse, 3, row, 1, 1)
    dlg:add_button("Load",   on_load,   4, row, 1, 1)

    row = row + 1
    dlg:add_button("Save .sft",  on_save,    1, row, 2, 1)
    dlg:add_button("Save As...", on_save_as, 3, row, 2, 1)

    -- Status bar
    row = row + 1
    local init_status = is_filtering_enabled() and "Ready. Filter: Enabled" or "Ready. Filter: Disabled"
    w_status = dlg:add_label(init_status, 1, row, 4, 1)

    refresh_filter_list()
    dlg:show()
end

function deactivate()
    if dlg then dlg:delete(); dlg = nil end
end

function close()
    deactivate()
end

function input_changed()
    local ok, item = pcall(function() return vlc.input.item() end)
    if not ok or not item then return end
    local ok2, uri = pcall(function() return item:uri() end)
    if not ok2 or not uri then return end
    local base = uri:match("(.+)%.[^%.]+$")
    if base then
        local filepath = base:gsub("^file://", "")
        filepath = filepath:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        local sft_path = filepath .. ".sft"
        local test = io.open(sft_path, "r")
        if test then
            test:close()
            load_sft(sft_path)
        end
    end
end
