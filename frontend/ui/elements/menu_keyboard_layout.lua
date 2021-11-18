local CheckButton = require("ui/widget/checkbutton")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local Language = require("ui/language")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")
local dbg = require("dbg")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local input_dialog, check_button_bold, check_button_border, check_button_compact

local function getActivatedKeyboards(compact)
    local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts", {})
    local activated_keyboards = {}
    for lang, dummy in FFIUtil.orderedPairs(VirtualKeyboard.lang_to_keyboard_layout) do
        if util.arrayContains(keyboard_layouts, lang) then
            if compact then
                table.insert(activated_keyboards, lang)
            else
                table.insert(activated_keyboards, Language:getLanguageName(lang))
            end
        end
    end
    return table.concat(activated_keyboards, ", ")
end

local sub_item_table = {
    {
        text_func = function()
            local activated_keyboards = getActivatedKeyboards()
            if activated_keyboards ~= "" then
                local item_text = string.format(_("Keyboard layout: %s"), activated_keyboards)

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
                if item_text_w >= Screen:getWidth()- 2*Size.padding.default - checked_widget:getSize().w then
                    item_text = string.format(_("Keyboard layout: %s"), _("many"))
                end

                return item_text
            else
                return _("Keyboard layout")
            end
        end,
        sub_item_table = {},
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
        text = _("Keyboard settings"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            input_dialog = require("ui/widget/inputdialog"):new{
                title = _("Keyboard font size"),
                input = tostring(G_reader_settings:readSetting("keyboard_key_font_size", VirtualKeyboard.default_label_size)),
                input_hint = "(16 - 30)",
                buttons = {
                    {
                        {
                            text = _("Close"),
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
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_bold:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_bold)
            check_button_border = CheckButton:new{
                text = _("with border"),
                checked = G_reader_settings:nilOrTrue("keyboard_key_border"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_border:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_border)
            check_button_compact = CheckButton:new{
                text = _("compact"),
                checked = G_reader_settings:isTrue("keyboard_key_compact"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_compact:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_compact)

            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    },
    {
        text = _("Layout-specific keyboard settings"),
        sub_item_table = {},
    }
}

for lang, keyboard_layout in FFIUtil.orderedPairs(VirtualKeyboard.lang_to_keyboard_layout) do
    table.insert(sub_item_table[1].sub_item_table, {
        text_func = function()
            local text = Language:getLanguageName(lang) .. " (" .. lang ..")"
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
                    UIManager:show(require("ui/widget/infomessage"):new{
                        text = _("Up to four layouts can be enabled."),
                        timeout = 2,
                    })
                    return
                end
            end
            G_reader_settings:saveSetting("keyboard_layouts", keyboard_layouts)
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("keyboard_layout_default", lang)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
    if VirtualKeyboard.lang_has_submenu[lang] then
        local keyboard = require("ui/data/keyboardlayouts/" .. keyboard_layout)
        if dbg.dassert(keyboard.genMenuItems ~= nil) then
            table.insert(sub_item_table[4].sub_item_table, {
                text = Language:getLanguageName(lang),
                sub_item_table = keyboard:genMenuItems(),
            })
        end
    end
end

return sub_item_table
