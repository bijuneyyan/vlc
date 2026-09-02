--[[
  Safety Filter (.sft) — Background Interface Script for VLC 3.0.x
  
  Architecture modeled after VLC's subtitle auto-loading:
    - Place "movie.sft" next to "movie.mp4" (same folder, same base name)
    - This script auto-detects the matching .sft file whenever a new video plays
    - No global config, no state files — each video gets its own filters
  
  Polling at 50ms (20Hz) — tighter than one frame at 24fps (~42ms).
  VLC's subtitle system achieves exact timing via the C decoder pipeline,
  which Lua cannot access. 50ms worst-case latency is imperceptible.
  
  Install: ~/Library/Application Support/org.videolan.vlc/lua/intf/sft_looper.lua
  Enable:  VLC Preferences > Show All > Interface > Main interfaces
           Extra interface modules: luaintf
           Main interfaces > Lua > Lua interface: sft_looper
--]]

-------------------------------------------------------------------------------
-- Minimal JSON decoder
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
local filters = {}           -- current active filter list
local current_video_uri = "" -- URI of the video we loaded filters for
local muted_by_sft = false

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function uri_to_filepath(uri)
    if not uri then return nil end
    -- Remove file:// prefix
    local path = uri:gsub("^file://", "")
    -- URL-decode percent-encoded characters (%20 -> space, etc.)
    path = path:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return path
end

local function find_sft_for_video(video_uri)
    local filepath = uri_to_filepath(video_uri)
    if not filepath then return nil end

    -- Strip the video extension and try .sft
    local base = filepath:match("(.+)%.[^%.]+$")
    if not base then return nil end

    local sft_path = base .. ".sft"
    local f = io.open(sft_path, "r")
    if f then
        f:close()
        return sft_path
    end
    return nil
end

local function load_filters(sft_path)
    local f = io.open(sft_path, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()

    local decoded = JSON.decode(content)
    if not decoded or not decoded.filters then return {} end

    -- Sort by start_time for efficient early-exit during playback
    local sorted = decoded.filters
    table.sort(sorted, function(a, b) return a.start_time < b.start_time end)
    return sorted
end

local function get_current_uri()
    local ok, item = pcall(function() return vlc.input.item() end)
    if ok and item then
        local ok2, uri = pcall(function() return item:uri() end)
        if ok2 and uri then return uri end
    end
    return nil
end

local function get_time_seconds()
    local input = vlc.object.input()
    if not input then return nil end

    local ok, val = pcall(vlc.var.get, input, "time")
    if ok and val and type(val) == "number" then
        -- VLC 3.x returns microseconds (values > 100000)
        if val > 100000 then
            return val / 1000000.0
        elseif val >= 0 then
            return val
        end
    end

    -- Fallback: position * length
    local ok_p, pos = pcall(vlc.var.get, input, "position")
    local ok_l, len = pcall(vlc.var.get, input, "length")
    if ok_p and ok_l and pos and len
       and type(pos) == "number" and type(len) == "number" then
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

    -- Primary: seek by position fraction (most reliable on macOS VLC 3.x)
    if total_sec > 0 then
        local frac = target_sec / total_sec
        if frac >= 0 and frac <= 1.0 then
            pcall(vlc.var.set, input, "position", frac)
        end
    end

    -- Secondary: seek by absolute time
    if raw_len > 100000 then
        pcall(vlc.var.set, input, "time", math.floor(target_sec * 1000000))
    else
        pcall(vlc.var.set, input, "time", target_sec)
    end
end

local function is_filtering_enabled()
    local home = os.getenv("HOME") or "/tmp"
    local f = io.open(home .. "/Library/Application Support/org.videolan.vlc/lua/extensions/userdata/sft_disabled.flag", "r")
    if f then
        f:close()
        return false
    end
    return true
end

local function set_mute(should_mute)
    if should_mute and not muted_by_sft then
        pcall(function() vlc.volume.set(0) end)
        muted_by_sft = true
        vlc.msg.info("[SFT] MUTED")
    elseif not should_mute and muted_by_sft then
        pcall(function() vlc.volume.set(256) end)
        muted_by_sft = false
        vlc.msg.info("[SFT] UNMUTED")
    end
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------
vlc.msg.info("[SFT] Safety Filter background monitor started (50ms / 20Hz)")

local tick = 0                 -- counter for periodic re-scan
local RESCAN_INTERVAL = 40     -- re-check .sft file every 40 ticks = ~2 seconds
local current_sft_path = ""    -- path of the currently loaded .sft file

while true do
    local ok, err = pcall(function()

        local uri = get_current_uri()

        -- 1. On video change: reset everything
        if uri and uri ~= current_video_uri then
            current_video_uri = uri
            current_sft_path = ""
            filters = {}
            tick = RESCAN_INTERVAL  -- force immediate scan
            if muted_by_sft then set_mute(false) end
            vlc.msg.info("[SFT] New video: " .. uri)
        end

        -- 2. Periodic re-scan for .sft file (every ~2 seconds)
        --    Detects: file added, file removed, file modified
        if uri and tick >= RESCAN_INTERVAL then
            tick = 0

            local sft_path = find_sft_for_video(uri)
            if sft_path and sft_path ~= current_sft_path then
                -- .sft file appeared or changed
                filters = load_filters(sft_path)
                current_sft_path = sft_path
                vlc.msg.info("[SFT] Loaded " .. #filters .. " filter(s) from: " .. sft_path)
            elseif sft_path and sft_path == current_sft_path then
                -- Same file — reload in case contents changed
                local new_filters = load_filters(sft_path)
                if #new_filters ~= #filters then
                    filters = new_filters
                    vlc.msg.info("[SFT] Reloaded " .. #filters .. " filter(s) from: " .. sft_path)
                end
            elseif not sft_path and current_sft_path ~= "" then
                -- .sft file was removed
                filters = {}
                current_sft_path = ""
                if muted_by_sft then set_mute(false) end
                vlc.msg.info("[SFT] .sft file removed — filtering OFF")
            end
        end
        tick = tick + 1

        -- 3. Apply filters if enabled and loaded
        local enabled = is_filtering_enabled()
        if enabled and #filters > 0 then
            local now = get_time_seconds()
            if now and now >= 0 then
                local inside_mute = false

                for _, f in ipairs(filters) do
                    -- Filters are sorted by start_time — early exit
                    if f.start_time > now + 1 then break end

                    if now >= f.start_time and now < f.end_time then
                        if f.action == "skip" then
                            vlc.msg.info("[SFT] SKIP at " ..
                                string.format("%.2f", now) .. "s -> " ..
                                string.format("%.2f", f.end_time + 0.1) .. "s")
                            seek_to(f.end_time + 0.1)
                            break
                        elseif f.action == "mute" then
                            inside_mute = true
                        end
                    end
                end

                set_mute(inside_mute)
            end
        elseif not enabled and muted_by_sft then
            set_mute(false)
        end

        -- 4. Sleep 50ms (50,000 μs)
        vlc.misc.mwait(vlc.misc.mdate() + 50000)
    end)

    if not ok then break end
end

-- Cleanup
if muted_by_sft then
    pcall(function() vlc.volume.set(256) end)
end
vlc.msg.info("[SFT] Safety Filter background monitor stopped.")

