--[[
  Safety Filter (.sft) — Background Interface Script for VLC
  
  This intf script runs a high-frequency polling loop (every 50ms / 20Hz)
  while VLC is open. It reads the active .sft file path written by the
  extension (sft_filter.lua), loads the filter definitions, and monitors
  playback position with near-frame-accurate precision.
  
  When the current playback time enters a "skip" segment, it seeks past it.
  When it enters a "mute" segment, it mutes audio (and unmutes when leaving).
  
  Why 50ms? VLC subtitles achieve frame accuracy via the C decoder pipeline,
  which Lua cannot hook into. 50ms polling (20 checks/sec) is tighter than
  one frame at 24fps (~42ms) and imperceptible to humans (~150ms blink).
  
  Install path (macOS):
    ~/Library/Application Support/org.videolan.vlc/lua/intf/sft_looper.lua
  
  Enable by launching VLC with:
    /Applications/VLC.app/Contents/MacOS/VLC --extraintf=luaintf --lua-intf=sft_looper
  Or set it permanently in VLC Preferences > All > Interface > Extra interface modules.
--]]

-------------------------------------------------------------------------------
-- Minimal JSON decoder (only needs decode for reading .sft files)
-------------------------------------------------------------------------------
local JSON = {}

function JSON.decode(str)
    if not str or str == "" then return nil end
    local pos = 1

    local function skip_ws()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else break end
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
            if c:find("[0-9%.eE%+%-]") then pos = pos + 1
            else break end
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
local sft_data = nil
local loaded_path = ""
local muted_by_sft = false
local last_check_path = ""

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function get_active_sft_path()
    local home = os.getenv("HOME") or "/tmp"
    local path_file = home .. "/Library/Application Support/org.videolan.vlc/lua/extensions/userdata/sft_active.txt"
    local f = io.open(path_file, "r")
    if not f then return nil end
    local p = f:read("*l")
    f:close()
    if p and p ~= "" then return p end
    return nil
end

local function load_sft_file(path)
    if not path or path == "" then return false end
    local f = io.open(path, "r")
    if not f then return false end
    local content = f:read("*all")
    f:close()
    local decoded = JSON.decode(content)
    if not decoded or not decoded.filters then return false end
    sft_data = decoded
    loaded_path = path
    vlc.msg.info("[SFT Looper] Loaded " .. #sft_data.filters .. " filters from: " .. path)
    return true
end

local function get_time_seconds()
    local input = vlc.object.input()
    if not input then return nil end

    local ok, val = pcall(vlc.var.get, input, "time")
    if ok and val and type(val) == "number" then
        -- VLC 3.x returns microseconds
        if val > 100000 then
            return val / 1000000.0
        elseif val >= 0 then
            return val
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

    return nil
end

local function seek_to(target_sec)
    local input = vlc.object.input()
    if not input then return end

    local ok_l, raw_len = pcall(vlc.var.get, input, "length")
    if not ok_l or not raw_len then return end

    local total_sec = (raw_len > 100000) and (raw_len / 1000000.0) or raw_len

    -- Primary: seek by position fraction (most reliable on macOS)
    if total_sec > 0 then
        local frac = target_sec / total_sec
        if frac >= 0 and frac <= 1.0 then
            pcall(vlc.var.set, input, "position", frac)
        end
    end

    -- Secondary: seek by time
    if raw_len > 100000 then
        pcall(vlc.var.set, input, "time", math.floor(target_sec * 1000000))
    else
        pcall(vlc.var.set, input, "time", target_sec)
    end
end

local function set_mute(should_mute)
    if should_mute and not muted_by_sft then
        pcall(function() vlc.volume.set(0) end)
        muted_by_sft = true
        vlc.msg.info("[SFT Looper] MUTED audio")
    elseif not should_mute and muted_by_sft then
        pcall(function() vlc.volume.set(256) end)  -- 256 = 100% volume
        muted_by_sft = false
        vlc.msg.info("[SFT Looper] UNMUTED audio")
    end
end

-------------------------------------------------------------------------------
-- Main polling loop
-------------------------------------------------------------------------------
vlc.msg.info("[SFT Looper] Safety Filter background monitor started.")

-- VLC 3.0.x does not have vlc.misc.should_die().
-- The intf script is terminated automatically when VLC exits.
-- We wrap the loop body in pcall so any error during shutdown is silent.
while true do
    local ok, err = pcall(function()
        -- Check if the active .sft path has changed
        local active_path = get_active_sft_path()
        if active_path and active_path ~= loaded_path then
            load_sft_file(active_path)
        end

        -- Only process if we have filters and media is playing
        if sft_data and sft_data.filters and #sft_data.filters > 0 then
            local now = get_time_seconds()
            if now and now >= 0 then
                local inside_mute = false

                for _, filter in ipairs(sft_data.filters) do
                    if now >= filter.start_time and now < filter.end_time then
                        if filter.action == "skip" then
                            vlc.msg.info("[SFT Looper] SKIP triggered at " ..
                                string.format("%.2f", now) .. "s -> seeking to " ..
                                string.format("%.2f", filter.end_time + 0.2) .. "s")
                            seek_to(filter.end_time + 0.2)
                            break
                        elseif filter.action == "mute" then
                            inside_mute = true
                        end
                    end
                end

                set_mute(inside_mute)
            end
        end

        -- Sleep 50ms (50,000 μs) — 20Hz, tighter than 24fps
        vlc.misc.mwait(vlc.misc.mdate() + 50000)
    end)

    if not ok then
        -- VLC is shutting down or an error occurred — exit loop
        break
    end
end

-- Cleanup: unmute if we muted
if muted_by_sft then
    pcall(function() vlc.volume.set(256) end)
end

vlc.msg.info("[SFT Looper] Safety Filter background monitor stopped.")

