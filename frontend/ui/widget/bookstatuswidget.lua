local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
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
local BookStatusWidget = InputContainer:new{
    padding = Screen:scaleBySize(15),
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

function BookStatusWidget:init()
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

function BookStatusWidget:showStatus()
    local screen_width = Screen:getWidth()
    return VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(30) },
            CloseButton:new{ window = self },
        },
        self:genBookInfoGroup(),
        self:genHeader(_("Statistics")),
        self:genStatisticsGroup(screen_width),
        self:genHeader(_("Review")),
        self:genSummaryGroup(screen_width),
        self:genHeader(_("Update Status")),
        self:generateSwitchGroup(screen_width),
    }
end

function BookStatusWidget:getStatDays(stats)
    if stats and stats.performance_in_pages then
        local dates = {}
        for k, v in pairs(stats.performance_in_pages) do
            dates[os.date("%Y-%m-%d", k)] = ""
        end
        return util.tableSize(dates)
    end
    return "none"
end

function BookStatusWidget:getStatHours(stats)
    if stats and stats.total_time_in_sec then
        return util.secondsToClock(stats.total_time_in_sec, false)
    end
    return "none"
end

function BookStatusWidget:getReadPages(stats)
    if stats and stats.performance_in_pages and stats.pages then
        return util.tableSize(stats.performance_in_pages) .. "/" .. stats.pages
    end
    return "none"
end

function BookStatusWidget:genHeader(title)
    local width, height = Screen:getWidth(), Screen:scaleBySize(35)

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
                h = 2,
            }
        }
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(25) },
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
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
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
    local text_author = TextWidget:new{
        text = self.props.authors,
        face = self.small_font_face,
        padding = 2,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_author:getSize().h },
            text_author
        }
    )
    -- progress bar
    local total_pages = self.document:getPageCount()
    local read_percentage = self.view.state.page / total_pages
    local progress_bar = ProgressWidget:new{
        width = width * 0.7,
        height = Screen:scaleBySize(10),
        percentage = read_percentage,
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
            autoscale = false,
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
                text = self:getStatDays(self.stats),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self:getStatHours(self.stats),
                face = self.medium_font_face,
            },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = tile_width, h = tile_height },
            TextWidget:new{
                text = self:getReadPages(self.stats),
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
        height = Screen:scaleBySize(60)
    else
        height = Screen:scaleBySize(130)
    end

    local text_padding = 5
    self.input_note = InputText:new{
        text = self.summary.note,
        face = self.medium_font_face,
        width = width - self.padding * 3,
        height = height * 0.75,
        scroll = true,
        bordersize = 2,
        focused = false,
        padding = text_padding,
        parent = self,
        hint = _("A few words about the book"),
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
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
        if v == curent_status then
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

function BookStatusWidget:getStatisticsSettings()
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


function BookStatusWidget:onSwitchFocus(inputbox)
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

function BookStatusWidget:closeInputDialog()
    self.note_dialog:onClose()
    UIManager:close(self.note_dialog)
end

return BookStatusWidget
