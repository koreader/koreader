-- typed on my Commodore 64 ;)
local Device = require("device")

-- The hotkey shortcuts defined here are only the defaults. The user can
-- change them at any time using the hotkey shortcuts configuration menu.
-- NOTE: The combinations that contain the tag ** keep nil, already assigned outside this plugin **
--       should never be assigned to any action in this plugin, because they are already assigned
--       to events in core. If you assign them to actions in this plugin, those actions will be in 
--       conflict with the existing ones and hell will break loose.
return {
    hotkeyshortcuts_fm = {
        modifier_plus_up                 = nil,
        modifier_plus_down               = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_left               = nil,
        modifier_plus_right              = nil,
        modifier_plus_left_page_back     = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_left_page_forward  = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_right_page_back    = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_right_page_forward = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_back               = {open_previous_document = true,},
        modifier_plus_home               = Device:hasWifiToggle() and {toggle_wifi = true,} or {},
        modifier_plus_press              = nil, -- keep nil, already assigned outside this plugin.
        modifier_plus_menu               = nil, -- keep nil, already assigned outside this plugin.
        -- optional, user can select whether or not to enable it.
        press = nil, -- keep nil, already assigned outside this plugin.
        -- alt
        alt_plus_up                 = nil,
        alt_plus_down               = nil,
        alt_plus_left               = nil,
        alt_plus_right              = nil,
        alt_plus_left_page_back     = nil,
        alt_plus_left_page_forward  = nil,
        alt_plus_right_page_back    = nil,
        alt_plus_right_page_forward = nil,
        alt_plus_back               = nil,
        alt_plus_home               = nil,
        alt_plus_press              = nil,
        alt_plus_menu               = nil,
        -- alt+alphabet
        alt_plus_a = nil,
        alt_plus_b = nil,
        alt_plus_c = nil,
        alt_plus_d = {dictionary_lookup = true,},
        alt_plus_e = nil,
        alt_plus_f = {file_search = true,},
        alt_plus_g = nil,
        alt_plus_h = nil,
        alt_plus_i = nil,
        alt_plus_j = nil,
        alt_plus_k = nil,
        alt_plus_l = nil,
        alt_plus_m = nil,
        alt_plus_n = nil,
        alt_plus_o = nil,
        alt_plus_p = nil,
        alt_plus_q = nil,
        alt_plus_r = nil,
        alt_plus_s = nil,
        alt_plus_t = nil,
        alt_plus_u = nil,
        alt_plus_v = nil,
        alt_plus_w = {wikipedia_lookup = true,},
        alt_plus_x = nil,
        alt_plus_y = nil,
        alt_plus_z = nil,
    },
    hotkeyshortcuts_reader = {
        modifier_plus_up                 = {toc = true,},
        modifier_plus_down               = {book_map = true,},
        modifier_plus_left               = {bookmarks = true,},
        modifier_plus_right              = {toggle_bookmark = true,},
        modifier_plus_left_page_back     = not Device:isTouchDevice() and {select_prev_page_link = true,} or {},
        modifier_plus_left_page_forward  = not Device:isTouchDevice() and {select_next_page_link = true,} or {},
        modifier_plus_right_page_back    = not Device:isTouchDevice() and {select_prev_page_link = true,} or {},
        modifier_plus_right_page_forward = not Device:isTouchDevice() and {select_next_page_link = true,} or {},
        modifier_plus_back               = {open_previous_document = true,},
        modifier_plus_home               = Device:hasWifiToggle() and {toggle_wifi = true,} or {},
        modifier_plus_press              = {full_refresh = true,},
        modifier_plus_menu               = nil, -- keep nil, already assigned outside this plugin.
        -- optional, user can select whether or not to enable it.
        press = {show_config_menu = true,},
        -- alt
        alt_plus_up                 = nil,
        alt_plus_down               = nil,
        alt_plus_left               = nil,
        alt_plus_right              = nil,
        alt_plus_left_page_forward  = nil,
        alt_plus_left_page_back     = nil,
        alt_plus_right_page_forward = nil,
        alt_plus_right_page_back    = nil,
        alt_plus_back               = nil,
        alt_plus_home               = nil,
        alt_plus_press              = nil,
        alt_plus_menu               = nil,
        -- alt+alphabet
        alt_plus_a = nil,
        alt_plus_b = nil,
        alt_plus_c = nil,
        alt_plus_d = {dictionary_lookup = true,},
        alt_plus_e = nil,
        alt_plus_f = {file_search = true,},
        alt_plus_g = nil,
        alt_plus_h = nil,
        alt_plus_i = nil,
        alt_plus_j = nil,
        alt_plus_k = nil,
        alt_plus_l = nil,
        alt_plus_m = nil,
        alt_plus_n = nil,
        alt_plus_o = nil,
        alt_plus_p = nil,
        alt_plus_q = nil,
        alt_plus_r = nil,
        alt_plus_s = {fulltext_search = true,},
        alt_plus_t = nil,
        alt_plus_u = nil,
        alt_plus_v = nil,
        alt_plus_w = {wikipedia_lookup = true,},
        alt_plus_x = nil,
        alt_plus_y = nil,
        alt_plus_z = nil,
    },
}
