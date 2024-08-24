--[[
event map for Kindle devices on FW 3.x & 4.x
--]]

return {
    -- NOTE: Although Kindle 3 does not have numerical keys, these key codes are still registered when pressing 'Alt'+'QWERTYUIOP'
    --       So, as far as kindle is concerned Alt+Q = 1, Alt+W = 2, ... Alt+P = 0
    [2]  = "1", [3]  = "2", [4]  = "3", [5]  = "4", [6]  = "5", [7]  = "6", [8]  = "7", [9]  = "8", [10] = "9", [11] = "0",
    -- Physical keys
    [16] = "Q", [17] = "W", [18] = "E", [19] = "R", [20] = "T", [21] = "Y", [22] = "U", [23] = "I", [24] = "O", [25] = "P",
    [30] = "A", [31] = "S", [32] = "D", [33] = "F", [34] = "G", [35] = "H", [36] = "J", [37] = "K", [38] = "L", [14] = "Del",
    [44] = "Z", [45] = "X", [46] = "C", [47] = "V", [48] = "B", [49] = "N", [50] = "M", [52] = ".",

    [28] = "Press", -- K3 (Enter)
    [29] = "ScreenKB", -- K4
    [42] = "Shift", -- K3
    [56] = "Alt", -- K3
    [57] = " ", -- K3
    [102] = "Home",
    [103] = "Up",
    [104] = "LPgFwd",
    [105] = "Left",
    [106] = "Right",
    [108] = "Down",
    [109] = "RPgBack",
    [126] = "Sym", -- K3
    [139] = "Menu",
    [158] = "Back",
    [190] = "AA", -- K3
    [191] = "RPgFwd",
    [193] = "LPgBack",
    [194] = "Press",
}
