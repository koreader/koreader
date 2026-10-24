--[[--
Detailed list view for the OPDS browser, modelled on coverbrowser.koplugin's listmenu.lua.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OPDSCoverLoader = require("opdscoverloader")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local scale_by_size = Screen:scaleBySize(1000000) * (1/1000000)

local NOMINAL_ITEM_HEIGHT = 96
local COVER_ASPECT_RATIO = 0.7
local COVER_UPDATE_INTERVAL = 1

local OPDSListMenuItem = InputContainer:extend{
    entry = nil, -- OPDS item table, mandatory
    menu = nil,
    show_parent = nil,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    do_cover_image = true,
    _underline_container = nil,
    cover_pending = false,
}

function OPDSListMenuItem:init()
    -- As done in MenuItem: squared letter for keyboard navigation
    if self.shortcut then
        local icon_width = math.floor(self.dimen.h * 2/5)
        self.shortcut_icon = self.menu:getItemShortCutIcon(
            Geom:new{ x = 0, y = 0, w = icon_width, h = icon_width },
            self.shortcut, self.shortcut_style)
    end

    -- We need this table per-instance, so we declare it here
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }

    -- Smaller than the default (3) to not shift our vertical alignment
    self.underline_h = 1
    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = Geom:new{
            w = self.width,
            h = self.height,
        },
        linesize = self.underline_h,
        focus_linesize = Size.line.focus_indicator,
    }
    self[1] = self._underline_container

    self:update()
end

local function getCoverUrl(entry)
    return entry.thumbnail or entry.image
end

local function getFormatsText(entry, get_filetype)
    if type(entry.acquisitions) ~= "table" then return end
    local formats, seen = {}, {}
    for __, acquisition in ipairs(entry.acquisitions) do
        local format
        if acquisition.count then
            -- @translators Refers to reading a document from an OPDS server page by page, without downloading it.
            format = _("Stream")
        elseif acquisition.type == "borrow" then
            format = _("Borrow")
        else
            local filetype = get_filetype(acquisition)
            format = filetype and filetype:upper()
        end
        if format and not seen[format] then
            seen[format] = true
            table.insert(formats, format)
        end
    end
    if #formats > 0 then
        return table.concat(formats, " · ")
    end
end

function OPDSListMenuItem:update()
    local dimen = Geom:new{
        w = self.width,
        h = self.height - 2 * self.underline_h,
    }

    local function _fontSize(nominal, max)
        -- Keep the ratio of font size to item height, based on a nominal item height
        local font_size = math.floor(nominal * dimen.h * (1/NOMINAL_ITEM_HEIGHT) / scale_by_size)
        if max and font_size >= max then
            return max
        end
        return font_size
    end

    local entry = self.entry
    self._has_cover_image = false
    local border_size = Size.border.thin
    local pad_width = Screen:scaleBySize(10)
    local max_img_h = dimen.h - 2 * border_size
    local max_img_w = math.floor(max_img_h * COVER_ASPECT_RATIO)

    -- Catalogs have no acquisition links, and get a plain single-line look
    local is_book = type(entry.acquisitions) == "table" and #entry.acquisitions > 0

    local wright, wright_width = nil, 0
    if entry.mandatory then
        wright = TextWidget:new{
            text = tostring(entry.mandatory),
            face = Font:getFace("infont", _fontSize(14, 18)),
        }
        wright_width = wright:getSize().w
    end

    local widget
    if not is_book then
        local text_widget = TextBoxWidget:new{
            text = BD.auto(entry.text or ""),
            face = Font:getFace("cfont", _fontSize(18, 22)),
            width = dimen.w - 2 * pad_width - wright_width,
            alignment = "left",
            height = dimen.h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
        widget = LeftContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                HorizontalSpan:new{ width = pad_width },
                text_widget,
            },
        }
    else
        local wleft
        local cover_url = self.do_cover_image and getCoverUrl(entry) or nil
        if cover_url then
            local cover_bb = OPDSCoverLoader:getCoverBB(cover_url, max_img_w, max_img_h)
            if cover_bb then
                local wimage = ImageWidget:new{
                    image = cover_bb,
                    image_disposable = true,
                }
                wimage:_render()
                local image_size = wimage:getSize()
                wleft = FrameContainer:new{
                    width = image_size.w + 2 * border_size,
                    height = image_size.h + 2 * border_size,
                    margin = 0,
                    padding = 0,
                    bordersize = border_size,
                    wimage,
                }
                -- Let the menu know it should dither this refresh
                self.menu._has_cover_images = true
                self._has_cover_image = true
            else
                -- nil: not fetched yet, false: known to be unavailable
                self.cover_pending = cover_bb == nil
            end
        end
        if not wleft and self.do_cover_image then
            wleft = FrameContainer:new{
                width = max_img_w + 2 * border_size,
                height = max_img_h + 2 * border_size,
                margin = 0,
                padding = 0,
                bordersize = border_size,
                CenterContainer:new{
                    dimen = Geom:new{ w = max_img_w, h = max_img_h },
                    TextWidget:new{
                        text = "⛶", -- U+26F6 Square four corners
                        face = Font:getFace("cfont", _fontSize(20)),
                    },
                },
            }
        end
        local cover_column_w = 0
        local wleft_container
        if wleft then
            cover_column_w = max_img_w + 2 * border_size
            wleft_container = CenterContainer:new{
                dimen = Geom:new{ w = cover_column_w, h = dimen.h },
                wleft,
            }
        end

        local text_width = dimen.w - cover_column_w - 3 * pad_width - wright_width
        local wtitle = TextBoxWidget:new{
            text = BD.auto(entry.title or entry.text or ""),
            face = Font:getFace("cfont", _fontSize(17, 22)),
            width = text_width,
            height = math.floor(dimen.h / 2),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
        }

        local right_group = VerticalGroup:new{
            align = "left",
            wtitle,
        }
        if entry.subtitle and entry.subtitle ~= "" then
            table.insert(right_group, VerticalSpan:new{ width = Screen:scaleBySize(1) })
            table.insert(right_group, TextWidget:new{
                text = BD.auto(entry.subtitle),
                face = Font:getFace("cfont", _fontSize(13, 16)),
                max_width = text_width,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
        end
        if entry.author then
            table.insert(right_group, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(right_group, TextWidget:new{
                text = BD.auto(entry.author),
                face = Font:getFace("cfont", _fontSize(14, 18)),
                max_width = text_width,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
        end
        local info_parts = {}
        local formats = getFormatsText(entry, self.menu.getFiletype)
        if formats then table.insert(info_parts, formats) end
        if entry.published then table.insert(info_parts, entry.published) end
        if #info_parts > 0 then
            table.insert(right_group, VerticalSpan:new{ width = Screen:scaleBySize(3) })
            table.insert(right_group, TextWidget:new{
                text = table.concat(info_parts, " · "),
                face = Font:getFace("infont", _fontSize(12, 15)),
                max_width = text_width,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
        end

        local hgroup = HorizontalGroup:new{
            HorizontalSpan:new{ width = pad_width },
        }
        if wleft_container then
            table.insert(hgroup, wleft_container)
            table.insert(hgroup, HorizontalSpan:new{ width = pad_width })
        end
        table.insert(hgroup, CenterContainer:new{
            dimen = Geom:new{ w = text_width, h = dimen.h },
            right_group,
        })
        widget = LeftContainer:new{
            dimen = dimen:copy(),
            hgroup,
        }
    end

    if wright then
        widget = OverlapGroup:new{
            dimen = dimen:copy(),
            widget,
            RightContainer:new{
                dimen = dimen:copy(),
                HorizontalGroup:new{
                    wright,
                    HorizontalSpan:new{ width = pad_width },
                },
            },
        }
    end

    if self._underline_container[1] then
        self._underline_container[1]:free()
    end
    -- Pad at the top to balance the hidden underline line at the bottom
    self._underline_container[1] = VerticalGroup:new{
        VerticalSpan:new{ width = self.underline_h },
        widget,
    }
end

function OPDSListMenuItem:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    if self.shortcut_icon then
        -- Align it on the bottom left corner of the sub-widget
        local target = self[1][1][2]
        local ix
        if BD.mirroredUILayout() then
            ix = target.dimen.w - self.shortcut_icon.dimen.w - 2 * self.shortcut_icon.bordersize
        else
            ix = 0
        end
        local iy = target.dimen.h - self.shortcut_icon.dimen.h - self.shortcut_icon.bordersize
        self.shortcut_icon:paintTo(bb, x + ix, y + iy)
    end
end

-- As done in MenuItem
function OPDSListMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    self._underline_container.focused = true
    return true
end

function OPDSListMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    self._underline_container.focused = false
    return true
end

-- The transient color inversion done in MenuItem is ugly over an image
function OPDSListMenuItem:onTapSelect()
    self.menu:onMenuSelect(self.entry)
    return true
end

function OPDSListMenuItem:onHoldSelect()
    self.menu:onMenuHold(self.entry)
    return true
end

-- Holder of the methods that replace those of the Menu instance
local OPDSListMenu = {}

function OPDSListMenu:_recalculateDimen()
    self.others_height = 0
    if self.title_bar then -- Menu:init() has been done
        if not self.is_borderless then
            self.others_height = self.others_height + 2
        end
        if not self.no_title then
            self.others_height = self.others_height + self.title_bar.dimen.h
        end
        if self.page_info then
            self.others_height = self.others_height + self.page_info:getSize().h
        end
    end
    local available_height = self.inner_dimen.h - self.others_height - Size.line.thin

    self.perpage = math.max(1,
        math.floor(available_height / scale_by_size / NOMINAL_ITEM_HEIGHT))
    if self.title_bar then
        -- Keep the first reliable value, so the item height can't drift between redraws
        self.opds_items_per_page = self.opds_items_per_page or self.perpage
        self.perpage = self.opds_items_per_page
    end

    self.page_num = math.ceil(#self.item_table / self.perpage)
    -- Fix the current page if out of range
    if self.page_num > 0 and self.page > self.page_num then self.page = self.page_num end

    self.item_height = math.floor(available_height / self.perpage) - Size.line.thin
    self.item_width = self.inner_dimen.w
    self.item_dimen = Geom:new{
        x = 0, y = 0,
        w = self.item_width,
        h = self.item_height,
    }
end

function OPDSListMenu:_updateItemsBuildUI()
    local line_widget = LineWidget:new{
        dimen = Geom:new{ w = self.width or self.screen_w, h = Size.line.thin },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
    table.insert(self.item_group, line_widget)
    local idx_offset = (self.page - 1) * self.perpage
    local select_number
    for idx = 1, self.perpage do
        local index = idx_offset + idx
        local entry = self.item_table[index]
        if entry == nil then break end
        entry.idx = index
        if index == self.itemnumber then -- focused item
            select_number = idx
        end
        local item_shortcut, shortcut_style
        if self.is_enable_shortcut then
            item_shortcut = self.item_shortcuts[idx]
            shortcut_style = (idx < 11 or idx > 20) and "square" or "grey_square"
        end

        local item_tmp = OPDSListMenuItem:new{
            height = self.item_height,
            width = self.item_width,
            entry = entry,
            show_parent = self.show_parent,
            dimen = self.item_dimen:copy(),
            shortcut = item_shortcut,
            shortcut_style = shortcut_style,
            menu = self,
            do_cover_image = self.opds_show_covers,
        }
        table.insert(self.item_group, item_tmp)
        table.insert(self.item_group, line_widget)
        table.insert(self.layout, {item_tmp})

        if item_tmp.cover_pending then
            table.insert(self.items_to_update, item_tmp)
        end
    end
    return select_number
end

function OPDSListMenu:updateItems(select_number, no_recalculate_dimen)
    local old_dimen = self.dimen and self.dimen:copy()
    -- self.layout must be updated for the focus manager
    self.layout = {}
    self.item_group:clear()
    -- As in CoverMenu: our _recalculateDimen depends on the other widgets being
    -- laid out, so run it before resetting their layout, unlike in Menu.
    if not no_recalculate_dimen then
        self:_recalculateDimen()
    end
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()

    self.items_to_update = {}
    if self.items_update_action then
        UIManager:unschedule(self.items_update_action)
        self.items_update_action = nil
    end

    self._has_cover_images = false
    select_number = self:_updateItemsBuildUI() or select_number

    self:updatePageInfo(select_number)
    Menu.mergeTitleBarIntoLayout(self)

    self.show_parent.dithered = self._has_cover_images
    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
        return "ui", refresh_dimen, self.show_parent.dithered
    end)

    if #self.items_to_update > 0 then
        self:_fetchMissingCovers()
    end
end

function OPDSListMenu:_fetchMissingCovers()
    local covers = {}
    for _, item in ipairs(self.items_to_update) do
        local cover_url = getCoverUrl(item.entry)
        if cover_url then
            table.insert(covers, cover_url)
        end
    end
    -- Launch at nextTick, so UIManager can render the page first
    UIManager:nextTick(function()
        OPDSCoverLoader:fetchInBackground(covers,
            self.root_catalog_username, self.root_catalog_password, self.root_catalog_url)
    end)

    self.items_update_action = function()
        self:_checkPendingCovers()
    end
    UIManager:scheduleIn(COVER_UPDATE_INTERVAL, self.items_update_action)
end

function OPDSListMenu:_checkPendingCovers()
    self.items_update_action = nil
    local still_fetching = OPDSCoverLoader:isFetching()
    local i = 1
    while i <= #self.items_to_update do
        local item = self.items_to_update[i]
        item.cover_pending = false
        item:update()
        if item.cover_pending then
            i = i + 1
        else
            self.show_parent.dithered = item._has_cover_image
            UIManager:setDirty(self.show_parent, function()
                return "ui", item[1].dimen, self.show_parent.dithered
            end)
            table.remove(self.items_to_update, i)
        end
    end
    if #self.items_to_update == 0 then
        logger.dbg("OPDSListMenu: all covers resolved")
    elseif still_fetching then
        self.items_update_action = function()
            self:_checkPendingCovers()
        end
        UIManager:scheduleIn(COVER_UPDATE_INTERVAL, self.items_update_action)
    else
        logger.dbg("OPDSListMenu: download finished,", #self.items_to_update, "covers unavailable")
    end
end

function OPDSListMenu:stopCoverUpdates()
    OPDSCoverLoader:stop()
    if self.items_update_action then
        UIManager:unschedule(self.items_update_action)
        self.items_update_action = nil
    end
end

function OPDSListMenu:onCloseWidget()
    self:stopCoverUpdates()
    OPDSCoverLoader:cleanUpCache()
    -- Propagate free() to our sub-widgets, to release the cover blitbuffers
    self.item_group:free()
    Menu.onCloseWidget(self)
end

return OPDSListMenu
