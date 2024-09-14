-- Start with the english keyboard layout
local th_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

-- Swap the four AZWQ keys (only in the lowercase and
-- uppercase letters layouts) to change it from QWERTY to AZERTY
local keys = th_keyboard.keys

keys[1][7][3] = "๗"
keys[1][8][3] = "๘"
keys[1][9][3] = "๙"

table.insert(keys[1], {
    {"ึ", north="ิ", alt_label="ิ"},
    {"ิ", north="ึ", alt_label="ึ", south="ู",},
    "๛", "๛"
})

keys[2][1][1] = { "ถ", north="ต", alt_label="ต" }
keys[2][1][2] = { "ต", north="ถ", alt_label="ถ" }
keys[2][2][1] = { "ภ", north="ค", alt_label="ค" }
keys[2][2][2] = { "ค", north="ภ", alt_label="ภ" }
keys[2][3][1] = { "ำ", north="พ", alt_label="พ" }
keys[2][3][2] = { "พ", north="ำ", alt_label="ำ" }
keys[2][4][1] = { "โ", north="ะ", alt_label="ะ" }
keys[2][4][2] = { "ะ", north="โ", alt_label="โ" }
keys[2][5][1] = { "ฦ", north="ข", alt_label="ข" }
keys[2][5][2] = { "ข", north="ฦ", alt_label="ฦ" }
keys[2][6][1] = { "ฎ", north="ว", alt_label="ว" }
keys[2][6][2] = { "ว", north="ฎ", alt_label="ฎ" }
keys[2][7][1] = { "ซ", north="ร", alt_label="ร" }
keys[2][7][2] = { "ร", north="ซ", alt_label="ซ" }
keys[2][7][3] = "๔"
keys[2][8][1] = { "ณ", north="น", alt_label="น" }
keys[2][8][2] = { "น", north="ณ", alt_label="ณ" }
keys[2][8][3] = "๕"
keys[2][9][1] = { "ญ", north="ย", alt_label="ย" }
keys[2][9][2] = { "ย", north="ญ", alt_label="ญ" }
keys[2][9][3] = "๖"
keys[2][10][1] = { "ฯ", north="ไ", alt_label="ไ" }
keys[2][10][2] = { "ไ", north="ฯ", alt_label="ฯ" }
table.insert(keys[2],{
    {"๏", north="ใ", alt_label="ใ"},
    {"ใ", north="๏", alt_label="๏"},
    "฿","฿"
})

keys[3][1][1] = { "ฤ", north="ห", alt_label="ห" }
keys[3][1][2] = { "ห", north="ฤ", alt_label="ฤ" }
keys[3][2][1] = { "ฟ", north="ก", alt_label="ก" }
keys[3][2][2] = { "ก", north="ฟ", alt_label="ฟ" }
keys[3][3][1] = { "ฆ", north="ด", alt_label="ด" }
keys[3][3][2] = { "ด", north="ฆ", alt_label="ฆ" }
keys[3][4][1] = { "ฏ", north="เ", alt_label="เ" }
keys[3][4][2] = { "เ", north="ฏ", alt_label="ฏ" }
keys[3][5][1] = { "ฌ", north="จ", alt_label="จ" }
keys[3][5][2] = { "จ", north="ฌ", alt_label="ฌ" }
keys[3][6][1] = { "ษ", north="บ", alt_label="บ" }
keys[3][6][2] = { "บ", north="ษ", alt_label="ษ" }
keys[3][7][1] = { "ศ", north="า", alt_label="า" }
keys[3][7][2] = { "า", north="ศ", alt_label="ศ" }
keys[3][7][3] = "๑"
keys[3][8][1] = { "ๆ", north="ล", alt_label="ล" }
keys[3][8][2] = { "ล", north="ๆ", alt_label="ๆ" }
keys[3][8][3] = "๒"
keys[3][9][1] = { "ฬ", north="ส", alt_label="ส" }
keys[3][9][2] = { "ส", north="ฬ", alt_label="ฬ" }
keys[3][9][3] = "๓"
keys[3][10][1] = { "ฺ", north="แ", alt_label="แ" }
keys[3][10][2] = { "แ", north="ฺ", alt_label="ฺ" }
table.insert(keys[3],{
    {"ื", north="ั", alt_label="ั"},
    {"ั", north="ื", alt_label="ื", south="็", west="๊"},
    "๎","๎"
})

keys[4][2][1] = { "ฑ", north="ผ", alt_label="ผ" }
keys[4][2][2] = { "ผ", north="ฑ", alt_label="ฑ" }
keys[4][3][1] = { "ธ", north="ป", alt_label="ป" }
keys[4][3][2] = { "ป", north="ธ", alt_label="ธ" }
keys[4][4][1] = { "ฉ", north="อ", alt_label="อ" }
keys[4][4][2] = { "อ", north="ฉ", alt_label="ฉ" }
keys[4][5][1] = { "ฐ", north="ง", alt_label="ง" }
keys[4][5][2] = { "ง", north="ฐ", alt_label="ฐ" }
keys[4][6][1] = { "ฮ", north="ช", alt_label="ช" }
keys[4][6][2] = { "ช", north="ฮ", alt_label="ฮ" }
keys[4][6][3] = "๐"
keys[4][7][1] = { "ฒ", north="ท", alt_label="ท" }
keys[4][7][2] = { "ท", north="ฒ", alt_label="ฒ" }
keys[4][8][1] = { "ฝ", north="ม", alt_label="ม" }
keys[4][8][2] = { "ม", north="ฝ", alt_label="ฝ" }
table.insert(keys[4], 9, {
    {"์", north="้", alt_label="้"},
    {"้", north="์", alt_label="์", south="ุ", west="๋", east="ํ"},
    "๚","๚"
})

table.insert(keys[5],7, {
    {"ี", north="่", alt_label="่"},
    {"่", north="ี", alt_label="ี"},
    "/","/"
})

-- Remove the "space" string
keys[5][4].label = ""

return th_keyboard
