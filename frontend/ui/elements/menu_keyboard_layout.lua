local CheckButton = require("ui/widget/checkbutton")
local FFIUtil = require("ffi/util")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Language = require("ui/language")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")
local _ = require("gettext")

local input_dialog, check_button_bold, check_button_border, check_button_compact

local sub_item_table = {
    {
        text = _("Keyboard layout"),
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
        text = _("Keyboard font size"),
        keep_menu_open = true,
        callback = function()
            input_dialog = require("ui/widget/inputdialog"):new{
                title = _("Keyboard font size"),
                input = tostring(G_reader_settings:readSetting("keyboard_key_font_size") or 22),
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
                                end
                            end,
                        },
                    },
                },
            }

            -- checkboxes
            check_button_bold = CheckButton:new{
                text = _("in bold"),
                checked = G_reader_settings:isTrue("keyboard_key_bold"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_bold:toggleCheck()
                end,
            }
            check_button_border = CheckButton:new{
                text = _("with border"),
                checked = G_reader_settings:nilOrTrue("keyboard_key_border"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_border:toggleCheck()
                end,
            }
            check_button_compact = CheckButton:new{
                text = _("compact"),
                checked = G_reader_settings:isTrue("keyboard_key_compact"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_compact:toggleCheck()
                end,
            }

            local checkbox_shift = math.floor((input_dialog.width - input_dialog._input_widget.width) / 2 + 0.5)
            local check_buttons = HorizontalGroup:new{
                HorizontalSpan:new{width = checkbox_shift},
                VerticalGroup:new{
                    align = "left",
                    check_button_bold,
                    check_button_border,
                    check_button_compact,
                },
            }

            -- insert check buttons before the regular buttons
            local nb_elements = #input_dialog.dialog_frame[1]
            table.insert(input_dialog.dialog_frame[1], nb_elements-1, check_buttons)

            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    },
}

local selected_layouts_count = 0
local _keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
for k, __ in FFIUtil.orderedPairs(VirtualKeyboard.lang_to_keyboard_layout) do
    if _keyboard_layouts[k] == true then
        selected_layouts_count = selected_layouts_count + 1
    end
    table.insert(sub_item_table[1].sub_item_table, {
        text_func = function()
            local text = Language:getLanguageName(k)
            if G_reader_settings:readSetting("keyboard_layout_default") == k then
                text = text .. "   ★"
            end
            return text
        end,
        checked_func = function()
            local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
            return keyboard_layouts[k] == true
        end,
        callback = function()
            local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
            if keyboard_layouts[k] == true then
                keyboard_layouts[k] = false
                selected_layouts_count = selected_layouts_count - 1
            else
                if selected_layouts_count < 4 then
                    keyboard_layouts[k] = true
                    selected_layouts_count = selected_layouts_count + 1
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
            G_reader_settings:saveSetting("keyboard_layout_default", k)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

return sub_item_table
