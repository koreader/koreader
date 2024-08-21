--[[
Kindle's kernel designates Alt+'QWERTYUIOP' as numerical values on kindle 3.
This map is intended to make shortcut writting more readable, for example Alt+W
would be: self.key_events = { Device.AltPlusQWER["W"] } instead of self.key_events = { "2" }
--]]

return {
    ["Q"] = {"1"}, ["W"] = {"2"},
    ["E"] = {"3"}, ["R"] = {"4"},
    ["T"] = {"5"}, ["Y"] = {"6"},
    ["U"] = {"7"}, ["I"] = {"8"},
    ["O"] = {"9"}, ["P"] = {"0"},
}
