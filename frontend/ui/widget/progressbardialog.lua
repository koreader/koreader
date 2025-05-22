local UIManager       = require("ui/uimanager")
local Device          = require("device")
local Screen          = Device.screen
local VerticalGroup   = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Size            = require("ui/size")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Blitbuffer      = require("ffi/blitbuffer")
local ProgressWidget  = require("ui/widget/progresswidget")
local dbg = require("dbg")
local TextWidget      = require("ui/widget/textwidget")
local Font            = require("ui/font")
local time = require("ui/time")

--[[--
A dialog that shows a progress bar with a title and subtitle

@usage
local progressbar_dialog = ProgressbarDialog:new {
    title = nil,
    subtitle = nil,
    refresh_time_seconds = 3,
    progress_max = nil
}

-- attach progress callback and call show()
progressbar_dialog:show()

-- call close() when download is done
progressbar_dialog:close()

-----------------------general use case-----------------------------------------
-- manually call reportProgress with the current progress (value between 0-max_progress)
progressbar_dialog:reportProgress( <progress value> )
----------------------------------------------------------------------------------

------------------use case with luasocket sink----------------------------------
local progress_callback = progressbar_dialog:getProgressCallback()
local sink = ltn12.sink.file(io.open(local_path, "w"))
sink = socketutil.chainSinkWithProgressCallback(sink, progress_callback)
-- start pushing data to the sink, this is usually some function that accepts a luasocket sink
something:startDownload(sink)
----------------------------------------------------------------------------------

Note: provide at least one of title, subtitle or progress_max
@param title string the title of the dialog
@param subtitle string the subtitle of the dialog
@param progress_max number the maximum progress (e.g. size of the file in bytes for file downloads)
                    reportProgress() should be called with the current
                    progress (value between 0-max_progress) to update the progress bar
                    optional: if `progress_max` is nil, the progress bar will be hidden
@param refresh_time_seconds number refresh time in seconds -  used with refresh_mode "time"
--]]
local ProgressbarDialog = WidgetContainer:extend {}

function ProgressbarDialog:init()
    self.align = "center"
    self.dimen = Screen:getSize()

    -- set default values if not provided
    self.title = self.title ~= nil and self.title or nil
    self.subtitle = self.subtitle ~= nil and self.subtitle or nil
    self.progress_max = self.progress_max ~= nil and self.progress_max or nil

    self.progress_bar_visible = self.progress_max ~= nil and self.progress_max > 0

    -- refresh time in seconds
    self.refresh_time_seconds = self.refresh_time_seconds and self.refresh_time_seconds or 3

    -- used for internal state
    self.last_redraw_time_ms = 0

    -- create the dialog
    local progress_bar_width = Screen:scaleBySize(360)
    local progress_bar_height = Screen:scaleBySize(18)

    self.title_text = TextWidget:new {
        text = self.title or "",
        face = Font:getFace("cfont", 18),
        bold = true,
        max_width = progress_bar_width,
    }

    self.subtitle_text = TextWidget:new {
        text = self.subtitle or "",
        face = Font:getFace("cfont", 16),
        max_width = progress_bar_width,
    }

    self.progress_bar = ProgressWidget:new {
        width = progress_bar_width,
        height = progress_bar_height,
        padding = Size.padding.large,
        margin = Size.margin.tiny,
        percentage = 0,
    }

    -- only add relevant widgets
    local vertical_group = VerticalGroup:new{ }
    if self.title then
        vertical_group[#vertical_group+1] = self.title_text
    end
    if self.subtitle then
        vertical_group[#vertical_group+1] = self.subtitle_text
    end
    if self.progress_bar_visible then
        vertical_group[#vertical_group+1] = self.progress_bar
    end

    self.frame_container = FrameContainer:new {
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        background = Blitbuffer.COLOR_WHITE,
        vertical_group
    }

    self[1] = self.frame_container
end
dbg:guard(ProgressbarDialog, "init",
nil,
    function(self)
        assert(self.progress_max == nil or
            (type(self.progress_max) == "number" and self.progress_max > 0),
            "Wrong self.progress_max type (expected nil or number greater than 0), value was: " .. tostring(self.progress_max))
        assert(type(self.refresh_time_seconds) == "number" and self.refresh_time_seconds > 0,
            "Wrong self.refresh_time_seconds type (expected number greater than 0), value was: " .. tostring(self.refresh_time_seconds))
        assert(self.title == nil or type(self.title) == "string",
            "Wrong title type (expected nil or string), value was of type: " .. type(self.title))
        assert(self.subtitle == nil or type(self.subtitle) == "string",
            "Wrong subtitle type (expected nil or string), value was of type: " .. type(self.subtitle))
        assert(self.title or self.subtitle or self.progress_max,
            "No values defined, dialog would be empty. Please provide at least one of title, subtitle or progress_max")
    end)

--- updates the UI to show the current percentage of the progress bar when needed see `ProgressbarDialog.refresh_mode`
function ProgressbarDialog:redrawProgressbarIfNeeded()
    -- grab the current percentage from the progress bar
    local current_percentage = self.progress_bar.percentage

    -- if we are at 100% always redraw
    if current_percentage >= 1 then
        self:redrawProgressbar()
        return
    end

    -- check if enough time has passed
    local current_time_ms = time.now()
    local time_delta_ms = current_time_ms - self.last_redraw_time_ms
    local refresh_time_ms = self.refresh_time_seconds * 1000 * 1000
    if time_delta_ms >= refresh_time_ms then
        self.last_redraw_time_ms = current_time_ms
        self:redrawProgressbar()
    end
end

function ProgressbarDialog:redrawProgressbar()
    --UI is not updating during file download so force an update
    UIManager:setDirty(self, function() return "fast", self.progress_bar.dimen end)
    UIManager:forceRePaint()
end

--- notify about a progress update i.e. when a new chunk on a file download has been received
-- @param progress number the current progress (e.g. size of the file in bytes for file downloads)
function ProgressbarDialog:reportProgress(progress)
    if not self.progress_bar_visible then
        return
    end

    -- set percentage of progress bar internally, this does not yet update
    self.progress_bar:setPercentage(progress / self.progress_max)

    -- actually draw the progress bar update
    self:redrawProgressbarIfNeeded()
end

--- Returns the progressCallback or nil if the progress bar is not visible
-- meant to be used with socketutil.chainSinkWithProgressCallback
--[[
usage:
------------------------------------------------------------
local handle = ltn12.sink.file(io.open(local_path, "w"))
local sink = socketutil.chainSinkWithProgressCallback(handle, progress_dialog:getProgressCallback())
...start download with sink...
------------------------------------------------------------
]]
function ProgressbarDialog:getProgressCallback()
    if self.progress_bar_visible then
        local progressCallback = function(progress)
            self:reportProgress(progress)
        end
        return progressCallback
    end

    return nil
end

--- opens dialog
function ProgressbarDialog:show()
    UIManager:show(self)
end

---- closes dialog
function ProgressbarDialog:close()
    UIManager:close(self)
end

return ProgressbarDialog
