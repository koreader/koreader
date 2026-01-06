local android = require("android")

require("ffi/posix_h")

local ffi = require("ffi")
local C = ffi.C

-- check uri of the intent that starts this application
local file = android.getIntent()

if file ~= nil then
    android.LOGI("intent file path " .. file)
end

-- create fake command-line arguments
-- luacheck: ignore 121
if android.isDebuggable() then
    arg = {"-d", file}
else
    arg = {file}
end

local protected_modules = {
    ["_G"] = true,
    ["android"] = true, -- important, as we are on Android here
    ["bit"] = true,
    ["ffi"] = true,
--    ["ffi/*"] = true, -- will be checked below
    ["gettext"] = true,
    ["jit"] = true,
    ["package"] = true,
    ["lua-ljsqlite3/init"] = true,

}
for k, v in pairs(package.loaded) do
    protected_modules[k] = true
end

local KO_RC_RESTART=85
local crash_count = 0

while crash_count < 5 do
    -- force a clean start of the safemode module
    for k, _ in pairs(package.loaded) do
        if not protected_modules[k] and not k:find("^ffi/") then
            package.loaded[k] = nil
        end
    end

    C.setenv("CRASH_COUNT", tostring(crash_count), 1)

    local chunk, loadError = loadfile(android.dir.."/reader.lua") -- check syntax, don't actually run it

    if not chunk then
        android.LOGE("Syntax Error: " .. loadError)
    else
        local success, value = pcall(chunk) -- value stores error or return value

        if not success then
            crash_count = crash_count + 1
            android.LOGE("Runtime Crash: " .. value)
        elseif value == KO_RC_RESTART then
            crash_count = 0
            android.LOGI("Restart KOReader")
        else
            android.LOGI("Leave KOReader")
            break
        end
    end
end
