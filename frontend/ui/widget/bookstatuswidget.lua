local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local stats_book = {}

--[[
-- Stored in the sidecar metadata, in a dedicated table:
["summary"] = {
    ["rating"] = 5,
    ["note"] = "Some text",
    ["status"] = "Reading"
    ["modified"] = "24.01.2016"
},]]
local BookStatusWidget = FocusManager:extend{
    padding = Size.padding.fullscreen,
    star = nil, -- Button
    summary = nil, -- hash
}

function BookStatusWidget:init()
    self.updated = nil
    self.layout = {}
    self.summary = self.ui.doc_settings:readSetting("summary")
    self.total_pages = self.ui.document:getPageCount()
    stats_book = self:getStats()

    self.small_font_face = Font:getFace("smallffont")
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")

    self.star = Button:new{
        icon = "star.empty",
        bordersize = 0,
        radius = 0,
        margin = 0,
        enabled = not self.readonly,
        show_parent = self,
        readonly = self.readonly,
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = function() return self.dimen end,
            }
        }
    end

    local screen_size = Screen:getSize()
    self.covers_fullscreen = true -- hint for UIManager:_repaint()
    self[1] = FrameContainer:new{
        width = screen_size.w,
        height = screen_size.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(screen_size.w),
    }

    self.dithered = true
end

function BookStatusWidget:getStats()
    return {}
end

function BookStatusWidget:getStatDays()
    if stats_book.days then
        return tostring(stats_book.days)
    else
        return _("N/A")
    end
end

function BookStatusWidget:getStatHours()
    if stats_book.time then
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        return datetime.secondsToClockDuration(user_duration_format, stats_book.time, false)
    else
        return _("N/A")
    end
end

function BookStatusWidget:getStatReadPages()
    if stats_book.pages then
        return string.format("%s/%s",stats_book.pages, self.total_pages)
    else
        return _("N/A")
    end
end

function BookStatusWidget:getStatusContent(width)
    local title_bar = TitleBar:new{
        width = width,
        bottom_v_padding = 0,
        close_callback = not self.readonly and function() self:onClose() end,
        show_parent = self,
    }
    local content = VerticalGroup:new{
        align = "left",
        title_bar,
        self:genBookInfoGroup(),
        self:genHeader(_("Statistics")),
        self:genStatisticsGroup(width),
        self:genHeader(_("Review")),
        self:genSummaryGroup(width),
        self:genHeader(self.readonly and _("Book Status") or _("Update Status")),
        self:generateSwitchGroup(width),
    }
    return content
end

function BookStatusWidget:genHeader(title)
    local width, height = Screen:getWidth(), Size.item.height_default

    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font_face,
        fgcolor = Blitbuffer.COLOR_GRAY_9,
    }

    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = height },
        LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{
                w = line_width,
                h = Size.line.thick,
            }
        }
    }
    local span_top, span_bottom
    if Screen:getScreenMode() == "landscape" then
        span_top = VerticalSpan:new{ width = Size.span.horizontal_default }
        span_bottom = VerticalSpan:new{ width = Size.span.horizontal_default }
    else
        span_top = VerticalSpan:new{ width = Size.item.height_default }
        span_bottom = VerticalSpan:new{ width = Size.span.vertical_large }
    end

    return VerticalGroup:new{
        span_top,
        HorizontalGroup:new{
            align = "center",
            padding_span,
            line_container,
            padding_span,
            header_title,
            padding_span,
            line_container,
            padding_span,
        },
        span_bottom,
    }
end

function BookStatusWidget:onChangeBookStatus(option_name, option_value)
    self.summary.status = option_name[option_value]
    self.summary.modified = os.date("%Y-%m-%d", os.time())
    self.updated = true
    return true
end

function BookStatusWidget:generateRateGroup(width, height, rating)
    self.stars_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }

    self:setStar(rating)
    return self.stars_container
end

function BookStatusWidget:setStar(num)
    -- clear previous data
    self.stars_container:clear()

    local stars_group = HorizontalGroup:new{ align = "center" }
    local row = {}
    if num then
        self.summary.rating = num
        self.updated = true

        for i = 1, num do
            local star = self.star:new{
                icon = "star.full",
                callback = function() self:setStar(i) end
            }
            table.insert(stars_group, star)
            table.insert(row, star)
        end
    else
        num = 0
    end

    for i = num + 1, 5 do
        local star = self.star:new{ callback = function() self:setStar(i) end }
        table.insert(stars_group, star)
        table.insert(row, star)
    end
    self.layout[1] = row

    table.insert(self.stars_container, stars_group)

    -- Individual stars are Button, w/ flash_ui, they'll have their own flash.
    -- And we need to redraw the full widget, because we don't know the coordinates of stars_container :/.
    self:refocusWidget()
    UIManager:setDirty(self, "ui", nil, true)
    return true
end

function BookStatusWidget:genBookInfoGroup()
    local screen_width = Screen:getWidth()
    local split_span_width = math.floor(screen_width * 0.05)

    local img_width, img_height
    if Screen:getScreenMode() == "landscape" then
        img_width = Screen:scaleBySize(132)
        img_height = Screen:scaleBySize(184)
    else
        img_width = Screen:scaleBySize(132 * 1.5)
        img_height = Screen:scaleBySize(184 * 1.5)
    end

    local height = img_height
    local width = screen_width - split_span_width - img_width

    -- Get a chance to have title and authors rendered with alternate
    -- glyphs for the book language
    local props = self.ui.doc_props
    local lang = props.language
    -- title
    local book_meta_info_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = height * 0.2 },
        TextBoxWidget:new{
            text = props.display_title,
            lang = lang,
            width = width,
            face = self.medium_font_face,
            alignment = "center",
        },

    }
    -- author
    local text_author = TextBoxWidget:new{
        text = props.authors,
        lang = lang,
        face = self.small_font_face,
        width = width,
        alignment = "center",
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_author:getSize().h },
            text_author
        }
    )
    -- progress bar
    local read_percentage = self.ui:getCurrentPage() / self.total_pages
    local progress_bar = ProgressWidget:new{
        width = math.floor(width * 0.7),
        height = Screen:scaleBySize(10),
        percentage = read_percentage,
        ticks = nil,
        last = nil,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = progress_bar:getSize().h },
            progress_bar
        }
    )
    -- complete text
    local text_complete = TextWidget:new{
        text = T(_("%1\xE2\x80\xAF% Completed"), string.format("%1.f", read_percentage * 100)),
        face = self.small_font_face,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_complete:getSize().h },
            text_complete
        }
    )
    -- rating
    table.insert(book_meta_info_group,
                 VerticalSpan:new{ width = Screen:scaleBySize(30) })
    local rateHeight = Screen:scaleBySize(60)
    table.insert(book_meta_info_group,
                 self:generateRateGroup(screen_width, rateHeight, self.summary.rating))

    -- build the final group
    local book_info_group = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width =  split_span_width }
    }
    -- thumbnail
    local thumbnail = FileManagerBookInfo:getCoverImage(self.ui.document)
    if thumbnail then
        -- Much like BookInfoManager, honor AR here
        local cbb_w, cbb_h = thumbnail:getWidth(), thumbnail:getHeight()
        if cbb_w > img_width or cbb_h > img_height then
            local scale_factor = math.min(img_width / cbb_w, img_height / cbb_h)
            cbb_w = math.min(math.floor(cbb_w * scale_factor)+1, img_width)
            cbb_h = math.min(math.floor(cbb_h * scale_factor)+1, img_height)
            thumbnail = RenderImage:scaleBlitBuffer(thumbnail, cbb_w, cbb_h, true)
        end
        table.insert(book_info_group, ImageWidget:new{
            image = thumbnail,
            width = cbb_w,
            height = cbb_h,
        })
    end

    table.insert(book_info_group, CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        book_meta_info_group,
    })

    return CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = img_height },
        book_info_group,
    }
end

function BookStatusWidget:genStatisticsGroup(width)
    local height = Screen:scaleBySize(60)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }

    local statistics_group = VerticalGroup:new{ align = "left" }

    local tile_width = width * (1/3)
    local tile_height = height * (1/2)

    local titles_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Days"),
                face = self.small_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Time"),
                face = self.small_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Read pages"),
                face = self.small_font_face,
            }
        }
    }

    local data_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self:getStatDays(),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self:getStatHours(),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self:getStatReadPages(),
                face = self.medium_font_face,
            }
        }
    }

    table.insert(statistics_group, titles_group)
    table.insert(statistics_group, data_group)

    table.insert(statistics_container, statistics_group)
    return statistics_container
end

function BookStatusWidget:genSummaryGroup(width)
    local height
    if Screen:getScreenMode() == "landscape" then
        height = Screen:scaleBySize(80)
    else
        height = Screen:scaleBySize(160)
    end

    local text_padding = Size.padding.default
    self.input_note = InputText:new{
        text = self.summary.note,
        face = self.medium_font_face,
        width = width - self.padding * 3,
        height = math.floor(height * 0.75),
        scroll = true,
        bordersize = Size.border.default,
        focused = false,
        padding = text_padding,
        parent = self,
        readonly = self.readonly,
        hint = _("A few words about the book"),
    }
    table.insert(self.layout, {self.input_note})

    return VerticalGroup:new{
        VerticalSpan:new{ width = Size.span.vertical_large },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            self.input_note
        }
    }
end

function BookStatusWidget:generateSwitchGroup(width)
    local height
    if Screen:getScreenMode() == "landscape" then
        -- landscape mode
        height = Screen:scaleBySize(60)
    else
        -- portrait mode
        height = Screen:scaleBySize(105)
    end

    local switch = ToggleSwitch:new{
        width = math.floor(width * 0.6),
        toggle = { _("Reading"), _("On hold"), _("Finished"), },
        args = { "reading", "abandoned", "complete", },
        values = { 1, 2, 3, },
        enabled = not self.readonly,
        config = self,
        readonly = self.readonly,
    }
    local position = util.arrayContains(switch.args, self.summary.status) or 1
    switch:setPosition(position)
    self:mergeLayoutInVertical(switch)

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        CenterContainer:new{
            ignore = "height",
            dimen = Geom:new{ w = width, h = height },
            switch,
        }
    }
end

function BookStatusWidget:onConfigChoose(values, name, event, args, position)
    UIManager:tickAfterNext(function()
        self:onChangeBookStatus(args, position)
        UIManager:setDirty(nil, "ui", nil, true)
    end)
end

function BookStatusWidget:onSwipe(arg, ges_ev)
    if ges_ev.direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif ges_ev.direction == "east" or ges_ev.direction == "west" or ges_ev.direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full", nil, true)
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function BookStatusWidget:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function BookStatusWidget:onClose()
    if self.updated then
        self.ui.doc_settings:flush()
    end
    -- NOTE: Flash on close to avoid ghosting, since we show an image.
    UIManager:close(self, "flashpartial")
    return true
end

function BookStatusWidget:onSwitchFocus(inputbox)
    self.note_dialog = InputDialog:new{
        title = _("Review"),
        input = self.input_note:getText(),
        scroll = true,
        allow_newline = true,
        text_height = Screen:scaleBySize(150),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("Save review"),
                    is_enter_default = true,
                    callback = function()
                        local note = self.note_dialog:getInputText()
                        self.input_note:setText(note)
                        self.summary.note = note
                        self.updated = true
                        self:closeInputDialog()
                    end,
                },
            },
        },
    }
    UIManager:show(self.note_dialog)
    self.note_dialog:onShowKeyboard()
end

function BookStatusWidget:closeInputDialog()
    UIManager:close(self.note_dialog)
    self.input_note:onUnfocus()
end

return BookStatusWidget
