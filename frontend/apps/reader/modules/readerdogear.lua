local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = Device.screen

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
                rotation_angle = BD.mirroredUILayout() and 90 or 0,
                width = self.dogear_size,
                height = self.dogear_size,
            }
        }
    end
end

function ReaderDogear:onReadSettings(config)
    if not self.ui.document.info.has_pages then
        -- Adjust to CreDocument margins (as done in ReaderTypeset)
        local h_margins = config:readSetting("copt_h_page_margins") or
            G_reader_settings:readSetting("copt_h_page_margins") or
            DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM
        local t_margin = config:readSetting("copt_t_page_margin") or
            G_reader_settings:readSetting("copt_t_page_margin") or
            DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE
        local b_margin = config:readSetting("copt_b_page_margin") or
            G_reader_settings:readSetting("copt_b_page_margin") or
            DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE
        local margins = { h_margins[1], t_margin, h_margins[2], b_margin }
        self:onSetPageMargins(margins)
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
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
end

function ReaderDogear:onSetDogearVisibility(visible)
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
