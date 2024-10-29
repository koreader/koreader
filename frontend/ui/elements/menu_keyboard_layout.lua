local CheckButton = require("ui/widget/checkbutton")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local Language = require("ui/language")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")
local Screen = Device.screen
local T = FFIUtil.template
local util = require("util")
local _ = require("gettext")

local input_dialog, check_button_bold, check_button_border, check_button_compact

local function getOrderedActivatedKeyboardLayouts()
    local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts", {})
    local activated_keyboards = {}
    for _, lang in ipairs(keyboard_layouts) do
        if VirtualKeyboard.lang_to_keyboard_layout[lang] then
            table.insert(activated_keyboards, lang)
        end
    end
    if #activated_keyboards == 0 then -- use default keyboard
        table.insert(activated_keyboards, VirtualKeyboard:getKeyboardLayout())
    elseif #activated_keyboards > 1 then
        table.sort(activated_keyboards)
    end
    return activated_keyboards
end

-- Returns a string with all selected keyboard layouts (comma separated) and
-- the count of the selectecd layouts.
-- If compact is set, only the abbreviations and the count are returned.
local function getActivatedKeyboardsStringCount(compact)
    local activated_keyboards = getOrderedActivatedKeyboardLayouts()
    if not compact then
        for i, lang in ipairs(activated_keyboards) do
            activated_keyboards[i] = Language:getLanguageName(lang)
        end
    end
    return table.concat(activated_keyboards, ", "), #activated_keyboards
end

local function genKeyboardLayoutsSubmenu()
    local item_table = {}
    for lang, keyboard_layout in FFIUtil.orderedPairs(VirtualKeyboard.lang_to_keyboard_layout) do
        table.insert(item_table, {
            text_func = function()
                local text = T("%1 (%2)", Language:getLanguageName(lang), lang:sub(1, 2))
                if G_reader_settings:readSetting("keyboard_layout_default") == lang then
                    text = text .. "   ★"
                end
                return text
            end,
            checked_func = function()
                local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts", {})
                return util.arrayContains(keyboard_layouts, lang)
            end,
            callback = function()
                local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts", {})
                local layout_index = util.arrayContains(keyboard_layouts, lang)
                if layout_index then
                    table.remove(keyboard_layouts, layout_index)
                else
                    if #keyboard_layouts < 4 then
                        table.insert(keyboard_layouts, lang)
                    else -- no more space in the 'globe' popup
                        UIManager:show(InfoMessage:new{
                            text = _("Up to four layouts can be enabled."),
                            timeout = 2,
                        })
                    end
                end
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("keyboard_layout_default", lang)
                touchmenu_instance:updateItems()
            end,
        })
    end
    return item_table
end

-- Generate the language specific settings menu on demand, and only for active layouts,
-- to avoid loading potentially complex/large data when the layout isn't enabled.
local function genLayoutSpecificSubmenu()
    local item_table = {}

    local activated_keyboards = getOrderedActivatedKeyboardLayouts()
    for _, lang in ipairs(activated_keyboards) do
        if VirtualKeyboard.lang_has_submenu[lang] then
            local keyboard_layout = VirtualKeyboard.lang_to_keyboard_layout[lang]
            local kb_pkg = "ui/data/keyboardlayouts/" .. keyboard_layout
            table.insert(item_table, {
                text = T("%1 (%2)", Language:getLanguageName(lang), lang),
                sub_item_table_func = function()
                    local keyboard = require(kb_pkg)
                    if keyboard.genMenuItems ~= nil then
                        return keyboard:genMenuItems()
                    else
                        return {
                            text = _("Not implemented"),
                        }
                    end
                end,
            })
        end
    end

    -- Be a little more user-friendly than an empty menu ;).
    if #item_table == 0 then
        table.insert(item_table, {
            text = _("Not available for any of your active layouts"),
        })
    end

    return item_table
end

local sub_item_table = {
    {
        text_func = function()
            local activated_keyboards, nb_keyboards = getActivatedKeyboardsStringCount()
            local item_text = T(_("Keyboard layouts: %1"), activated_keyboards)

            -- get width of text
            local tmp = TextWidget:new{
                text = item_text,
                face = Font:getFace("cfont"),
            }
            local item_text_w = tmp:getSize().w
            tmp:free()
            local checked_widget = CheckMark:new{ -- for layout, to :getSize()
                checked = true,
            }
            if item_text_w >= Screen:getWidth() - 2*Size.padding.default - checked_widget:getSize().w then
                item_text = T(_("Keyboard layouts (%1)"), nb_keyboards)
            end

            return item_text
        end,
        sub_item_table_func = genKeyboardLayoutsSubmenu,
    },
    {
        text = _("Layout-specific keyboard settings"),
        -- Lazy-loaded to avoid pinning potentially unnecessary data
        sub_item_table_func = genLayoutSpecificSubmenu,
    },
    {
        text = _("Remember last layout"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("keyboard_remember_layout")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("keyboard_remember_layout")
        end,
        separator = true,
    },
    {
        text = _("Keyboard appearance settings"),
        keep_menu_open = true,
        enabled_func = function()
            return G_reader_settings:nilOrTrue("virtual_keyboard_enabled")
        end,
        callback = function(touchmenu_instance)
            local InputDialog = require("ui/widget/inputdialog")
            input_dialog = InputDialog:new{
                title = _("Keyboard font size"),
                -- do not use input_type = "number" to see letters on the keyboard
                input = tostring(G_reader_settings:readSetting("keyboard_key_font_size", VirtualKeyboard.default_label_size)),
                input_hint = "(16 - 30)",
                buttons = {
                    {
                        {
                            text = _("Close"),
                            id = "close",
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = _("Apply"),
                            is_enter_default = true,
                            callback = function()
                                local font_size = tonumber(input_dialog:getInputText())
                                if font_size and font_size >= 16 and font_size <= 30 then
                                    G_reader_settings:saveSetting("keyboard_key_font_size", font_size)
                                    G_reader_settings:saveSetting("keyboard_key_bold", check_button_bold.checked)
                                    G_reader_settings:saveSetting("keyboard_key_border", check_button_border.checked)
                                    G_reader_settings:saveSetting("keyboard_key_compact", check_button_compact.checked)
                                    input_dialog._input_widget:onCloseKeyboard()
                                    input_dialog._input_widget:initKeyboard()
                                    input_dialog:onShowKeyboard()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end
                            end,
                        },
                    },
                },
            }

            check_button_bold = CheckButton:new{
                text = _("in bold"),
                checked = G_reader_settings:isTrue("keyboard_key_bold"),
                parent = input_dialog,
            }
            input_dialog:addWidget(check_button_bold)
            check_button_border = CheckButton:new{
                text = _("with border"),
                checked = G_reader_settings:nilOrTrue("keyboard_key_border"),
                parent = input_dialog,
            }
            input_dialog:addWidget(check_button_border)
            check_button_compact = CheckButton:new{
                text = _("compact"),
                checked = G_reader_settings:isTrue("keyboard_key_compact"),
                parent = input_dialog,
            }
            input_dialog:addWidget(check_button_compact)

            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    },
}
if Device:hasKeyboard() or Device:hasScreenKB() then
    -- we use same pos. 4 as below so we are always above "keyboard appearance settings"
    table.insert(sub_item_table, 4, {
        text = _("Show virtual keyboard"),
        help_text = _("Enable this setting to always display the virtual keyboard within a text input field. When a field is selected (in focus), you can temporarily toggle the keyboard on/off by pressing 'Shift' (or 'ScreenKB') + 'Home'."),
        checked_func = function()
            return G_reader_settings:nilOrTrue("virtual_keyboard_enabled")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("virtual_keyboard_enabled")
            if G_reader_settings:isFalse("virtual_keyboard_enabled") then
                local keyboard_infomessage
                if Device:hasScreenKB() then
                    keyboard_infomessage = _("When a text field is selected (in focus), you can temporarily bring up the virtual keyboard by pressing 'ScreenKB' + 'Home'.")
                else
                    keyboard_infomessage = _("When a text field is selected (in focus), you can temporarily bring up the virtual keyboard by pressing 'Shift' + 'Home'.")
                end
                UIManager:show(InfoMessage:new{
                    text = keyboard_infomessage
                })
            end
        end,
    })
end
if Device:isTouchDevice() then
    -- same pos. 4 as above so if both conditions are met we are above "Show virtual keyboard"
    table.insert(sub_item_table, 4, {
        text = _("Swipe to input additional characters"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("keyboard_swipes_enabled")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("keyboard_swipes_enabled")
        end,
    })
end

return sub_item_table
