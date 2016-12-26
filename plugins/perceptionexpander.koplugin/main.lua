local Widget = require("ui/widget/widget")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

local PerceptionExpander = Widget:extend{
    is_enabled = nil,
    name = "percepton_expander",
    page_counter = 0,
    shift_each_pages = 100,
    margin = 0.1,
    line_thick = 2,
    line_color_intensity = 0.3,
    margin_shift = 0.03,
}

function PerceptionExpander:init()
    local settings = G_reader_settings:readSetting("perception_expander") or {}
    self.is_enabled = not (settings.is_enabled == false)
    if not self.is_enabled then
        return
    end
    self:createUI(settings)
end

function PerceptionExpander:createUI(settings)
    if settings then
        self.line_thick = tonumber(settings.line_thick)
        self.margin = tonumber(settings.margin)
        self.line_color_intensity = tonumber(settings.line_color_intensity)
        self.shift_each_pages = tonumber(settings.shift_each_pages)
        self.page_counter = tonumber(settings.page_counter)
    end

    self.screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local line_height = screen_height * 0.9
    local line_top_position = screen_height * 0.05

    if Screen:getScreenMode() == "landscape" then
        self.margin = (self.margin - self.margin_shift)
    end

    local line_widget = LineWidget:new{
        background = Blitbuffer.gray(self.line_color_intensity),
        dimen = Geom:new{
            w = self.line_thick,
            h = line_height,
        },
    }

    self.left_line = WidgetContainer:new{
        dimen = Geom:new{
            x = self.screen_width * self.margin,
            y = line_top_position,
            w = self.line_thick,
            h = line_height,
        },
        line_widget
    }

    self.right_line = WidgetContainer:new{
        dimen = Geom:new{
            x = self.screen_width - (self.screen_width * self.margin),
            y = line_top_position,
            w = self.line_thick,
            h = line_height,
        },
        line_widget
    }

    self[1] = HorizontalGroup:new{
        self.left_line,
        self.right_line,
    }
end

function PerceptionExpander:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("perception_expander", self)
end

function PerceptionExpander:resetLayout()
    self:createUI()
end

function PerceptionExpander:showSettingsDialog()
    self.settings_dialog = MultiInputDialog:new{
        title = _("Perception expander settings"),
        fields ={
            {
                text = "",
                input_type = "number",
                hint = T(_("Line thick. Current value: %1"),
                    self.line_thick),
            },
            {
                text = "",
                input_type = "number",
                hint = T(_("Margin from edges. Current value: %1"),
                    self.margin),
            },
            {
                text = "",
                input_type = "number",
                hint = T(_("Line color intensity (1-10). Current value: %1"),
                    self.line_color_intensity * 10),
            },
            {
                text = "",
                input_type = "number",
                hint = T(_("Increase margin after pages. Current value: %1"),
                    self.shift_each_pages),
            },
        },
        buttons ={
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings(MultiInputDialog:getFields())
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                        self:createUI()
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.3,
    }
    self.settings_dialog:onShowKeyboard()
    UIManager:show(self.settings_dialog)
end

function PerceptionExpander:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins,{
        text = _("Speed reading module - perception expander"),
        sub_item_table ={
            {
                text = _("Enable"),
                checked_func = function() return self.is_enabled end,
                callback = function()
                    self.is_enabled = not self.is_enabled
                    self:saveSettings()
                    return true
                end,
            },
            {
                text = _("Settings"),
                callback = function()
                    self:showSettingsDialog()
                end,
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("For more information see wiki page Perception Expander Plugin"),
                    })
                end,
            },
        },
    })
end

-- in case when screensaver starts
function PerceptionExpander:onSaveSettings()
    self:saveSettings()
end

function PerceptionExpander:onPageUpdate(pageno)
    if not self.is_enabled then
        return
    end

    if self.page_counter >= self.shift_each_pages and self.margin < 0.37 then
        self.page_counter = 0
        self.margin = self.margin + self.margin_shift
        self.left_line.dimen.x = self.screen_width * self.margin
        self.right_line.dimen.x = self.screen_width - (self.screen_width * self.margin)
    else
        self.page_counter = self.page_counter + 1;
    end
end


function PerceptionExpander:saveSettings(fields)
    if fields then
        self.line_thick = tonumber(fields[1])
        self.margin = tonumber(fields[2])

        local line_intensity = tonumber(fields[3])
        if line_intensity then
            self.line_color_intensity = line_intensity / 10
        end
        self.shift_each_pages = tonumber(fields[4])
    end

    local settings ={
        line_thick = self.line_thick,
        margin = self.margin,
        line_color_intensity = self.line_color_intensity,
        shift_each_pages = self.shift_each_pages,
        is_enabled = self.is_enabled,
    }

    G_reader_settings:saveSetting("perception_expander", settings)
end

function PerceptionExpander:paintTo(bb, x, y)
    if self.is_enabled and self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

return PerceptionExpander
