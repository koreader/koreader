local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local ReaderFlipping = WidgetContainer:extend{
    orig_reflow_mode = 0,
    -- Icons to show during crengine partial rerendering automation
    rolling_rendering_state_icons = {
        PARTIALLY_RERENDERED = "cre.render.partial",
        FULL_RENDERING_IN_BACKGROUND = "cre.render.working",
        FULL_RENDERING_READY = "cre.render.ready",
        RELOADING_DOCUMENT = "cre.render.reload",
    },
}

function ReaderFlipping:init()
    local icon_size = Screen:scaleBySize(32)
    local dummy = IconWidget:new{
        width = icon_size,
        height = icon_size,
    }
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = dummy:getSize().h},
        dummy,
    }
    self:resetLayout()
end

function ReaderFlipping:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._last_screen_width then return end
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
end

function ReaderFlipping:getRollingRenderingStateIconWidget()
    if not self.rolling_rendering_state_widgets then
        self.rolling_rendering_state_widgets = {}
    end
    local widget = self.rolling_rendering_state_widgets[self.ui.rolling.rendering_state]
    if widget == nil then    -- not met yet
        local icon_size = Screen:scaleBySize(32)
        for k, v in pairs(self.ui.rolling.RENDERING_STATE) do -- known states
            if v == self.ui.rolling.rendering_state then -- current state
                local icon = self.rolling_rendering_state_icons[k] -- our icon (or none) for this state
                if icon then
                    self.rolling_rendering_state_widgets[v] = IconWidget:new{
                        icon = icon,
                        width = icon_size,
                        height = icon_size,
                        alpha = not self.ui.rolling.cre_top_bar_enabled,
                            -- if top status bar enabled, have them opaque, as they
                            -- will be displayed over the bar
                            -- otherwise, keep their alpha so some bits of text is
                            -- visible if displayed over the text when small margins
                    }
                else
                    self.rolling_rendering_state_widgets[v] = false
                end
                break
            end
        end
        widget = self.rolling_rendering_state_widgets[self.ui.rolling.rendering_state]
    end
    return widget or nil -- return nil if cached widget is false
end

function ReaderFlipping:onSetStatusLine()
    -- Reset these widgets: we want new ones with proper alpha/opaque
    self.rolling_rendering_state_widgets = nil
end

function ReaderFlipping:paintTo(bb, x, y)
    local widget
    if self.ui.paging and self.view.flipping_visible then
        -- pdf page flipping or bookmark browsing mode
        local icon_size = Screen:scaleBySize(32)
        widget = IconWidget:new{
            icon = self.ui.paging.bookmark_flipping_mode and "bookmark" or "book.opened",
            width = icon_size,
            height = icon_size,
        }
    elseif self.ui.highlight.select_mode then
        -- highlight select mode
        local icon_size = Screen:scaleBySize(36)
        widget = IconWidget:new{
            icon = "texture-box",
            width = icon_size,
            height = icon_size,
            alpha = true,
        }
    elseif self.ui.rolling and self.ui.rolling.rendering_state then
        -- epub rerendering
        widget = self:getRollingRenderingStateIconWidget()
    end
    if widget then
        if self[1][1] ~= widget then
            self[1][1] = widget
        end
        WidgetContainer.paintTo(self, bb, x, y)
    end
end

return ReaderFlipping
