
local Font = require("ui/font")
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
        UIManager:show(InfoMessage:new{
            text = T(_("Time's up\nIt's %1 now."), os.date("%c")),
            timeout = 10,
        })
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:scheduled()
    return self.time ~= 0
end

function ReadTimer:remainingMinutes()
    if self:scheduled() then
        return os.difftime(os.time(), self.time) / 60
    else
        return math.huge
    end
end

function ReadTimer:unschedule()
    if self:scheduled() then
        UIManager:unschedule(self.alarm_callback)
    end
end

function ReadTimer:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Read timer"),
        callback = function()
            local title = _("When will the countdown timer alarm?\n(The unit is \"minute\", and only positive number is accepted.)")
            if self:scheduled() then
                title = title .. T(_("\nYou have already set up a timer in %1 minutes. Setting a new one will overwrite it."),
                                   self:remainingMinutes())
            end
            local buttons = {{
                text = _("Close"),
                callback = function()
                    UIManager:close(self.input)
                end,
            }, {
                text = _("Start"),
                callback = function()
                    self:unschedule()
                    local seconds = self.input:getInputValue() * 60
                    if seconds > 0 then
                        self.time = os.time() + seconds
                        UIManager:scheduleIn(seconds, self.alarm_callback)
                    end
                    UIManager:close(self.input)
                end,
            }}
            if self:scheduled() then
                table.insert(buttons, {
                    text = _("Stop"),
                    callback = function()
                        self:unschedule()
                        UIManager:close(self.input)
                    end,
                })
            end
            self.input = InputDialog:new{
                title_face = Font:getFace("cfont", 20),
                title = title,
                full_title = true,
                input_type = "number",
                input_hint = _("in minutes"),
                buttons = { buttons },
            }
            UIManager:show(self.input)
        end,
    })
end

return ReadTimer
