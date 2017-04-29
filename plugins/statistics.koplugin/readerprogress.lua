local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local LINE_COLOR = Blitbuffer.gray(0.4)
local BG_COLOR = Blitbuffer.gray(0.2)

local ReaderProgress = InputContainer:new{
    padding = Screen:scaleBySize(15),
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

local shortDayOfWeekTranslation = {
    ["Mon"] = _("Mon"),
    ["Tue"] = _("Tue"),
    ["Wed"] = _("Wed"),
    ["Thu"] = _("Thu"),
    ["Fri"] = _("Fri"),
    ["Sat"] = _("Sat"),
    ["Sun"] = _("Sun"),
}

function ReaderProgress:init()
    self.small_font_face = Font:getFace("smallffont")
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    self[1] = FrameContainer:new{
        width = self.width,
        height = self.height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(self.screen_width),
    }
end

function ReaderProgress:getTotalStats(dates)
    local total_time = 0
    local total_pages = 0
    for _, v in pairs(dates) do
        total_pages = total_pages + v. count
        total_time = total_time + v.read
    end
    return total_time, total_pages
end

function ReaderProgress:getTodayStats(dates)
    local today_time = 0
    local today_pages = 0
    local now_time = os.time()
    local today = string.format("%s (%s)",
        os.date("%Y-%m-%d", now_time),
        shortDayOfWeekTranslation[os.date("%a", now_time)])
    if dates[today] ~= nil then
        today_time = dates[today].read
        today_pages = dates[today].count
    end
    return today_time, today_pages
end

function ReaderProgress:getStatusContent(width)
    return VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = width, h = Screen:scaleBySize(30) },
            CloseButton:new{ window = self },
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
                h = 2,
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
            header_title,
            padding_span,
            line_container,
            padding_span,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(5), height = self.screen_height / 25 },
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
                h = 2,
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
        VerticalSpan:new{ width = Screen:scaleBySize(5), height = self.screen_height / 25 },
    }
end

function ReaderProgress:genWeekStats(stats_day)
    local second_in_day = 86400
    local date_format
    local date_format_show
    local select_day_time
    local diff_time
    local now_time = os.time()
    local height = Screen:scaleBySize(60)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local max_week_time = -1
    for _, v in pairs(self.dates) do
        if v.read > max_week_time then max_week_time = v.read end
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
            dimen = Geom:new{ h = Screen:scaleBySize(20) },
            padding_span
        },
    }

    for i = 1, stats_day , 1 do
        diff_time = now_time - second_in_day * (i - 1)
        date_format = string.format("%s (%s)",
            os.date("%Y-%m-%d", diff_time),
            shortDayOfWeekTranslation[os.date("%a", diff_time)])
        if self.dates[date_format] ~= nil then
            select_day_time = self.dates[date_format].read
        else
            select_day_time = 0
        end
        date_format_show = dayOfWeekTranslation[os.date("%A", diff_time)] .. os.date(" (%d.%m)", diff_time)
        local total_group = HorizontalGroup:new{
            align = "center",
            padding = 2,
            LeftContainer:new{
                dimen = Geom:new{ w = self.screen_width , h = height / 3 },
                TextWidget:new{
                    padding = 2,
                    text = date_format_show .. " - " .. util.secondsToClock(select_day_time, true),
                    face = Font:getFace("smallffont"),
                },
            },
        }
        local titles_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = self.screen_width , h = height / 3 },
                ProgressWidget:new{
                    width = (self.screen_width * 0.005) + (self.screen_width * 0.9 * select_day_time / max_week_time),
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
        dimen = Geom:new{ w = self.screen_width * 1.1 , h = self.screen_height * 0.50 },
        statistics_container,
    }
end

function ReaderProgress:genSummaryDay(width)
    local today_time, today_pages = self:getTodayStats(self.dates)
    local height = Screen:scaleBySize(60)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local tile_width = width / 4
    local tile_height = height / 3

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
            dimen = Geom:new{ h = Screen:scaleBySize(10) },
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
                text = util.secondsToClock(self.current_period, true),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = today_pages,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClock(today_time, true),
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
        dimen = Geom:new{ w = self.screen_width , h = self.screen_height * 0.13 },
        statistics_container,
    }
end

function ReaderProgress:genSummaryWeek(width)
    local height = Screen:scaleBySize(60)
    local total_time, total_pages = self:getTotalStats(self.dates)
    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local tile_width = width / 4
    local tile_height = height / 3
    local total_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                padding = 5,
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
            dimen = Geom:new{ h = Screen:scaleBySize(10) },
            padding_span
        },
    }

    local data_group = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = total_pages,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClock(math.floor(total_time), true),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = math.floor(total_pages / 7),
                face = self.medium_font_face,
            }
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = util.secondsToClock(math.floor(total_time) / 7, true),
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
        dimen = Geom:new{ w = self.screen_width , h = self.screen_height * 0.10 },
        statistics_container,
    }
end

function ReaderProgress:onAnyKeyPressed()
    return self:onClose()
end

function ReaderProgress:onClose()
    UIManager:close(self)
    return true
end

return ReaderProgress
