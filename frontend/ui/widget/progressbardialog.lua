local UIManager       = require("ui/uimanager")
local Device          = require("device")
local Screen          = Device.screen
local VerticalGroup   = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Size            = require("ui/size")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Blitbuffer      = require("ffi/blitbuffer")
local ProgressWidget  = require("ui/widget/progresswidget")
local TitleBar        = require("ui/widget/titlebar")
local logger          = require("logger")
local TextWidget      = require("ui/widget/textwidget")
local Font            = require("ui/font")
local time = require("ui/time")

--[[--
A dialog that shows a progress bar with a title and subtitle

@usage
local progressbar_dialog = ProgressbarDialog:new {
    title = nil, -- e.g. _("Downloading file."),
    subtitle = nil, -- e.g. "Please wait.",

    -- determines how the progress bar is updated
    refresh_mode = "time", -- other options: "steps" | "fixed_percentage" | "time",

    -- set self.refresh_* values according to the refresh_mode
    refresh_time_seconds = 3,
    refresh_fixed_percentage_change = 0.2,
    refresh_steps_stepcount = 5,

    -- reportProgress() should be called with the current
    -- progress (value between 0-max_progress) to update the progress bar
    -- optional: if `progress_max` is not set, the progress bar will not be shown
    progress_max = nil -- e.g. 150
}

-----------------------general use case-----------------------------------------
-- call reportProgress with the current progress (value between 0-max_progress)
progressbar_dialog:reportProgress( <progress value> )
----------------------------------------------------------------------------------

------------------use case with luasocket sink----------------------------------
local progress_callback = progressbar_dialog:getProgressCallback()
local sink = ltn12.sink.file(io.open(local_path, "w"))
sink = socketutil.wrapSinkWithProgressCallback(sink, progress_callback)
-- start pushing data to the sink, this is usually some function that accepts a luasocket sink
something:startDownload(sink)
----------------------------------------------------------------------------------


@param title string the title of the dialog
@param subtitle string the subtitle of the dialog
@param progress_max number the maximum progress (e.g. size of the file in bytes for file downloads)
@param refresh_mode string how the updating of the progress should be handle (to limit redraws to significant changes)
    - "time" means update every x second
    - "fixed_percentage" means only update when the percentage changes by a certain amount e.g. every 10% step
    - "steps" means update in steps e.g. 5 total steps and show step markers inside progress bar
@param refresh_time_seconds number refresh time in seconds -  used with refresh_mode "time"
@param refresh_fixed_percentage_change number - used with refresh_mode "fixed_percentage"
@param refresh_steps_stepcount number how many steps to show - used with refresh_mode "steps"
--]]
local ProgressbarDialog = WidgetContainer:extend {}

function ProgressbarDialog:init()
    self.align = "center"
    self.dimen = Screen:getSize()

    self.title = self.title ~= nil and self.title or nil
    self.subtitle = self.subtitle ~= nil and self.subtitle or nil
    self.progress_max = self.progress_max ~= nil and self.progress_max or nil

    local progress_max_available = self.progress_max ~= nil and self.progress_max > 0
    self.progress_bar_visible = progress_max_available

    self.refresh_mode = self.refresh_mode and self.refresh_mode or "time"

    -- refresh time in seconds
    self.refresh_time_seconds = self.refresh_time_seconds and self.refresh_time_seconds or 3
    -- used with refresh_mode "fixed_percentage"
    self.refresh_fixed_percentage_change = self.refresh_fixed_percentage_change and
        self.refresh_fixed_percentage_change or 0.2
    -- used with refresh_mode "steps"
    self.refresh_steps_stepcount = self.refresh_steps_stepcount and self.refresh_steps_stepcount or 5

    self.ticks = {}
    for i = 1, self.refresh_steps_stepcount do
        self.ticks[i] = i
    end

    -- used for internal state
    self.last_percent = 0
    self.last_step = 0
    self.last_redraw_time_ms = 0

    -- create the dialog
    local progress_bar_width = Screen:scaleBySize(360)
    local progress_bar_height = Screen:scaleBySize(18)
    local frame_width = Screen:scaleBySize(400)


    self.title_text = TextWidget:new {
        text = self.title,
        face = Font:getFace("cfont", 18),
        bold = true,
    }
    self.subtitle_text = TextWidget:new {
        text = self.subtitle,
        face = Font:getFace("cfont", 16),
        truncate_with_ellipsis = true,
        truncate_left = false,
        max_width = progress_bar_width,
    }

    self.title_bar = TitleBar:new {
        title = self.title,
        subtitle = self.subtitle,
        align = "left",
        width = frame_width,
        with_bottom_line = false,
        bottom_v_padding = Screen:scaleBySize(15),
        padding = Size.padding.tiny,
    };

    self.progress_bar = ProgressWidget:new {
        width = progress_bar_width,
        height = progress_bar_height,
        padding = Size.padding.large,
        margin = Size.margin.tiny,
        percentage = 0,
        ticks = self.refresh_mode == "steps" and self.ticks or nil,
        last = self.refresh_mode == "steps" and self.refresh_steps_stepcount or nil,
        tick_width = Screen:scaleBySize(2),
    }

    self[1] = FrameContainer:new {
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            self.title_text,
            self.subtitle_text,
            -- self.title_bar,
            self.progress_bar_visible and self.progress_bar or nil
        }
    }
end

--- the title at the top of the dialog, e.g. to show "Downloading File" or similar
function ProgressbarDialog:setTitle(title)
    self.title_bar.title = title
    UIManager:setDirty(self.title_bar, function() return "fast", self.title_bar.dimen end)
end

--- the subtitle below the title to show more information,
--- e.g. "Please wait" or the current file name
function ProgressbarDialog:setSubtitle(subtitle)
    self.titlle_bar.subtitle = subtitle
    UIManager:setDirty(self.title_bar, function() return "fast", self.title_bar.dimen end)
end

--- updates the UI to show the current percentage of the progress bar when needed see `ProgressbarDialog.refresh_mode`
function ProgressbarDialog:redrawProgressbarIfNeeded()
    -- grab the current percentage from the progress bar
    local current_percentage = self.progress_bar.percentage

    -- if we are at 100% always redraw
    if current_percentage >= 1 then
        self:redrawProgressbar()
        return
    end

    if self.refresh_mode == "time" then
        -- check if enough time has passed
        local current_time_ms = time.now()
        local time_delta_ms = current_time_ms - self.last_redraw_time_ms
        local refresh_time_ms = self.refresh_time_seconds * 1000 * 1000
        if time_delta_ms >= refresh_time_ms then
            self.last_redraw_time_ms = current_time_ms
            self:redrawProgressbar()
        end
    elseif self.refresh_mode == "fixed_percentage" then
        -- only update if we have a significant change
        if current_percentage >= self.last_percent + self.refresh_fixed_percentage_change then
            self.last_percent = current_percentage
            self:redrawProgressbar()
        end
    elseif self.refresh_mode == "steps" then
        local current_step = math.floor(current_percentage * self.refresh_steps_stepcount)

        -- only update if we reached a new step
        if self.last_step ~= current_step then
            self.last_step = current_step
            self:redrawProgressbar()
        end
    else
        logger.err(
            "ProgressbarDialog:redrawProgressbarIfNeeded - function called but self.refresh_mode not properly set")
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
-- meant to be used with socketutil.wrapSinkWithProgressCallback
--[[
usage:
------------------------------------------------------------
local handle = ltn12.sink.file(io.open(local_path, "w"))
handle = socketutil.wrapSinkWithProgressCallback(handle, progress_dialog:getProgressCallback())
...start download with handle as sink...
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
    -- full flash to make sure the whole window gets closed
    UIManager:close(self, "flashui", Screen:getSize())
end

return ProgressbarDialog
