--[[--
List row for the Calibre-Web view: cover, title, author, year · formats, and presence status.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local CalibreWebItem = InputContainer:extend{
    entry = nil, -- menu item table (with .row)
    menu = nil,
    dimen = nil,
    cover_bb = nil, -- scaled BlitBuffer owned by the menu's cover cache
    show_parent = nil,
}

--- Size reserved for covers in a row of the given height.
function CalibreWebItem.getCoverSize(item_height)
    local h = item_height - 2 * Size.padding.small
    return math.floor(h * 2 / 3), h
end

function CalibreWebItem:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    local row = self.entry.row
    local width, height = self.dimen.w, self.dimen.h
    local pad = Size.padding.default
    local cover_w, cover_h = CalibreWebItem.getCoverSize(height)

    local cover
    if self.cover_bb then
        cover = CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            ImageWidget:new{ image = self.cover_bb, image_disposable = false },
        }
    else
        -- Placeholder keeps the text column aligned while covers load (or when there is none)
        local border = Size.border.thin
        cover = FrameContainer:new{
            width = cover_w,
            height = cover_h,
            padding = 0,
            margin = 0,
            bordersize = border,
            color = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{
                dimen = Geom:new{ w = cover_w - 2 * border, h = cover_h - 2 * border },
                VerticalSpan:new{ width = 0 },
            },
        }
    end

    local status_widget = TextWidget:new{
        text = self.entry.mandatory or "",
        face = Font:getFace("smallinfofont", 16),
        fgcolor = self.entry.mandatory_dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
        bold = row.status == "both",
    }
    local status_w = status_widget:getSize().w + pad

    local text_w = width - cover_w - status_w - 3 * pad
    local title_face = Font:getFace("cfont", 20)
    local title = TextBoxWidget:new{
        text = row.title ~= "" and row.title or "—",
        face = title_face,
        bold = true,
        width = text_w,
        height = math.min(2 * title_face.size * 1.35, math.floor(height * 0.55)),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    }
    local authors = row.authors and #row.authors > 0 and table.concat(row.authors, ", ") or nil
    local details = {}
    local year = row.remote and row.remote.year
    if year then table.insert(details, tostring(year)) end
    if row.remote then
        local formats = {}
        for format in pairs(row.remote.formats) do table.insert(formats, format) end
        table.sort(formats)
        if #formats > 0 then table.insert(details, table.concat(formats, ", ")) end
    elseif #row.local_paths > 0 then
        local suffix = row.local_paths[1]:match("%.([^./]+)$")
        if suffix then table.insert(details, suffix:upper()) end
    end

    local text_group = VerticalGroup:new{ align = "left", title }
    if authors then
        table.insert(text_group, TextWidget:new{
            text = authors,
            face = Font:getFace("cfont", 17),
            max_width = text_w,
        })
    end
    if #details > 0 then
        table.insert(text_group, TextWidget:new{
            text = table.concat(details, " · "),
            face = Font:getFace("cfont", 15),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = text_w,
        })
    end

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            CenterContainer:new{ dimen = Geom:new{ w = cover_w, h = height }, cover },
            HorizontalSpan:new{ width = pad },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = height }, text_group },
            RightContainer:new{ dimen = Geom:new{ w = status_w, h = height }, status_widget },
            HorizontalSpan:new{ width = pad },
        },
    }
end

local function flash(self, callback)
    if G_reader_settings:isFalse("flash_ui") then return callback() end
    local frame = self[1]
    frame.invert = true
    UIManager:widgetInvert(frame, frame.dimen.x, frame.dimen.y)
    UIManager:setDirty(nil, "fast", frame.dimen)
    UIManager:forceRePaint()
    UIManager:yieldToEPDC()
    frame.invert = false
    UIManager:widgetInvert(frame, frame.dimen.x, frame.dimen.y)
    UIManager:setDirty(nil, "ui", frame.dimen)
    callback()
    UIManager:forceRePaint()
end

function CalibreWebItem:onTapSelect()
    if not self[1].dimen then return end
    flash(self, function() self.menu:onMenuSelect(self.entry) end)
    return true
end

function CalibreWebItem:onHoldSelect()
    if not self[1].dimen then return end
    flash(self, function() self.menu:onMenuHold(self.entry) end)
    return true
end

function CalibreWebItem:onFocus()
    self[1].invert = true
    return true
end

function CalibreWebItem:onUnfocus()
    self[1].invert = false
    return true
end

--- Search field shown as the first row: tap to search, hold to clear.
local SearchBar = CalibreWebItem:extend{}
CalibreWebItem.SearchBar = SearchBar

function SearchBar:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    local width, height = self.dimen.w, self.dimen.h
    local pad = Size.padding.default
    local border = Size.border.button
    local field_h = math.min(height - 2 * pad, math.floor(height * 0.6))
    local field_w = width - 2 * pad
    local icon_size = math.floor(field_h * 0.6)
    local search = self.entry.search

    local right_text
    if search then
        right_text = T(_("%1 found · hold to clear"), self.entry.result_count)
    end
    local right_widget = right_text and TextWidget:new{
        text = right_text,
        face = Font:getFace("cfont", 15),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local right_w = right_widget and (right_widget:getSize().w + pad) or 0
    local inner_w = field_w - 2 * border - 2 * pad
    local text_w = inner_w - icon_size - pad - right_w

    local query_widget = TextWidget:new{
        text = search and search.query or _("Search title, author, year…"),
        face = Font:getFace("cfont", 19),
        bold = search ~= nil,
        fgcolor = search and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        max_width = text_w,
    }

    local inner = HorizontalGroup:new{
        align = "center",
        IconWidget:new{ icon = "appbar.search", width = icon_size, height = icon_size },
        HorizontalSpan:new{ width = pad },
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = field_h - 2 * border }, query_widget },
    }
    if right_widget then
        table.insert(inner, RightContainer:new{ dimen = Geom:new{ w = right_w, h = field_h - 2 * border }, right_widget })
    end

    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            FrameContainer:new{
                width = field_w,
                height = field_h,
                bordersize = border,
                radius = Size.radius.button,
                padding = 0,
                padding_left = pad,
                padding_right = pad,
                inner,
            },
        },
    }
end

return CalibreWebItem
