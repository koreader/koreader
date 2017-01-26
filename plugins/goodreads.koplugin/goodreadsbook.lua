local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local CloseButton = require("ui/widget/closebutton")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Font = require("ui/font")
local _ = require("gettext")
local T = require("ffi/util").template
local Pic = require("ffi/pic")

local GoodreadsBook = InputContainer:new{
    padding = Screen:scaleBySize(15),
}

function GoodreadsBook:init()
    self.small_font_face = Font:getFace("ffont", 16)
    self.medium_font_face = Font:getFace("ffont", 18)
    self.large_font_face = Font:getFace("ffont", 22)
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    self[1] = FrameContainer:new{
        width = self.screen_width,
        height = self.screen_height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(self.screen_width),
    }
end

function GoodreadsBook:getStatusContent(width)
    return VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = width, h = Screen:scaleBySize(30) },
            CloseButton:new{ window = self },
        },
        self:genHeader(_("Book info")),
        self:genBookInfoGroup(),
        self:genHeader(_("Review")),
        self:bookReview(),
    }
end

function GoodreadsBook:genHeader(title)
    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font_face,
        fgcolor = Blitbuffer.gray(0.4),
    }
    local padding_span = HorizontalSpan:new{ width = self.padding}
    local line_width = (self.screen_width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = self.screen_height / 25 },
        LineWidget:new{
            background = Blitbuffer.gray(0.2),
            dimen = Geom:new{
                w = line_width,
                h = 2,
            }
        }
    }

    return VerticalGroup:new{
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
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

function GoodreadsBook:genBookInfoGroup()
    local split_span_width = self.screen_width * 0.05
    local img_width, img_height
    if Screen:getScreenMode() == "landscape" then
        img_width = Screen:scaleBySize(132)
        img_height = Screen:scaleBySize(184)
    else
        img_width = Screen:scaleBySize(132 * 1.5)
        img_height = Screen:scaleBySize(184 * 1.5)
    end
    local height = img_height
    local width = self.screen_width - 1.5 * split_span_width - img_width
    -- title
    local book_meta_info_group = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = self.dates.title,
            face = self.medium_font_face,
            padding = 2,
            alignment = "center",
            width = width,
        },
    }
    -- author
    local text_author = TextBoxWidget:new{
        text = self.dates.author,
        width = width,
        face = self.large_font_face,
        alignment = "center",
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_author:getSize().h },
            text_author
        }
    )
    --span
    local span_author = VerticalSpan:new{ width = height * 0.1 }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = Screen:scaleBySize(10) },
            span_author
        }
    )
    -- series
    local text_series = TextWidget:new{
        text = T(_("Series: %1"), self.dates.series),
        face = self.small_font_face,
        padding = 2,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_series:getSize().h },
            text_series
        }
    )
    -- rating
    local text_rating = TextWidget:new{
        text = T(_("Rating: %1"), self.dates.rating),
        face = self.small_font_face,
        padding = 2,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_rating:getSize().h },
            text_rating
        }
    )
    -- pages
    local text_pages = TextWidget:new{
        text = T(_("Pages: %1"), self.dates.pages),
        face = self.small_font_face,
        padding = 2,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_pages:getSize().h },
            text_pages
        }
    )
    -- relesse date
    local text_release = TextWidget:new{
        text = T(_("Release date: %1"), self.dates.release),
        face = self.small_font_face,
        padding = 2,
    }
    table.insert(book_meta_info_group,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = text_release:getSize().h },
            text_release
        }
    )
    local book_info_group = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width =  split_span_width }
    }
    --thumbnail
    local http = require("socket.http")
    local body = http.request(self.dates.image)
    local image = false
    if body then image = Pic.openJPGDocumentFromMem(body) end
    if image then
        table.insert(book_info_group, ImageWidget:new{
            image = image.image_bb,
            width = img_width,
            height = img_height,
        })
    else
        table.insert(book_info_group, ImageWidget:new{
            file = "resources/goodreadsnophoto.png",
            width = img_width,
            height = img_height,
        })
    end

    local book_info_group_span = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width =  split_span_width / 2 }
    }
    table.insert(book_info_group, book_info_group_span)
    table.insert(book_info_group, CenterContainer:new{
        dimen = Geom:new{ w = width  , h = height },
        book_meta_info_group,
    })
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width, h = self.screen_height * 0.35 },
        book_info_group,
    }
end

function GoodreadsBook:bookReview()
    local book_meta_info_group = VerticalGroup:new{
        align = "center",
        padding = 0,
        bordersize = 0,
        ScrollTextWidget:new{
            text = self.dates.description,
            face = self.medium_font_face,
            padding = 0,
            width = self.screen_width * 0.9,
            height = self.screen_height * 0.48,
            dialog = self,
        }
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width, h = self.screen_height * 0.50 },
        book_meta_info_group,
    }
end

function GoodreadsBook:onAnyKeyPressed()
    return self:onClose()
end

function GoodreadsBook:onClose()
    UIManager:setDirty("all")
    UIManager:close(self)
    return true
end

return GoodreadsBook
