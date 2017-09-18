
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local ReadTimer = WidgetContainer:new{
    name = "readtimer",
    time = 0,  -- The expected time of alarm if enabled, or 0.
}

function ReadTimer:init()
    self.alarm_callback = function()
        if self.time == 0 then return end -- How could this happen?
        self.time = 0
        UIManager:show(InfoMessage:new{
            text = T(_("Read timer alarm\nTime's up. It's %1 now."), os.date("%c")),
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:scheduled()
    return self.time ~= 0
end

function ReadTimer:remainingMinutes()
    if self:scheduled() then
        return os.difftime(self.time, os.time()) / 60
    else
        return math.huge
    end
end

function ReadTimer:unschedule()
    if self:scheduled() then
        UIManager:unschedule(self.alarm_callback)
        self.time = 0
    end
end

function ReadTimer:addToMainMenu(menu_items)
    menu_items.read_timer = {
        text_func = function()
            if self:scheduled() then
                return T(_("Read timer (%1m)"),
                         string.format("%.2f", self:remainingMinutes()))
            else
                return _("Read timer")
            end
        end,
        checked_func = function()
            return self:scheduled()
        end,
        callback = function()
            local description = _("When should the countdown timer notify you?")
            local buttons = {{
                text = _("Close"),
                callback = function()
                    UIManager:close(self.input)
                end,
            }, {
                text = _("Start timer"),
                callback = function()
                    self:unschedule()
                    local seconds = self.input:getInputValue() * 60
                    if seconds > 0 then
                        self.time = os.time() + seconds
                        UIManager:scheduleIn(seconds, self.alarm_callback)
                    end
                    UIManager:close(self.input)
                    if self.ui == nil or self.ui.document == nil then
                        self.ui.menu:onCloseFileManagerMenu()
                    else
                        self.ui.menu:onTapCloseMenu()
                    end
                end,
            }}
            if self:scheduled() then
                description = description ..
                    T(_("\n\nYou have already set up a timer for %1 minutes from now. Setting a new one will overwrite it."),
                      string.format("%.2f", self:remainingMinutes()))
                table.insert(buttons, {
                    text = _("Stop"),
                    callback = function()
                        self:unschedule()
                        if self.ui == nil or self.ui.document == nil then
                            self.ui.menu:onCloseFileManagerMenu()
                        else
                            self.ui.menu:onTapCloseMenu()
                        end
                        UIManager:close(self.input)
                    end,
                })
            end
            description = description .. _("\n\n  - Positive number is required.")

            self.input = InputDialog:new{
                title = _("Read timer"),
                description = description,
                input_type = "number",
                input_hint = _("time in minutes"),
                buttons = { buttons },
            }
            self.input:onShowKeyboard()
            UIManager:show(self.input)
        end,
    }
end

return ReadTimer
