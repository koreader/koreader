local user_path = require("datastorage"):getDataDir() .. "/dictionaries.lua"
local ok, dicts = pcall(dofile, user_path)

local t = {}

table.insert(t, 1, { "Goldendict", "Goldendict", false, "goldendict" })

if jit.os == "OSX" then
    table.insert(t, 1, { "Apple", "AppleDict", false, "dict://" })
end

if ok then
    -- append user dictionaries to the bottom of the menu
    for k, v in pairs(dicts) do
        table.insert(t, #t + 1, v)
    end
end

return t

