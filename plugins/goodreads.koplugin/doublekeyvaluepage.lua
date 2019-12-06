local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CloseButton = require("ui/widget/closebutton")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local GoodreadsApi = require("goodreadsapi")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/topcontainer")
local LineWidget = require("ui/widget/linewidget")
local LuaSettings = require("luasettings")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

local DoubleKeyValueTitle = VerticalGroup:new{
    kv_page = nil,
    title = "",
    tface = Font:getFace("tfont"),
    align = "left",
    use_top_page_count = false,
}

function DoubleKeyValueTitle:init()
    self.close_button = CloseButton:new{ window = self }
    local btn_width = self.close_button:getSize().w
    -- title and close button
    table.insert(self, OverlapGroup:new{
        dimen = { w = self.width },
        TextWidget:new{
            text = self.title,
            max_width = self.width - btn_width,
            face = self.tface,
        },
        self.close_button,
    })
    -- page count and separation line
    self.title_bottom = OverlapGroup:new{
        dimen = { w = self.width, h = Screen:scaleBySize(2) },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Screen:scaleBySize(2) },
            background = Blitbuffer.COLOR_DARK_GRAY,
            style = "solid",
        },
    }
    if self.use_top_page_count then
        self.page_cnt = FrameContainer:new{
            padding = Size.padding.default,
            margin = 0,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            -- overlap offset x will be updated in setPageCount method
            overlap_offset = {0, -15},
            TextWidget:new{
                text = "",  -- page count
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                face = Font:getFace("smallffont"),
            },
        }
        table.insert(self.title_bottom, self.page_cnt)
    end
    table.insert(self, self.title_bottom)
    table.insert(self, VerticalSpan:new{ width = Screen:scaleBySize(5) })
end

function DoubleKeyValueTitle:setPageCount(curr, total)
    if total == 1 then
        -- remove page count if there is only one page
        table.remove(self.title_bottom, 2)
        return
    end
    self.page_cnt[1]:setText(curr .. "/" .. total)
    self.page_cnt.overlap_offset[1] = (self.width - self.page_cnt:getSize().w - 10)
    self.title_bottom[2] = self.page_cnt
end

function DoubleKeyValueTitle:onClose()
    self.kv_page:onClose()
    return true
end

local DoubleKeyValueItem = InputContainer:new{
    key = nil,
    value = nil,
    cface_up = Font:getFace("smallinfofont"),
    cface_down = Font:getFace("xx_smallinfofont"),
    width = nil,
    height = nil,
    align = "left",
}

function DoubleKeyValueItem:init()
    self.dimen = Geom:new{align = "left", w = self.width, h = self.height}
    if self.callback and Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
    local padding = Screen:scaleBySize(20)
    local max_width = self.width - 2*padding
    local h = self.dimen.h / 2
    local w = self.dimen.w
    self[1] = FrameContainer:new{
        padding = padding,
        bordersize = 0,
        width = self.width,
        height = self.height,
        VerticalGroup:new{
            LeftContainer:new{
                padding = 0,
                dimen = Geom:new{ h = h, w = w },
                TextWidget:new{
                    text = self.value,
                    max_width = max_width,
                    face = self.cface_up,
                }
            },
            LeftContainer:new{
                padding = 0,
                dimen = Geom:new{ h = h, w = w },
                TextWidget:new{
                    text = self.key,
                    max_width = max_width,
                    face = self.cface_down,
                }
            }
        }
    }
end

function DoubleKeyValueItem:onTap()
    if self.callback then
        local info = InfoMessage:new{text = _("Please wait…")}
        UIManager:show(info)
        if G_reader_settings:isFalse("flash_ui") then
            UIManager:forceRePaint()
            self.callback()
            UIManager:close(info)
        else
            self[1].invert = true
            UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
            UIManager:setDirty(nil, function()
                return "fast", self[1].dimen
            end)
            UIManager:tickAfterNext(function()
                self.callback()
                UIManager:close(info)
                self[1].invert = false
                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                UIManager:setDirty(nil, function()
                    return "ui", self[1].dimen
                end)
            end)
        end
    end
    return true
end

local DoubleKeyValuePage = InputContainer:new{
    title = "",
    width = nil,
    height = nil,
    show_page = 1,
    use_top_page_count = false,
    text_input = "",
    pages = 1,
    goodreads_key = "",
}

function DoubleKeyValuePage:readGRSettings()
    self.gr_settings = LuaSettings:open(DataStorage:getSettingsDir().."/goodreadssettings.lua")
    return self.gr_settings
end

function DoubleKeyValuePage:saveGRSettings(setting)
    if not self.gr_settings then self:readGRSettings() end
    self.gr_settings:saveSetting("goodreads", setting)
    self.gr_settings:flush()
end

function DoubleKeyValuePage:init()
    self.screen_width = Screen:getSize().w
    self.screen_height = Screen:getSize().h
    local gr_sett = self:readGRSettings().data
    if gr_sett.goodreads then
        self.goodreads_key = gr_sett.goodreads.key
        self.goodreads_secret = gr_sett.goodreads.secret
    end
    self.kv_pairs = GoodreadsApi:showData(self.text_input, self.search_type, 1, self.goodreads_key)
    self.total_res = GoodreadsApi:getTotalResults()
    if self.total_res == nil then
        self.total_res = 0
    end
    self.total_res = tonumber(self.total_res)
    if self.kv_pairs == nil then
        self.kv_pairs = {}
    end
    self.dimen = Geom:new{
        w = self.width or self.screen_width,
        h = self.height or self.screen_height,
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close page" },
            NextPage = {{Input.group.PgFwd}, doc = "next page"},
            PrevPage = {{Input.group.PgBack}, doc = "prev page"},
        }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end
    self.page_info_text = Button:new{
        text = "",
        bordersize = 0,
        margin = Screen:scaleBySize(20),
        text_font_face = "pgfont",
        text_font_bold = false,
    }
    -- group for page info
    local chevron_left = "resources/icons/appbar.chevron.left.png"
    local chevron_right = "resources/icons/appbar.chevron.right.png"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
    end
    self.page_info_left_chev = Button:new{
        icon = chevron_left,
        callback = function() self:prevPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_right_chev = Button:new{
        icon = chevron_right,
        callback = function() self:nextPage() end,
        bordersize = 0,
        show_parent = self,
    }
    self.page_info_spacer = HorizontalSpan:new{
        width = Screen:scaleBySize(32),
    }

    self.page_info_left_chev:hide()
    self.page_info_right_chev:hide()

    self.page_info = HorizontalGroup:new{
        self.page_info_left_chev,
        self.page_info_text,
        self.page_info_right_chev,
    }

    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        self.page_info,
    }

    local padding = Screen:scaleBySize(10)
    self.item_width = self.dimen.w - 2 * padding
    self.item_height = Screen:scaleBySize(55)
    -- setup title bar
    self.title_bar = DoubleKeyValueTitle:new{
        title = self.title,
        width = self.item_width,
        height = self.item_height,
        use_top_page_count = self.use_top_page_count,
        kv_page = self,
    }
    -- setup main content
    self.item_margin = self.item_height / 6
    local line_height = self.item_height + 2 * self.item_margin
    local content_height = self.dimen.h - self.title_bar:getSize().h - self.page_info:getSize().h
    self.max_loaded_pages = 1
    self.items_per_page = math.floor(content_height / line_height)
    self.pages = math.ceil(self.total_res / self.items_per_page)
    self.main_content = VerticalGroup:new{}
    self:_populateItems()

    local content = OverlapGroup:new{
        dimen = self.dimen:copy(),
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            self.main_content,
        },
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

function DoubleKeyValuePage:nextPage()
    local new_page = math.min(self.show_page + 1, self.pages)
    if (new_page * self.items_per_page > #self.kv_pairs) and (self.max_loaded_pages < new_page)
        and #self.kv_pairs < self.total_res then
        local api_page = math.floor(new_page * self.items_per_page / 20 ) + 1
        -- load new portion of data
        local new_pair = GoodreadsApi:showData(self.text_input, self.search_type, api_page, self.goodreads_key )
        if new_pair == nil then return end
        for _, v in pairs(new_pair) do
            table.insert(self.kv_pairs, v)
        end
    end
    if new_page > self.show_page then
        if self.max_loaded_pages == self.show_page then
            self.max_loaded_pages = self.max_loaded_pages + 1
        end
        self.show_page = new_page
        self:_populateItems()
    end
end

function DoubleKeyValuePage:prevPage()
    local new_page = math.max(self.show_page - 1, 1)
    if new_page < self.show_page then
        self.show_page = new_page
        self:_populateItems()
    end
end

-- make sure self.item_margin and self.item_height are set before calling this
function DoubleKeyValuePage:_populateItems()
    self.page_info:resetLayout()
    self.main_content:clear()
    local idx_offset = (self.show_page - 1) * self.items_per_page
    for idx = 1, self.items_per_page do
        local entry = self.kv_pairs[idx_offset + idx]
        if entry == nil then break end
        table.insert(self.main_content,
                     VerticalSpan:new{ align = "left", width = self.item_margin })
        if type(entry) == "table" then
            table.insert(
                self.main_content,
                DoubleKeyValueItem:new{
                    height = self.item_height,
                    width = self.item_width,
                    key = entry[1],
                    value = entry[2],
                    align = "left",
                    callback = entry.callback,
                    show_parent = self,
                }
            )
        elseif type(entry) == "string" then
            local c = string.sub(entry, 1, 1)
            if c == "-" then
                table.insert(self.main_content, LineWidget:new{
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    dimen = Geom:new{
                        w = self.item_width,
                        h = Screen:scaleBySize(2)
                    },
                    style = "solid",
                })
            end
        end
        table.insert(self.main_content,
                     VerticalSpan:new{ width = self.item_margin })
    end
    self.page_info_text:setText(T(_("Page %1 of %2"), self.show_page, self.pages))
    self.page_info_left_chev:showHide(self.pages > 1)
    self.page_info_right_chev:showHide(self.pages > 1)
    self.page_info_left_chev:enableDisable(self.show_page > 1)
    self.page_info_right_chev:enableDisable(self.show_page < self.pages)

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function DoubleKeyValuePage:_nextPage()
    local new_page = math.min(self.show_page + 1, self.pages)
    if (new_page * self.items_per_page > #self.kv_pairs) and (self.max_loaded_pages < new_page)
        and #self.kv_pairs < self.total_res  then
        local info = InfoMessage:new{text = _("Please wait…")}
        UIManager:show(info)
        UIManager:forceRePaint()
        self:nextPage()
        UIManager:close(info)
    else
        self:nextPage()
    end
end

function DoubleKeyValuePage:onNextPage()
    self:_nextPage()
    return true
end

function DoubleKeyValuePage:onPrevPage()
    self:prevPage()
    return true
end

function DoubleKeyValuePage:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:_nextPage()
        return true
    elseif direction == "east" then
        self:prevPage()
        return true
    elseif direction == "south" then
        -- Allow easier closing with swipe down
        self:onClose()
    elseif direction == "north" then
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

function DoubleKeyValuePage:onClose()
    UIManager:close(self)
    return true
end

return DoubleKeyValuePage
