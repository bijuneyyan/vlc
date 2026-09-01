--[[
  Safety Filter (.sft) Extension for VLC Media Player
  Author: VLC SFT Team
  Description: Automatically skip or mute sensitive video portions using .sft filter files,
               and interactive marker editor to generate .sft files.
--]]

-- Top-level extension descriptor required by VLC
function descriptor()
    return {
        title = "Safety Filter (.sft)",
        version = "1.0",
        author = "VLC SFT Team",
        url = "https://github.com/user/vlc-sft",
        shortdesc = "Safety Filter (.sft) Player & Marker Editor",
        description = "Automatically skip or mute sensitive video portions using .sft filter files, or mark in-out points to generate .sft files.",
        capabilities = {"input-listener", "menu"}
    }
end

-------------------------------------------------------------------------------
-- Pure Lua JSON Module (Embedded for zero external dependencies)
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
        return tostring(val)
    elseif t == "string" then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        -- Check if it's an array or dictionary
        local is_array = true
        local max_index = 0
        for k, v in pairs(val) do
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

    local function skip_whitespace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_val -- forward declaration

    local function parse_string()
        pos = pos + 1 -- skip opening quote
        local start_pos = pos
        local res = ""
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                res = res .. str:sub(start_pos, pos - 1)
                pos = pos + 1
                return res
            elseif c == '\\' then
                res = res .. str:sub(start_pos, pos - 1)
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == 'n' then res = res .. '\n'
                elseif esc == 'r' then res = res .. '\r'
                elseif esc == 't' then res = res .. '\t'
                elseif esc == '"' then res = res .. '"'
                elseif esc == '\\' then res = res .. '\\'
                else res = res .. esc end
                pos = pos + 1
                start_pos = pos
            else
                pos = pos + 1
            end
        end
        return res
    end

    local function parse_number()
        local start_pos = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c:find("[0-9%.eE%+]") then
                pos = pos + 1
            else
                break
            end
        end
        local num_str = str:sub(start_pos, pos - 1)
        return tonumber(num_str)
    end

    local function parse_array()
        pos = pos + 1 -- skip '['
        local arr = {}
        skip_whitespace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while pos <= #str do
            local val = parse_val()
            table.insert(arr, val)
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
                skip_whitespace()
            else
                break
            end
        end
        return arr
    end

    local function parse_object()
        pos = pos + 1 -- skip '{'
        local obj = {}
        skip_whitespace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while pos <= #str do
            skip_whitespace()
            if str:sub(pos, pos) ~= '"' then break end
            local key = parse_string()
            skip_whitespace()
            if str:sub(pos, pos) == ':' then
                pos = pos + 1
                skip_whitespace()
            end
            local val = parse_val()
            obj[key] = val
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
                skip_whitespace()
            else
                break
            end
        end
        return obj
    end

    parse_val = function()
        skip_whitespace()
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
-- Safety Filter State & Global Variables
-------------------------------------------------------------------------------
local dialog = nil
local sft_data = {
    sft_version = "1.0",
    metadata = {
        title = "Untitled Movie",
        year = 2024,
        created_by = "VLC SFT Extension"
    },
    filters = {}
}

local filtering_enabled = true
local muted_by_sft = false
local current_sft_path = ""

-- GUI Widget References
local w_status = nil
local w_sft_path = nil
local w_in_time = nil
local w_out_time = nil
local w_action_dropdown = nil
local w_category_dropdown = nil
local w_desc = nil
local w_filter_list = nil
local w_toggle_filtering = nil

-------------------------------------------------------------------------------
-- Helper Functions
-------------------------------------------------------------------------------
local function get_current_time_sec()
    local input = vlc.object.input()
    if not input then return 0 end
    local time_us = vlc.var.get(input, "time") or 0
    return time_us / 1000000.0
end

local function seek_to_sec(target_sec)
    local input = vlc.object.input()
    if not input then return end
    vlc.var.set(input, "time", math.floor(target_sec * 1000000))
end

local function format_time(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    local ms = math.floor((seconds - math.floor(seconds)) * 10)
    if hrs > 0 then
        return string.format("%02d:%02d:%02d.%d", hrs, mins, secs, ms)
    else
        return string.format("%02d:%02d.%d", mins, secs, ms)
    end
end

local function update_filter_list_display()
    if not w_filter_list then return end
    local display_text = ""
    for i, filter in ipairs(sft_data.filters) do
        display_text = display_text .. string.format(
            "[%d] %s -> %s | Action: %s | Cat: %s | %s\n",
            i,
            format_time(filter.start_time),
            format_time(filter.end_time),
            filter.action:upper(),
            filter.category,
            filter.description or ""
        )
    end
    if display_text == "" then
        display_text = "(No filter segments added yet)"
    end
    w_filter_list:set_text(display_text)
end

-------------------------------------------------------------------------------
-- SFT File I/O
-------------------------------------------------------------------------------
local function load_sft_file(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        if w_status then w_status:set_text("Error opening file: " .. tostring(err)) end
        return false
    end
    local content = file:read("*all")
    file:close()

    local decoded = JSON.decode(content)
    if not decoded or not decoded.filters then
        if w_status then w_status:set_text("Invalid .sft JSON format!") end
        return false
    end

    sft_data = decoded
    current_sft_path = filepath
    if w_sft_path then w_sft_path:set_text(filepath) end
    if w_status then w_status:set_text("Loaded " .. #sft_data.filters .. " filters from .sft") end
    update_filter_list_display()
    return true
end

local function save_sft_file(filepath)
    if not sft_data or #sft_data.filters == 0 then
        if w_status then w_status:set_text("No filters to save!") end
        return false
    end

    local file, err = io.open(filepath, "w")
    if not file then
        if w_status then w_status:set_text("Error saving file: " .. tostring(err)) end
        return false
    end

    local json_str = JSON.encode(sft_data)
    file:write(json_str)
    file:close()

    current_sft_path = filepath
    if w_status then w_status:set_text("Saved " .. #sft_data.filters .. " filters to " .. filepath) end
    return true
end

-------------------------------------------------------------------------------
-- Core Filtering Runtime Loop (Triggered periodically or on events)
-------------------------------------------------------------------------------
local function process_active_filters()
    if not filtering_enabled or not sft_data or not sft_data.filters then return end
    
    local now_sec = get_current_time_sec()
    if now_sec <= 0 then return end

    local inside_mute_zone = false

    for _, filter in ipairs(sft_data.filters) do
        if now_sec >= filter.start_time and now_sec < filter.end_time then
            if filter.action == "skip" then
                -- Skip ahead to end_time (+ 0.1s buffer to avoid re-trigger loop)
                seek_to_sec(filter.end_time + 0.1)
                if w_status then
                    w_status:set_text("Skipped: " .. (filter.description or filter.category))
                end
                return
            elseif filter.action == "mute" then
                inside_mute_zone = true
            end
        end
    end

    -- Manage Mute State
    if inside_mute_zone and not muted_by_sft then
        vlc.volume.mute()
        muted_by_sft = true
        if w_status then w_status:set_text("Muted: Sensitive audio") end
    elseif not inside_mute_zone and muted_by_sft then
        vlc.volume.mute() -- toggle unmute
        muted_by_sft = false
        if w_status then w_status:set_text("Unmuted audio") end
    end
end

-------------------------------------------------------------------------------
-- GUI Event Handlers
-------------------------------------------------------------------------------
local function click_mark_in()
    local t = get_current_time_sec()
    w_in_time:set_text(string.format("%.2f", t))
    if w_status then w_status:set_text("Marked IN: " .. format_time(t)) end
end

local function click_mark_out()
    local t = get_current_time_sec()
    w_out_time:set_text(string.format("%.2f", t))
    if w_status then w_status:set_text("Marked OUT: " .. format_time(t)) end
end

local function click_add_filter()
    local in_t = tonumber(w_in_time:get_text())
    local out_t = tonumber(w_out_time:get_text())

    if not in_t or not out_t or in_t >= out_t then
        if w_status then w_status:set_text("Error: IN time must be less than OUT time!") end
        return
    end

    local action_val = "skip"
    if w_action_dropdown:get_value() == 2 then action_val = "mute" end

    local categories = {"gore", "violence", "nudity", "profanity", "other"}
    local cat_val = categories[w_category_dropdown:get_value()] or "other"

    local new_filter = {
        id = #sft_data.filters + 1,
        start_time = in_t,
        end_time = out_t,
        action = action_val,
        category = cat_val,
        description = w_desc:get_text() or ""
    }

    table.insert(sft_data.filters, new_filter)
    update_filter_list_display()
    if w_status then w_status:set_text("Added filter #" .. new_filter.id) end
end

local function click_load_sft()
    local filepath = w_sft_path:get_text()
    if filepath and filepath ~= "" then
        load_sft_file(filepath)
    else
        if w_status then w_status:set_text("Please enter a valid .sft path!") end
    end
end

local function click_export_sft()
    local filepath = w_sft_path:get_text()
    if not filepath or filepath == "" then
        filepath = "movie.sft"
        w_sft_path:set_text(filepath)
    end
    save_sft_file(filepath)
end

local function click_clear_filters()
    sft_data.filters = {}
    update_filter_list_display()
    if w_status then w_status:set_text("Cleared all filter markers.") end
end

local function toggle_filtering_state()
    filtering_enabled = not filtering_enabled
    if w_status then
        w_status:set_text("Filtering: " .. (filtering_enabled and "ENABLED" or "DISABLED"))
    end
end

-------------------------------------------------------------------------------
-- VLC Extension Lifecycle Callbacks
-------------------------------------------------------------------------------
function menu()
    return {"Open Safety Filter Manager"}
end

function trigger_menu(id)
    if id == 1 then
        activate()
    end
end

function activate()
    if dialog then
        dialog:show()
        return
    end

    dialog = vlc.dialog("Safety Filter (.sft) Manager")

    -- Row 1: File Loading & Status
    dialog:add_label("<b>.sft File Path:</b>", 1, 1, 1, 1)
    w_sft_path = dialog:add_input("example_movie.sft", 2, 1, 3, 1)
    dialog:add_button("Load .sft", click_load_sft, 5, 1, 1, 1)

    -- Row 2: In / Out Markers
    dialog:add_button("Mark IN", click_mark_in, 1, 2, 1, 1)
    w_in_time = dialog:add_input("0.00", 2, 2, 1, 1)
    dialog:add_button("Mark OUT", click_mark_out, 3, 2, 1, 1)
    w_out_time = dialog:add_input("0.00", 4, 2, 1, 1)

    -- Row 3: Action & Category Selection
    dialog:add_label("<b>Action:</b>", 1, 3, 1, 1)
    w_action_dropdown = dialog:add_dropdown(2, 3, 1, 1)
    w_action_dropdown:add_value("Skip", 1)
    w_action_dropdown:add_value("Mute", 2)

    dialog:add_label("<b>Category:</b>", 3, 3, 1, 1)
    w_category_dropdown = dialog:add_dropdown(4, 3, 1, 1)
    w_category_dropdown:add_value("Gore", 1)
    w_category_dropdown:add_value("Violence", 2)
    w_category_dropdown:add_value("Nudity", 3)
    w_category_dropdown:add_value("Profanity", 4)
    w_category_dropdown:add_value("Other", 5)

    -- Row 4: Description & Add Button
    dialog:add_label("<b>Description:</b>", 1, 4, 1, 1)
    w_desc = dialog:add_input("Filter description", 2, 4, 3, 1)
    dialog:add_button("+ Add Filter", click_add_filter, 5, 4, 1, 1)

    -- Row 5: Filter List Box
    w_filter_list = dialog:add_label("(No filter segments added yet)", 1, 5, 5, 3)

    -- Row 6: Export & Clear Buttons
    dialog:add_button("Export .sft", click_export_sft, 1, 8, 2, 1)
    dialog:add_button("Clear All", click_clear_filters, 3, 8, 1, 1)
    dialog:add_button("Toggle Filtering", toggle_filtering_state, 4, 8, 2, 1)

    -- Row 7: Status Bar
    w_status = dialog:add_label("Ready. Play video and mark IN/OUT points.", 1, 9, 5, 1)

    update_filter_list_display()
    dialog:show()
end

function deactivate()
    if muted_by_sft then
        vlc.volume.mute()
        muted_by_sft = false
    end
    if dialog then
        dialog:delete()
        dialog = nil
    end
end

function close()
    deactivate()
end

function input_changed()
    -- When a new video opens, check for a matching .sft file in the same directory
    local input = vlc.object.input()
    if not input then return end

    local item = vlc.input.item()
    if item then
        local uri = item:uri()
        if uri and (uri:sub(-4) == ".mp4" or uri:sub(-4) == ".mkv" or uri:sub(-4) == ".avi") then
            -- Attempt auto-load of matching .sft path
            local sft_uri = uri:sub(1, -5) .. ".sft"
            -- Convert file:// URI to local filepath
            local filepath = vlc.strings.decode_uri(sft_uri:gsub("^file://", ""))
            load_sft_file(filepath)
        end
    end
end

-- Extension update hook called continuously by VLC while dialog is active
function update()
    process_active_filters()
end
