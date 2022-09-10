local android_eventmap = require("device/android/event_map")
android_eventmap[21] = "LPgBack" -- changed for Tolino Buttons (up key)
android_eventmap[22] = "LPgFwd" -- changed for Tolino Buttons (down key)

return android_eventmap
