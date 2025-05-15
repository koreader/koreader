return {
    [102] = "Home",
    [105] = "LPgBack",
    [106] = "RPgFwd",
    [116] = "Power",
    [143] = "Power",
}
-- 116 is issued when the device gets to sleep, 143 when it's waked up. Both should be handled as "Power" to make waking up work without launcher (e.g. rMPP)
