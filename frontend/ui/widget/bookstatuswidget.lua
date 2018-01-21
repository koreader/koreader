local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TimeVal = require("ui/timeval")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local template = require("ffi/util").template

local stats_book = {}

--[[
--Save into sdr folder addtional section
["summary"] = {
    ["rating"] = 5,
    ["note"] = "Some text",
    ["status"] = "Reading"
    ["modified"] = "24.01.2016"
},]]
local BookStatusWidget = InputContainer:new{
    padding = Size.padding.fullscreen,
    settings = nil,
    thumbnail = nil,
    props = nil,
    star = {},
    summary = {
        rating = nil,
        note = nil,
        status = "",
        modified = "",
    },
}

function BookStatusWidget:init()
    if self.settings then
        self.summary = self.settings:readSetting("summary") or {
            rating = nil,
            note = nil,
            status = "",
            modified = "",
        }
    end
    self.total_pages = self.view.document:getPageCount()
    stats_book = self:getStats()

    self.small_font_face = Font:getFace("smallffont")
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")

    local button_enabled = true
    if self.readonly then
        button_enabled = false
    end

    self.star = Button:new{
        icon = "resources/icons/stats.star.empty.png",
        bordersize = 0,
        radius = 0,
        margin = 0,
        enabled = button_enabled,
        show_parent = self,
        readonly = self.readonly,
    }
    local screen_size = Screen:getSize()
    self[1] = FrameContainer:new{
        width = screen_size.w,
        height = screen_size.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(screen_size.w),
    }
end

function BookStatusWidget:getStats()
    return {}
end

function BookStatusWidget:getStatDays()
    if stats_book.days then
        return stats_book.days
    else
        return _("N/A")
    end
end

function BookStatusWidget:getStatHours()
    if stats_book.time then
        return util.secondsToClock(stats_book.time, false)
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
    local close_button = nil
    local status_header = self:genHeader(_("Book Status"))

    if self.readonly ~= true then
        close_button = CloseButton:new{ window = self }
        status_header = self:genHeader(_("Update Status"))
    end
    local content = VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = width, h = Size.item.height_default },
            close_button,
        },
        self:genBookInfoGroup(),
        self:genHeader(_("Statistics")),
        self:genStatisticsGroup(width),
        self:genHeader(_("Review")),
        self:genSummaryGroup(width),
        status_header,
        self:generateSwitchGroup(width),
    }
    return content
end

function BookStatusWidget:genHeader(title)
    local width, height = Screen:getWidth(), Size.item.height_default

    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font_face,
        fgcolor = Blitbuffer.gray(0.4),
    }

    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = height },
        LineWidget:new{
            background = Blitbuffer.gray(0.2),
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
    local curr_time = TimeVal:now()
    self.summary.status = option_name[option_value]
    self.summary.modified = os.date("%Y-%m-%d", curr_time.sec)
    self:saveSummary()
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
    --clear previous data
    self.stars_container:clear()

    local stars_group = HorizontalGroup:new{ align = "center" }
    if num then
        self.summary.rating = num
        self:saveSummary()

        for i = 1, num do
            table.insert(stars_group, self.star:new{
                icon = "resources/icons/stats.star.full.png",
                callback = function() self:setStar(i) end
            })
        end
    else
        num = 0
    end

    for i = num + 1, 5 do
        table.insert(stars_group, self.star:new{ callback = function() self:setStar(i) end })
    end

    table.insert(self.stars_container, stars_group)

    UIManager:setDirty(nil, "partial")
    return true
end

function BookStatusWidget:genBookInfoGroup()
    local screen_width = Screen:getWidth()
    local split_span_width = screen_width * 0.05

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
    -- title
    local book_meta_info_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = height * 0.2 },
        TextBoxWidget:new{
            text = self.props.title,
            width = width,
            face = self.medium_font_face,
            alignment = "center",
        },

    }
    -- author
    local text_author = TextBoxWidget:new{
        text = self.props.authors,
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
    local read_percentage = self.view.state.page / self.total_pages
    local progress_bar = ProgressWidget:new{
        width = width * 0.7,
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
        text = template(_("%1% Completed"),
                        string.format("%1.f", read_percentage * 100)),
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
    if self.thumbnail then
        table.insert(book_info_group, ImageWidget:new{
            image = self.thumbnail,
            width = img_width,
            height = img_height,
        })
        -- dereference thumbnail since we let imagewidget manages its lifecycle
        self.thumbnail = nil
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

    local tile_width = width / 3
    local tile_height = height / 2

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
        height = height * 0.75,
        scroll = true,
        bordersize = Size.border.default,
        focused = false,
        padding = text_padding,
        parent = self,
        readonly = self.readonly,
        hint = _("A few words about the book"),
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Size.span.vertical_large },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            self.input_note
        }
    }
end

function BookStatusWidget:onUpdateNote()
    self.summary.note = self.input_note:getText()
    self:saveSummary()
    return true
end

function BookStatusWidget:saveSummary()
    if self.summary then
        self.settings:saveSetting("summary", self.summary)
        self.settings:flush()
    end
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

    local args = { "complete", "reading", "abandoned" }

    local current_status = self.summary.status
    local position = 2
    for k, v in pairs(args) do
        if v == current_status then
            position = k
        end
    end

    local config = {
        event = "ChangeBookStatus",
        default_value = 2,
        args = args,
        default_arg = "reading",
        toggle = { _("Complete"), _("Reading"), _("Abandoned") },
        values = { 1, 2, 3 },
        name = "book_status",
        alternate = false,
        enabled = true,
    }

    if self.readonly then
        config.enable = false
    end

    local switch = ToggleSwitch:new{
        width = width * 0.6,
        default_value = config.default_value,
        name = config.name,
        name_text = config.name_text,
        event = config.event,
        toggle = config.toggle,
        args = config.args,
        alternate = config.alternate,
        default_arg = config.default_arg,
        values = config.values,
        enabled = config.enable,
        config = self,
        readonly = self.readonly,
    }
    switch:setPosition(position)

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        CenterContainer:new{
            ignore = "height",
            dimen = Geom:new{ w = width, h = height },
            switch,
        }
    }
end

function BookStatusWidget:onConfigChoose(values, name, event, args, events, position)
    UIManager:scheduleIn(0.05, function()
        if values then
            self:onChangeBookStatus(args, position)
        end
        UIManager:setDirty("all")
    end)
end


function BookStatusWidget:onAnyKeyPressed()
    return self:onClose()
end

function BookStatusWidget:onClose()
    self:saveSummary()
    UIManager:setDirty("all")
    UIManager:close(self)
    return true
end

function BookStatusWidget:onSwitchFocus(inputbox)
    self.note_dialog = InputDialog:new{
        title = _("Review"),
        input = self.input_note:getText(),
        input_hint = "",
        input_type = "text",
        scroll = true,
        text_height = Screen:scaleBySize(150),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("Save review"),
                    is_enter_default = true,
                    callback = function()
                        self.input_note:setText(self.note_dialog:getInputText())
                        self:closeInputDialog()
                        self:onUpdateNote()
                    end,
                },
            },
        },
    }
    self.note_dialog:onShowKeyboard()
    UIManager:show(self.note_dialog)
end

function BookStatusWidget:closeInputDialog()
    UIManager:close(self.note_dialog)
end

return BookStatusWidget
