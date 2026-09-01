-- Unit test script for Safety Filter (.sft) JSON specification & parser

-- Load JSON logic
local function load_file(filename)
    local f = assert(io.open(filename, "r"))
    local content = f:read("*all")
    f:close()
    return content
end

-- Read sft_filter.lua to test the embedded JSON decoder/encoder
local lua_code = load_file("lua/extensions/sft_filter.lua")

-- Extract embedded JSON functions into a test sandbox
local test_fn, err = load(lua_code .. "\nreturn JSON", "test_sandbox", "t", _G)
if not test_fn then
    print("❌ Failed to compile sandbox: " .. tostring(err))
    os.exit(1)
end

local JSON = test_fn()

print("=========================================")
print("Running SFT JSON Parser & Validator Tests")
print("=========================================")

-- Test 1: Decode example_movie.sft
local example_sft_content = load_file("spec/example_movie.sft")
local data = JSON.decode(example_sft_content)

assert(data ~= nil, "JSON decode returned nil")
assert(data.sft_version == "1.0", "sft_version mismatch")
assert(data.metadata.title == "Example Sample Video", "Title mismatch")
assert(#data.filters == 2, "Expected 2 filters, got " .. #data.filters)
assert(data.filters[1].action == "skip", "Filter 1 action should be skip")
assert(data.filters[2].action == "mute", "Filter 2 action should be mute")
print("✅ Test 1 Passed: Successfully parsed spec/example_movie.sft")

-- Test 2: Encode table back to JSON string
local re_encoded = JSON.encode(data)
assert(re_encoded ~= nil and #re_encoded > 0, "JSON encode failed")
local data_reparsed = JSON.decode(re_encoded)
assert(data_reparsed.metadata.title == data.metadata.title, "Reparsed title mismatch")
assert(#data_reparsed.filters == 2, "Reparsed filters count mismatch")
print("✅ Test 2 Passed: JSON re-encoding and re-parsing match accurately")

print("=========================================")
print("All SFT unit tests passed successfully!")
print("=========================================")
