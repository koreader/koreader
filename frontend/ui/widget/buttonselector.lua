local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")

local ButtonSelector = ButtonDialog:extend{
    multi_choice = nil, 
    current_value = nil, -- value; or for multi_choice: hash table { value_key = true }
    values = nil, -- array { { value_text, value_key } } - buttons in order
    bg_colors = nil, -- array { color }, corresponding to values
    keep_open_on_apply = nil,
    width_factor = 0.4,
}

function ButtonSelector:init()
    local curr_values = self.multi_choice and {}
    local no_refresh_checkmark = not self.multi_choice and not self.keep_open_on_apply

    self.buttons = {}
    for i, v in ipairs(self.values) do
        local value_text, value_key = unpack(v)
        if self.multi_choice then
            -- no current_value means no filter, i.e. all selected
            curr_values[value_key] = not self.current_value or self.current_value[value_key]
        end
        self.buttons[i] = {{
            id = value_key,
            text = value_text,
            menu_style = true,
            background = self.bg_colors and self.bg_colors[i],
            checked_func = function()
                if self.multi_choice then
                    return curr_values[value_key]
                else
                    return value_key == self.current_value
                end
            end,
            no_refresh_checkmark = no_refresh_checkmark,
            callback = function()
                if self.multi_choice then
                    curr_values[value_key] = not curr_values[value_key] or nil
                else
                    UIManager:close(self)
                    if self.current_value ~= value_key then
                        self.callback(value_key)
                    end
                    if self.keep_open_on_apply then
                        self.current_value = value_key
                        self:init()
                        UIManager:show(self)
                    end
                end
            end,
        }}
    end

    if self.multi_choice then
        local function setAllValues(value)
            for _, v in ipairs(self.values) do
                curr_values[v[2]] = value
                local button = self:getButtonById(v[2])
                button.label_widget:setText(button:getDisplayText())
                button:refresh()
            end
        end
        table.insert(self.buttons, {
            {
                text = _("None"),
                callback = function()
                    setAllValues(nil)
                end,
            },
            {
                text = _("All"),
                callback = function()
                    setAllValues(true)
                end,
            },
        })
        table.insert(self.buttons, {
            {
                text = _("Apply"),
                callback = function()
                    if next(curr_values) then
                        -- nothing selected isn't allowed; all selected means no filter
                        self.callback(util.tableSize(curr_values) < #self.values and curr_values or nil)
                        if not self.keep_open_on_apply then
                            UIManager:close(self)
                        end
                    end
                end,
            },
        })
    end

    if self.bg_color then
        self.colorful = true
        self.dithered = true
    end

    ButtonDialog.init(self)
end

return ButtonSelector
