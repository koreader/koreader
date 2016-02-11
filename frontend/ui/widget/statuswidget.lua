local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local InputText = require("ui/widget/inputtext")
local ToggleSwitch = require("ui/widget/toggleswitch")
local Button = require("ui/widget/button")
local ProgressWidget = require("ui/widget/progresswidget")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")

local CloseButton = require("ui/widget/closebutton")
local InputDialog = require("ui/widget/inputdialog")

local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Font = require("ui/font")
local TimeVal = require("ui/timeval")
local RenderText = require("ui/rendertext")

local template = require("ffi/util").template
local util = require("util")
local _ = require("gettext")

--[[
--Save into sdr folder addtional section
["summary"] = {
    ["rating"] = 5,
    ["note"] = "Some text",
    ["status"] = "Reading"
    ["modified"] = "24.01.2016"
},]]
local StatusWidget = InputContainer:new{
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
    stats = {
        total_time_in_sec = 0,
        performance_in_pages = {},
        pages = 0,
    }
}

function StatusWidget:init()
    self.stats.pages = self.document:getPageCount()
    self:getStatisticsSettings()
    if self.settings then
        self.summary = self.settings:readSetting("summary")
    end

    self.small_font_face = Font:getFace("ffont", 15)
    self.medium_font_face = Font:getFace("ffont", 20)
    self.large_font_face = Font:getFace("ffont", 25)

    self.star = Button:new{
        icon = "resources/icons/stats.star.empty.png",
        bordersize = 0,
        radius = 0,
        margin = 0,
        enabled = true,
        show_parent = self,
    }

    local statusContainer = FrameContainer:new{
        dimen = Screen:getSize(),
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:showStatus(),
    }
    self[1] = statusContainer
end

function StatusWidget:showStatus()
    local main_group = VerticalGroup:new{ align = "left" }

    local img_width = Screen:scaleBySize(132 * 1.5)
    local img_height = Screen:scaleBySize(184 * 1.5)

    if Screen:getScreenMode() == "landscape" then
        img_width = Screen:scaleBySize(132)
        img_height = Screen:scaleBySize(184)
    end

    local thumb = nil
    if self.thumbnail then
        thumb = ImageWidget:new{
            image = self.thumbnail,
            width = img_width,
            height = img_height,
            autoscale = false,
        }
    end

    local screen_width = Screen:getWidth()

    local cover_with_title_and_author_container = CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = img_height },
    }

    local cover_with_title_and_author_group = HorizontalGroup:new{ align = "top" }

    local span = HorizontalSpan:new{ width = screen_width * 0.05 }

    table.insert(cover_with_title_and_author_group, span)

    if self.thumbnail then
        table.insert(cover_with_title_and_author_group, thumb)
    end
    table.insert(cover_with_title_and_author_group,
        self:generateTitleAuthorProgressGroup(screen_width - span.width - img_width,
            img_height,
            self.props.title,
            self.props.authors,
            self.document:getCurrentPage(),
            self.document:getPageCount()))
    table.insert(cover_with_title_and_author_container, cover_with_title_and_author_group)

    --portrait mode
    local rateHeight = Screen:scaleBySize(60)
    local statisticsHeight = Screen:scaleBySize(60)
    local summaryHeight = Screen:scaleBySize(140)
    local statusHeight = Screen:scaleBySize(105)

    --landscape mode
    if Screen:getScreenMode() == "landscape" then
        summaryHeight = Screen:scaleBySize(70)
        statusHeight = Screen:scaleBySize(60)
    end

    local header_group = HorizontalGroup:new{
        align = "center",
        self:addHeader(screen_width * 0.95, Screen:scaleBySize(15), _("Progress")),
        CloseButton:new{ window = self }
    }

    table.insert(main_group, header_group)
    table.insert(main_group, cover_with_title_and_author_container)
    table.insert(main_group, self:addHeader(screen_width, Screen:scaleBySize(25), _("Rate")))
    table.insert(main_group, self:generateRateGroup(screen_width, rateHeight, self.summary.rating))
    table.insert(main_group, self:addHeader(screen_width, Screen:scaleBySize(35), _("Statistics")))
    table.insert(main_group, self:generateStatisticsGroup(screen_width, statisticsHeight,
        self:getStatDays(self.stats), self:getStatHours(self.stats), self:getReadPages(self.stats)))
    table.insert(main_group, self:addHeader(screen_width, Screen:scaleBySize(35), _("Review")))
    table.insert(main_group, self:generateSummaryGroup(screen_width, summaryHeight, self.summary.note))
    table.insert(main_group, self:addHeader(screen_width, Screen:scaleBySize(25), _("Update Status")))
    table.insert(main_group, self:generateSwitchGroup(screen_width, statusHeight, self.summary.status))
    return main_group
end

function StatusWidget:getStatDays(stats)
    if stats and stats.performance_in_pages then
        local dates = {}
        for k, v in pairs(stats.performance_in_pages) do
            dates[os.date("%Y-%m-%d", k)] = ""
        end
        return util.tableSize(dates)
    end
    return "none"
end


function StatusWidget:getStatHours(stats)
    if stats and stats.total_time_in_sec then
        return util.secondsToClock(stats.total_time_in_sec, false)
    end
    return "none"
end


function StatusWidget:getReadPages(stats)
    if stats and stats.performance_in_pages and stats.pages then
        return util.tableSize(stats.performance_in_pages) .. "/" .. stats.pages
    end
    return "none"
end

function StatusWidget:addHeader(width, height, title)
    local group = HorizontalGroup:new{
        align = "center",
        bordersize = 0,
    }

    local bold = false

    local titleWidget = TextWidget:new{
        text = title,
        face = self.large_font_face,
        bold = bold,
    }
    local titleSize = RenderText:sizeUtf8Text(0, Screen:getWidth(), self.large_font_face, title, true, bold)
    local lineWidth = ((width - titleSize.x) * 0.5)

    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = lineWidth, h = height },
        LineWidget:new{
            background = Blitbuffer.gray(0.2),
            dimen = Geom:new{
                w = lineWidth,
                h = 2,
            }
        }
    }

    local text_container = CenterContainer:new{
        dimen = Geom:new{ w = titleSize.x, h = height },
        titleWidget,
    }

    table.insert(group, line_container)
    table.insert(group, text_container)
    table.insert(group, line_container)
    return group
end

function StatusWidget:generateSwitchGroup(width, height, book_status)
    local switch_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }

    local args = {
        [1] = "complete",
        [2] = "reading",
        [3] = "abandoned",
    }

    local position = 2
    for k, v in pairs(args) do
        if v == book_status then
            position = k
        end
    end

    local config = {
        event = "ChangeBookStatus",
        default_value = 2,
        toggle = {
            [1] = _("Complete"),
            [2] = _("Reading"),
            [3] = _("Abandoned"),
        },
        args = args,
        default_arg = "reading",
        values = {
            [1] = 1,
            [2] = 2,
            [3] = 3,
        },
        name = "book_status",
        alternate = false,
        enabled = true,
    }

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
    }

    switch:setPosition(position)

    table.insert(switch_container, switch)
    return switch_container
end

function StatusWidget:onConfigChoose(values, name, event, args, events, position)
    UIManager:scheduleIn(0.05, function()
        if values then
            self:onChangeBookStatus(args, position)
        end
        UIManager:setDirty("all")
    end)
end

function StatusWidget:onChangeBookStatus(option_name, option_value)
    local curr_time = TimeVal:now()
    self.summary.status = option_name[option_value]
    self.summary.modified = os.date("%Y-%m-%d", curr_time.sec)
    self:saveSummary()
    return true
end

function StatusWidget:onUpdateNote()
    self.summary.note = self.input_note:getText()
    self:saveSummary()
    return true
end


function StatusWidget:saveSummary()
    self.settings:saveSetting("summary", self.summary)
    self.settings:flush()
end


function StatusWidget:generateSummaryGroup(width, height, text)

    self.input_note = InputText:new{
        text = text,
        face = self.medium_font_face,
        width = width * 0.95,
        height = height * 0.55,
        scroll = true,
        focused = false,
        margin = 5,
        padding = 0,
        parent = self,
        hint = _("A few words about the book"),
    }

    local note_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        self.input_note
    }
    return note_container
end

function StatusWidget:generateRateGroup(width, height, rating)
    self.stars_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }

    self:setStar(rating)
    return self.stars_container
end

function StatusWidget:setStar(num)
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

function StatusWidget:generateStatisticsGroup(width, height, days, average, pages)
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
                text = days,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = average,
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = pages,
                face = self.medium_font_face,
            }
        }
    }

    table.insert(statistics_group, titles_group)
    table.insert(statistics_group, data_group)

    table.insert(statistics_container, statistics_group)
    return statistics_container
end

function StatusWidget:generateTitleAuthorProgressGroup(width, height, title, authors, current_page, total_pages)

    local title_author_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
    }

    local title_author_progressbar_group = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = height * 0.2 },
        TextBoxWidget:new{
            text = title,
            width = width,
            face = self.medium_font_face,
            alignment = "center",
        }
    }
    local text_author = TextWidget:new{
        text = authors,
        face = self.small_font_face,
        padding = 2,
    }

    local author_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = text_author:getSize().h },
        text_author
    }

    table.insert(title_author_progressbar_group, author_container)

    local read_percentage = current_page / total_pages
    local progress_height = Screen:scaleBySize(10)

    local progress_bar = ProgressWidget:new{
        width = width * 0.7,
        height = progress_height,
        percentage = read_percentage,
        ticks = {},
        tick_width = 0,
        last = total_pages,
    }

    table.insert(title_author_progressbar_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = progress_bar:getSize().h },
            progress_bar
        }
    )
    local text_complete = TextWidget:new{
        text = template(_("%1% Completed"),
                        string.format("%1.f", read_percentage * 100)),
        face = self.small_font_face,
    }

    local progress_bar_text_container = CenterContainer:new{
        dimen = Geom:new{ w = width, h = text_complete:getSize().h },
        text_complete
    }

    table.insert(title_author_progressbar_group, progress_bar_text_container)
    table.insert(title_author_container, title_author_progressbar_group)
    return title_author_container
end


function StatusWidget:onAnyKeyPressed()
    return self:onClose()
end

function StatusWidget:onClose()
    self:saveSummary()
    UIManager:setDirty("all")
    UIManager:close(self)
    return true
end

function StatusWidget:getStatisticsSettings()
    if self.settings then
        local stats = self.settings:readSetting("stats")
        if stats then
            self.stats.total_time_in_sec = self.stats.total_time_in_sec + stats.total_time_in_sec
            for k, v in pairs(stats.performance_in_pages) do
                self.stats.performance_in_pages[k] = v
            end
        end
    end
end


function StatusWidget:onSwitchFocus(inputbox)
    self.note_dialog = InputDialog:new{
        title = "Note",
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
                    text = _("OK"),
                    callback = function()
                        self.input_note:setText(self.note_dialog:getInputText())
                        self:closeInputDialog()
                        self:onUpdateNote()
                    end,
                },
            },
        },
        enter_callback = function()
            self:closeInputDialog()
        end,
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.note_dialog:onShowKeyboard()
    UIManager:show(self.note_dialog)
end

function StatusWidget:closeInputDialog()
    self.note_dialog:onClose()
    UIManager:close(self.note_dialog)
end

return StatusWidget

