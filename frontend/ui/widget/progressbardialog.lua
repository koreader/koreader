--[[--
A dialog that shows a progress bar with a title and subtitle.

@usage
local progressbar_dialog = ProgressbarDialog:new {
    title = nil,
    subtitle = nil,
    progress_max = nil
    refresh_time_seconds = 3,
}
Note: provide at least one of title, subtitle or progress_max
@param title string the title of the dialog
@param subtitle string the subtitle of the dialog
@param progress_max number the maximum progress (e.g. size of the file in bytes for file downloads)
                    reportProgress() should be called with the current
                    progress (value between 0-progress_max) to update the progress bar
                    optional: if `progress_max` is nil, the progress bar will be hidden
@param refresh_time_seconds number refresh time in seconds

-- Attach progress callback and call show()
progressbar_dialog:show()

-- Call close() when download is done
progressbar_dialog:close()

-- To report progress, you can either:
-- manually call reportProgress with the current progress (value between 0-progress_max)
progressbar_dialog:reportProgress( <progress value> )

-- or when using luasocket sinks, chain the callback:
local sink = ltn12.sink.file(io.open(local_path, "w"))
sink = socketutil.chainSinkWithProgressCallback(sink, function(progress)
    progressbar_dialog:reportProgress(progress)
end)
--]]

local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local dbg = require("dbg")
local time = require("ui/time")
local Input = Device.input
local Screen = Device.screen
local _ = require("gettext")

local ProgressbarDialog = InputContainer:extend {
    align = "center",
    vertical_align = "center",
    dismissable = true,
    dismiss_callback = nil,
    dismiss_text = nil,
    refresh_time_seconds = 3,
}

function ProgressbarDialog:init()
    self.align = "center"
    self.dimen = Screen:getSize()

    if self.dismissable then
        if Device:hasKeys() then
            self.key_events.AnyKeyPressed = { { Input.group.Any } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end

    self.progress_bar_visible = self.progress_max ~= nil and self.progress_max > 0

    -- used for internal state
    self.last_redraw_time_ms = 0

    -- create the dialog
    local progress_bar_width = Screen:getWidth() - Screen:scaleBySize(80)
    local progress_bar_height = Screen:scaleBySize(18)

    -- only add relevant widgets
    local vertical_group = VerticalGroup:new {}
    if self.title then
        vertical_group[#vertical_group + 1] = TextWidget:new {
            text = self.title or "",
            face = Font:getFace("ffont"),
            bold = true,
            max_width = progress_bar_width,
        }
    end
    if self.subtitle then
        vertical_group[#vertical_group + 1] = TextWidget:new {
            text = self.subtitle or "",
            face = Font:getFace("smallffont"),
            max_width = progress_bar_width,
        }
    end
    if self.progress_bar_visible then
        self.progress_bar = ProgressWidget:new {
            fillcolor = Blitbuffer.COLOR_BLACK,
            width = progress_bar_width,
            height = progress_bar_height,
            padding = Size.padding.large,
            margin = Size.margin.tiny,
            percentage = 0,
        }
        vertical_group[#vertical_group + 1] = self.progress_bar
    end

    self[1] = FrameContainer:new {
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        background = Blitbuffer.COLOR_WHITE,
        vertical_group
    }
end

dbg:guard(ProgressbarDialog, "init",
    nil,
    function(self)
        assert(self.progress_max == nil or
            (type(self.progress_max) == "number" and self.progress_max > 0),
            "Wrong self.progress_max type (expected nil or number greater than 0), value was: " ..
            tostring(self.progress_max))
        assert(type(self.refresh_time_seconds) == "number" and self.refresh_time_seconds > 0,
            "Wrong self.refresh_time_seconds type (expected number greater than 0), value was: " ..
            tostring(self.refresh_time_seconds))
        assert(self.title == nil or type(self.title) == "string",
            "Wrong title type (expected nil or string), value was of type: " .. type(self.title))
        assert(self.subtitle == nil or type(self.subtitle) == "string",
            "Wrong subtitle type (expected nil or string), value was of type: " .. type(self.subtitle))
        assert(self.title or self.subtitle or self.progress_max,
            "No values defined, dialog would be empty. Please provide at least one of title, subtitle or progress_max")
    end)

--- Updates the UI to show the current percentage of the progress bar when needed.
function ProgressbarDialog:redrawProgressbarIfNeeded()
    -- grab the current percentage from the progress bar
    local current_percentage = self.progress_bar.percentage

    -- if we are at 100% always redraw
    if current_percentage >= 1 then
        self:redrawProgressbar()
        return true
    end

    -- check if enough time has passed
    local current_time_ms = time.now()
    local time_delta_ms = current_time_ms - self.last_redraw_time_ms
    local refresh_time_ms = self.refresh_time_seconds * 1000 * 1000
    if time_delta_ms >= refresh_time_ms then
        self.last_redraw_time_ms = current_time_ms
        self:redrawProgressbar()
        return true
    end
end

function ProgressbarDialog:redrawProgressbar()
    --UI is not updating during file download so force an update
    UIManager:setDirty(self, function() return "fast", self.dimen end)
    UIManager:forceRePaint()
end

--- Used to notify about a progress update.
-- @param progress number the current progress (e.g. size of the file in bytes for file downloads)
function ProgressbarDialog:reportProgress(progress)
    if not self.progress_bar_visible then
        return
    end

    -- set percentage of progress bar internally, this does not yet update the screen element
    self.progress_bar:setPercentage(progress / self.progress_max)

    -- actually draw the progress bar update
    return self:redrawProgressbarIfNeeded()
end

--- Opens dialog.
function ProgressbarDialog:show()
    UIManager:show(self, "ui")
end

---- Closes dialog.
function ProgressbarDialog:close()
    UIManager:close(self, "ui")
end

function ProgressbarDialog:onCloseWidget()
    if self.dismiss_box then
        UIManager:close(self.dismiss_box)
        self.dismiss_box = nil
    end
    if self.dismiss_callback then
        self.dismiss_callback()
        self.dismiss_callback = nil
    end
end

function ProgressbarDialog:onDismiss()
    if self.dismiss_text then
        self.dismiss_box = ConfirmBox:new{
            text = self.dismiss_text,
            cancel_text = _("Cancel"),
            cancel_callback = function()
                self.dismiss_box = nil
                UIManager:close(self)
            end,
            ok_text = _("Continue"),
            ok_callback = function()
                self.dismiss_box = nil
            end,
            dismissable = false,
        }
        UIManager:show(self.dismiss_box)
    else
        UIManager:close(self)
    end
end
ProgressbarDialog.onAnyKeyPressed = ProgressbarDialog.onDismiss
ProgressbarDialog.onTapClose = ProgressbarDialog.onDismiss

return ProgressbarDialog
