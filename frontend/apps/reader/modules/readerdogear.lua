local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = require("device").screen

local ReaderDogear = InputContainer:new{}

function ReaderDogear:init()
    -- This image could be scaled for DPI (with scale_for_dpi=true, scale_factor=0.7),
    -- but it's as good to scale it to a fraction (1/32) of the screen size.
    -- For CreDocument, we should additionally take care of not exceeding margins
    -- to not overwrite the book text.
    -- For other documents, there is no easy way to know if valuable content
    -- may be hidden by the icon (kopt's page_margin is quite obscure).
    self.dogear_max_size = math.ceil( math.min(Screen:getWidth(), Screen:getHeight()) / 32)
    self.dogear_size = nil
    self:setupDogear()
    self:resetLayout()
end

function ReaderDogear:setupDogear(new_dogear_size)
    if not new_dogear_size then
        new_dogear_size = self.dogear_max_size
    end
    if new_dogear_size ~= self.dogear_size then
        self.dogear_size = new_dogear_size
        if self[1] then
            self[1]:free()
        end
        self[1] = RightContainer:new{
            dimen = Geom:new{w = Screen:getWidth(), h = self.dogear_size},
            ImageWidget:new{
                file = "resources/icons/dogear.png",
                width = self.dogear_size,
                height = self.dogear_size,
            }
        }
    end
end

function ReaderDogear:onReadSettings(config)
    if not self.ui.document.info.has_pages then
        -- Adjust to CreDocument margins (as done in ReaderTypeset)
        self:onSetPageMargins(
            config:readSetting("copt_page_margins") or
            G_reader_settings:readSetting("copt_page_margins") or
            DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM)
    end
end

function ReaderDogear:onSetPageMargins(margins)
    if self.ui.document.info.has_pages then
        -- we may get called by readerfooter (when hiding the footer)
        -- on pdf documents and get margins=nil
        return
    end
    local margin_top, margin_right = margins[2], margins[3]
    -- As the icon is squared, we can take the max() instead of the min() of
    -- top & right margins and be sure no text is hidden by the icon
    -- (the provided margins are not scaled, so do as ReaderTypeset)
    local margin = Screen:scaleBySize(math.max(margin_top, margin_right))
    local new_dogear_size = math.min(self.dogear_max_size, margin)
    self:setupDogear(new_dogear_size)
end

function ReaderDogear:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._last_screen_width then return end
    local new_screen_height = Screen:getHeight()
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = new_screen_width*DTAP_ZONE_BOOKMARK.x,
                        y = new_screen_height*DTAP_ZONE_BOOKMARK.y,
                        w = new_screen_width*DTAP_ZONE_BOOKMARK.w,
                        h = new_screen_height*DTAP_ZONE_BOOKMARK.h
                    }
                }
            }
        }
    end
end

function ReaderDogear:onTap()
    self.ui:handleEvent(Event:new("ToggleBookmark"))
    return true
end

function ReaderDogear:onSetDogearVisibility(visible)
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
