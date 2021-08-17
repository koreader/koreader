local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local LINE_COLOR = Blitbuffer.COLOR_WEB_GRAY
local BG_COLOR = Blitbuffer.COLOR_LIGHT_GRAY

local ReaderProgress = InputContainer:new{
    padding = Size.padding.fullscreen,
}

local dayOfWeekTranslation = {
    ["Monday"] = _("Monday"),
    ["Tuesday"] = _("Tuesday"),
    ["Wednesday"] = _("Wednesday"),
    ["Thursday"] = _("Thursday"),
    ["Friday"] = _("Friday"),
    ["Saturday"] = _("Saturday"),
    ["Sunday"] = _("Sunday"),
}

function ReaderProgress:init()
    self.current_pages = tostring(self.current_pages)
    self.today_pages = tostring(self.today_pages)
    self.small_font_face = Font:getFace("smallffont")
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    if self.screen_width < self.screen_height then
        self.header_span = 25
        self.stats_span = 20
    else
        self.header_span = 0
        self.stats_span = 10
    end
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    if Device:hasKeys() then
        self.key_events = {
            --don't get locked in on non touch devices
            AnyKeyPressed = { { Device.input.group.Any },
            seqtext = "any key", doc = "close dialog" }
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            }
        }
    end
    self.covers_fullscreen = true -- hint for UIManager:_repaint()
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(self.screen_width),
    }
end

function ReaderProgress:getTotalStats(stats_day)
    local total_time = 0
    local total_pages = 0
    for i=1, stats_day do
        total_pages = total_pages + self.dates[i][1]
        total_time = total_time + self.dates[i][2]
    end
    return total_time, total_pages
end

function ReaderProgress:getStatusContent(width)
    local close_button = nil
    if self.readonly ~= true then
        close_button = CloseButton:new{ window = self }
    end
    return VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = width, h = Size.item.height_default },
            close_button,
        },
        self:genSingleHeader(_("Last week")),
        self:genSummaryWeek(width),
        self:genSingleHeader(_("Week progress")),
        self:genWeekStats(7),
        self:genDoubleHeader(_("Current"), _("Today") ),
        self:genSummaryDay(width),
    }
end

function ReaderProgress:genSingleHeader(title)
    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font_face,
        fgcolor = LINE_COLOR,
    }
    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (self.screen_width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = self.screen_height / 25 },
        LineWidget:new{
            background = BG_COLOR,
            dimen = Geom:new{
                w = line_width,
                h = Size.line.thick,
            }
        }
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(self.header_span), height = self.screen_height / 25 },
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
        VerticalSpan:new{ width = Size.span.vertical_large, height = self.screen_height / 25 },
    }
end

function ReaderProgress:genDoubleHeader(title_left, title_right)
    local header_title_left = TextWidget:new{
        text = title_left,
        face = self.medium_font_face,
        fgcolor = LINE_COLOR,
    }
    local header_title_right = TextWidget:new{
        text = title_right,
        face = self.medium_font_face,
        fgcolor = LINE_COLOR,
    }
    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (self.screen_width - header_title_left:getSize().w - header_title_right:getSize().w - self.padding * 7) / 4
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = self.screen_height / 25 },
        LineWidget:new{
            background = BG_COLOR,
            dimen = Geom:new{
                w = line_width,
                h = Size.line.thick,
            }
        }
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(25), height = self.screen_height / 25 },
        HorizontalGroup:new{
            align = "center",
            padding_span,
            line_container,
            padding_span,
            header_title_left,
            padding_span,
            line_container,
            padding_span,
            line_container,
            padding_span,
            header_title_right,
            padding_span,
            line_container,
            padding_span,
        },
        VerticalSpan:new{ width = Size.span.vertical_large, height = self.screen_height / 25 },
    }
end

function ReaderProgress:genWeekStats(stats_day)
    local second_in_day = 86400
    local date_format_show
    local select_day_time
    local diff_time
    local now_time = os.time()
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    local height = Screen:scaleBySize(60)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local max_week_time = -1
    local day_time
    for i=1, stats_day do
        day_time = self.dates[i][2]
        if day_time > max_week_time then max_week_time = day_time end
    end
    local top_padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    local top_span_group = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ h = Screen:scaleBySize(30) },
            top_padding_span
        },
    }
    table.insert(statistics_group, top_span_group)

    local padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    local span_group = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ h = Screen:scaleBySize(self.stats_span) },
            padding_span
        },
    }

    local j = 1
    for i = 1, stats_day do
        diff_time = now_time - second_in_day * (i - 1)
        if self.dates[j][3] == os.date("%Y-%m-%d", diff_time) then
            select_day_time = self.dates[j][2]
            j = j + 1
        else
            select_day_time = 0
        end
        date_format_show = dayOfWeekTranslation[os.date("%A", diff_time)] .. os.date(" (%d.%m)", diff_time)
        local total_group = HorizontalGroup:new{
            align = "center",
            padding = Size.padding.small,
            LeftContainer:new{
                dimen = Geom:new{ w = self.screen_width , h = height / 3 },
                TextWidget:new{
                    padding = Size.padding.small,
                    text = date_format_show .. " - " .. util.secondsToClockDuration(user_duration_format, select_day_time, true),
                    face = Font:getFace("smallffont"),
                },
            },
        }
        local titles_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = self.screen_width , h = height / 3 },
                ProgressWidget:new{
                    width = math.floor((self.screen_width * 0.005) + (self.screen_width * 0.9 * select_day_time / max_week_time)),
                    height = Screen:scaleBySize(14),
                    percentage = 1.0,
                    ticks = nil,
                    last = nil,
                    margin_h = 0,
                    margin_v = 0,
                }
            },
        }
        table.insert(statistics_group, total_group)
        table.insert(statistics_group, titles_group)
        table.insert(statistics_group, span_group)
    end  --for i=1
    table.insert(statistics_container, statistics_group)
    return CenterContainer:new{
        dimen = Geom:new{ w = math.floor(self.screen_width * 1.1), h = math.floor(self.screen_height * 0.5) },
        statistics_container,
    }
end

function ReaderProgress:genSummaryDay(width)
    local height = Screen:scaleBySize(60)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local tile_width = width / 4
    local tile_height = height / 3
    local user_duration_format = G_reader_settings:readSetting("duration_format")

    local titles_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Pages"),
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
                text = _("Pages"),
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
    }

    local padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    local span_group = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ h = Size.span.horizontal_default },
            padding_span
        },
    }

    local data_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self.current_pages,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClockDuration(user_duration_format, self.current_duration, true),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self.today_pages,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClockDuration(user_duration_format, self.today_duration, true),
                face = self.medium_font_face,
            },
        },
    }
    table.insert(statistics_group, titles_group)
    table.insert(statistics_group, span_group)
    table.insert(statistics_group, data_group)
    table.insert(statistics_group, span_group)
    table.insert(statistics_group, span_group)
    table.insert(statistics_container, statistics_group)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = math.floor(self.screen_height * 0.13) },
        statistics_container,
    }
end

function ReaderProgress:genSummaryWeek(width)
    local height = Screen:scaleBySize(60)
    local total_time, total_pages = self:getTotalStats(#self.dates)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local tile_width = width / 4
    local tile_height = height / 3
    local user_duration_format = G_reader_settings:readSetting("duration_format")
    local total_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                padding = Size.padding.default,
                text = _("Total"),
                face = self.small_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Total"),
                face = self.small_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Average"),
                face = self.small_font_face,
            }
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Average"),
                face = self.small_font_face,
            }
        }
    }

    local titles_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Pages"),
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
                text = _("Pages"),
                face = self.small_font_face,
            }
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = _("Time"),
                face = self.small_font_face,
            }
        }
    }

    local padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    local span_group = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ h = Size.span.horizontal_default },
            padding_span
        },
    }

    local data_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = tostring(total_pages),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClockDuration(user_duration_format, math.floor(total_time), true),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = tostring(math.floor(total_pages / 7)),
                face = self.medium_font_face,
            }
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClockDuration(user_duration_format, math.floor(total_time) / 7, true),
                face = self.medium_font_face,
            }
        }
    }
    table.insert(statistics_group, total_group)
    table.insert(statistics_group, titles_group)
    table.insert(statistics_group, span_group)
    table.insert(statistics_group, data_group)
    table.insert(statistics_container, statistics_group)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = math.floor(self.screen_height * 0.10) },
        statistics_container,
    }
end

function ReaderProgress:onAnyKeyPressed()
    return self:onClose()
end

function ReaderProgress:onSwipe(arg, ges_ev)
    if ges_ev.direction == "south" then
        -- Allow easier closing with swipe up/down
        self:onClose()
    elseif ges_ev.direction == "east" or ges_ev.direction == "west" or ges_ev.direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function ReaderProgress:onClose()
    UIManager:close(self)
    return true
end

return ReaderProgress
