local cs_keyboard = dofile("frontend/ui/data/keyboardlayouts/sk_keyboard.lua")

local keys = cs_keyboard.keys

keys[1][2][1] = {
    "2",
    north = "ě",
    northeast = "Ě",
    east = "~",
    southeast = "/",
    south = "@",
    southwest = "https://",
    west = "http://",
    northwest = "Ĺ",
    alt_label = "ě",
}
keys[1][2][2] = {
    "ě",
    north = "2",
    northeast = "Ě",
    east = "~",
    southeast = "/",
    south = "@",
    southwest = "https://",
    west = "http://",
    northwest = "ĺ",
    alt_label = "2",
}

keys[1][5][1] = {
    "5",
    north = "ř",
    northeast = "Ř",
    east = "¾",
    southeast = "‱",
    south = "%",
    southwest = "‰",
    west = "⅔",
    northwest = "Ŕ",
    alt_label = "ř",
}
keys[1][5][2] = {
    "ř",
    north = "5",
    northeast = "Ř",
    east = "¼",
    southeast = "‱",
    south = "%",
    southwest = "‰",
    west = "½",
    northwest = "ŕ",
    alt_label = "5",
}

keys[5][4].label = "mezera"

return cs_keyboard
