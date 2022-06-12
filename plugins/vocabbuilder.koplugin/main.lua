--[[--
This plugin processes dictionary word lookups and uses spaced repetition to help you remember new words.

@module koplugin.vocabbuilder
--]]--

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local DB = require("db")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification = require("ui/widget/notification")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = Device.screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local ToggleSwitch = require("ui/widget/toggleswitch")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext

-------- shared values
local word_face = Font:getFace("x_smallinfofont")
local subtitle_face = Font:getFace("cfont", 12)
local subtitle_italic_face = Font:getFace("NotoSans-Italic.ttf", 12)
local subtitle_color = Blitbuffer.COLOR_DARK_GRAY
local dim_color = Blitbuffer.Color8(0x22)
local settings = G_reader_settings:readSetting("vocabulary_builder", {enabled = true})

--[[--
Menu dialogue widget
--]]--
local MenuDialog = FocusManager:new{
    padding = Size.padding.large,
    is_edit_mode = false,
    edit_callback = nil,
    tap_close_callback = nil,
    clean_callback = nil,
    reset_callback = nil,
}

function MenuDialog:init()
    self.layout = {}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back }, doc = "close dialog" }
    end
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new {
                ges = "tap",
                range = Geom:new {
                    x = 0,
                    y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end

    local size = Screen:getSize()
    local width = math.floor(size.w * 0.8)

    -- Switch text translations could be long
    local temp_text_widget = TextWidget:new{
        text = _("Accept new words"),
        face = Font:getFace("xx_smallinfofont")
    }
    local switch_guide_width = temp_text_widget:getSize().w
    temp_text_widget:setText(_("Save context"))
    switch_guide_width = math.max(switch_guide_width, temp_text_widget:getSize().w)
    switch_guide_width = math.min(math.max(switch_guide_width, math.ceil(width*0.39)), math.ceil(width*0.61))
    temp_text_widget:free()

    local switch_width = width - switch_guide_width - Size.padding.fullscreen - Size.padding.default

    local switch = ToggleSwitch:new{
        width = switch_width,
        default_value = 2,
        name = "vocabulary_builder",
        name_text = nil, --_("Accept new words"),
        event = "ChangeEnableStatus",
        args = {"off", "on"},
        default_arg = "on",
        toggle = { _("off"), _("on") },
        values = {1, 2},
        alternate = false,
        enabled = true,
        config = self,
        readonly = self.readonly,
    }
    switch:setPosition(settings.enabled and 2 or 1)
    self:mergeLayoutInVertical(switch)

    self.context_switch = ToggleSwitch:new{
        width = switch_width,
        default_value = 1,
        name_text = nil,
        event = "ChangeContextStatus",
        args = {"off", "on"},
        default_arg = "off",
        toggle = { _("off"), _("on") },
        values = {1, 2},
        alternate = false,
        enabled = settings.enabled,
        config = self,
        readonly = self.readonly,
    }
    self.context_switch:setPosition(settings.with_context and 2 or 1)
    self:mergeLayoutInVertical(self.context_switch)

    local edit_button = {
        text = self.is_edit_mode and _("Resume") or _("Quick deletion"),
        callback = function()
            self:onClose()
            self.edit_callback()
        end
    }

    local reset_button = {
        text = _("Reset all progress"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Reset progress of all words?"),
                ok_text = _("Reset"),
                ok_callback = function()
                    DB:resetProgress()
                    self:onClose()
                    self.reset_callback()
                end
            })
        end
    }

    local clean_button = {
        text = _("Clean all words"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Clean all words including progress?"),
                ok_text = _("Clean"),
                ok_callback = function()
                    DB:purge()
                    self:onClose()
                    self.clean_callback()
                end
            })
        end,
    }

    local buttons = ButtonTable:new{
        width = width,
        buttons = {
            {edit_button},
            {reset_button},
            {clean_button}
        },
        show_parent = self
    }
    self:mergeLayoutInVertical(buttons)

    self.covers_fullscreen = true
    self[1] = CenterContainer:new{
        dimen = size,
        FrameContainer:new{
            padding = Size.padding.default,
            padding_top = Size.padding.large,
            padding_bottom = 0,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            VerticalGroup:new{
                HorizontalGroup:new{
                    RightContainer:new{
                        dimen = Geom:new{w = switch_guide_width, h = switch:getSize().h },
                        TextWidget:new{
                            text = _("Accept new words"),
                            face = Font:getFace("xx_smallinfofont"),
                            max_width = switch_guide_width
                        }
                    },
                    HorizontalSpan:new{width = Size.padding.fullscreen},
                    switch,
                },
                VerticalSpan:new{ width = Size.padding.default},
                HorizontalGroup:new{
                    RightContainer:new{
                        dimen = Geom:new{w = switch_guide_width, h = switch:getSize().h},
                        TextWidget:new{
                            text = _("Save context"),
                            face = Font:getFace("xx_smallinfofont"),
                            max_width = switch_guide_width
                        }
                    },
                    HorizontalSpan:new{width = Size.padding.fullscreen},
                    self.context_switch,
                },
                VerticalSpan:new{ width = Size.padding.large},
                LineWidget:new{
                    background = Blitbuffer.COLOR_GRAY,
                        dimen = Geom:new{
                            w = width,
                            h = Screen:scaleBySize(1),
                        }
                },

                buttons
            }
        }
    }

end

function MenuDialog:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self[1][1].dimen
    end)
end

function MenuDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function MenuDialog:onTap(_, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        -- Tap outside closes widget
        self:onClose()
        return true
    end
end

function MenuDialog:onClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function MenuDialog:onChangeContextStatus(args, position)
    settings.with_context = position == 2
    G_reader_settings:saveSetting("vocabulary_builder", settings)
end

function MenuDialog:onChangeEnableStatus(args, position)
    settings.enabled = position == 2
    self.context_switch.enabled = position == 2
    G_reader_settings:saveSetting("vocabulary_builder", settings)
end

function MenuDialog:onConfigChoose(values, name, event, args, position)
    UIManager:tickAfterNext(function()
        if values then
            if event == "ChangeEnableStatus" then
                self:onChangeEnableStatus(args, position)
            elseif event == "ChangeContextStatus" then
                self:onChangeContextStatus(args, position)
            end
        end
        UIManager:setDirty(nil, "ui", nil, true)
    end)
end


--[[--
Individual word info dialogue widget
--]]--
local WordInfoDialog = InputContainer:new{
    title = nil,
    book_title = nil,
    dates = nil,
    padding = Size.padding.large,
    margin = Size.margin.title,
    tap_close_callback = nil,
    remove_callback = nil,
    reset_callback = nil,
    dismissable = true, -- set to false if any button callback is required
}
local word_info_dialog_width
function WordInfoDialog:init()
    if self.dismissable then
        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back }, doc = "close dialog" }
        end
        if Device:isTouchDevice() then
            self.ges_events.Tap = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0,
                        y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end

    if not word_info_dialog_width then
        local temp_text = TextWidget:new{
            text = self.dates,
            padding = Size.padding.fullscreen,
            face = Font:getFace("cfont", 14)
        }
        local dates_width = temp_text:getSize().w
        temp_text:free()
        local screen_width = math.min(Screen:getWidth(), Screen:getHeight())
        word_info_dialog_width = math.floor(math.max(screen_width * 0.6, math.min(screen_width * 0.8, dates_width)))
    end
    local width = word_info_dialog_width
    local reset_button = {
        text = _("Reset progress"),
        callback = function()
            self.reset_callback()
            UIManager:close(self)
        end
    }
    local remove_button = {
        text = _("Remove word"),
        callback = function()
            self.remove_callback()
            UIManager:close(self)
        end
    }

    local focus_button = ButtonTable:new{
        width = width,
        buttons = {{reset_button, remove_button}},
        show_parent = self
    }

    local copy_button = Button:new{
        text = "", -- copy in nerdfont,
        callback = function()
            Device.input.setClipboardText(self.title)
            UIManager:show(Notification:new{
                text = _("Word copied to clipboard."),
            })
        end,
        bordersize = 0,
    }
    local has_context = self.prev_context or self.next_context
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        MovableContainer:new{
            FrameContainer:new{
                VerticalGroup:new{
                    align = "center",
                    FrameContainer:new{
                        padding = self.padding,
                        padding_top = Size.padding.buttontable,
                        padding_bottom = Size.padding.buttontable,
                        margin = self.margin,
                        bordersize = 0,
                        VerticalGroup:new {
                            align = "left",
                            HorizontalGroup:new{
                                TextWidget:new{
                                    text = self.title,
                                    max_width = width - copy_button:getSize().w - Size.padding.default,
                                    face = word_face,
                                    bold = true,
                                    alignment = self.title_align or "left",
                                },
                                HorizontalSpan:new{ width=Size.padding.default },
                                copy_button,
                            },
                            TextBoxWidget:new{
                                text = self.book_title,
                                width = width,
                                face = Font:getFace("NotoSans-Italic.ttf", 15),
                                alignment = self.title_align or "left",
                            },
                            VerticalSpan:new{width= Size.padding.default},
                            has_context and
                            TextBoxWidget:new{
                                text = "..." .. self.prev_context:gsub("\n", " ") .. "【" ..self.title.."】" .. self.next_context:gsub("\n", " ") .. "...",
                                width = width,
                                face = Font:getFace("smallffont"),
                                alignment = self.title_align or "left",
                            }
                            or VerticalSpan:new{ width = Size.padding.default },
                            VerticalSpan:new{ width = has_context and Size.padding.default or 0},
                            TextBoxWidget:new{
                                text = self.dates,
                                width = width,
                                face = Font:getFace("cfont", 14),
                                alignment = self.title_align or "left",
                                fgcolor = dim_color
                            },
                        }

                    },
                    LineWidget:new{
                        background = Blitbuffer.COLOR_GRAY,
                        dimen = Geom:new{
                            w = width + self.padding + self.margin,
                            h = Screen:scaleBySize(1),
                        }
                    },
                    focus_button
                },
                background = Blitbuffer.COLOR_WHITE,
                bordersize = Size.border.window,
                radius = Size.radius.window,
                padding = 0
            }
        }
    }

end

function WordInfoDialog:setTitle(title)
    self.title = title
    self:free()
    self:init()
    UIManager:setDirty("all", "ui")
end

function WordInfoDialog:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self[1][1].dimen
    end)
end

function WordInfoDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function WordInfoDialog:onClose()
    UIManager:close(self)
    if self.tap_close_callback then
        self.tap_close_callback()
    end
    return true
end

function WordInfoDialog:onTap(_, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        -- Tap outside closes widget
        self:onClose()
        return true
    end
end

function WordInfoDialog:paintTo(...)
    InputContainer.paintTo(self, ...)
    self.dimen = self[1][1].dimen -- FrameContainer
end



-- values useful for item cells
local ellipsis_button_width = Screen:scaleBySize(34)
local star_width = Screen:scaleBySize(25)

local point_widget = TextWidget:new{
    text = " • ",
    bold = true,
    face = Font:getFace("cfont", 24),
    fgcolor = dim_color
}

--[[--
Individual word item widget
--]]--
local VocabItemWidget = InputContainer:new{
    face = Font:getFace("smallinfofont"),
    width = nil,
    height = nil,
    review_button_width = nil,
    show_parent = nil,
    item = nil,
    forgot_button = nil,
    got_it_button = nil,
    more_button = nil,
    layout = nil
}
--[[--
    item: {
        checked_func: Block,
        review_count: interger,
        word: Text
        book_title: TEXT
        create_time: Integer
        review_time: Integer
        due_time: Integer,
        got_it_callback: function
        remove_callback: function
        is_dim: BOOL
    }
--]]--

local point_widget_height = point_widget:getSize().h
local point_widget_width = point_widget:getSize().w
local word_height = TextWidget:new{text = " ", face = word_face}:getSize().h
local subtitle_height = TextWidget:new{text = " ", face = subtitle_face}:getSize().h


function VocabItemWidget:init()
    self.layout = {}
    self.dimen = Geom:new{w = self.width, h = self.height}
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        }
    }
    self.ges_events.Hold = {
        GestureRange:new{
            ges = "hold",
            range = self.dimen,
        }
    }
    self.v_spacer = VerticalSpan:new{width = math.floor((self.height - word_height - subtitle_height)/2)}
    self.point_v_spacer = VerticalSpan:new{width = (self.v_spacer.width + word_height/2) - point_widget_height/2 }
    self.margin_span = HorizontalSpan:new{ width = Size.padding.large }
    self:initItemWidget()
end

function VocabItemWidget:initItemWidget()
    for i = 1, #self.layout do self.layout[i] = nil end
    if not self.show_parent.is_edit_mode and self.item.review_count < 6 then
        self.more_button = Button:new{
            text = (self.item.prev_context or self.item.next_context) and "⋯" or "⋮",
            padding = Size.padding.button,
            callback = function() self:showMore() end,
            width = ellipsis_button_width,
            bordersize = 0,
            show_parent = self
        }
    else
        self.more_button = IconButton:new{
            icon = "exit",
            width = star_width,
            height = star_width,
            padding = math.floor((ellipsis_button_width - star_width)/2) + Size.padding.button,
            callback = function()
                self:remover()
            end,
        }
    end


    local right_side_width
    local right_widget
    if not self.show_parent.is_edit_mode and self.item.due_time <= os.time() then
        self.has_review_buttons = true
        right_side_width = self.review_button_width * 2 + Size.padding.large * 2 + ellipsis_button_width
        self.forgot_button = Button:new{
            text = _("Forgot"),
            width = self.review_button_width,
            max_width = self.review_button_width,
            radius = Size.radius.button,
            callback = function()
                self:onForgot()
            end,
            show_parent = self,
        }

        self.got_it_button = Button:new{
            text = _("Got it"),
            radius = Size.radius.button,
            callback = function()
                self:onGotIt()
            end,
            width = self.review_button_width,
            max_width = self.review_button_width,
            show_parent = self,
        }
        right_widget = HorizontalGroup:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.margin_span,
            self.forgot_button,
            self.margin_span,
            self.got_it_button,
            self.more_button,
        }
        table.insert(self.layout, self.forgot_button)
        table.insert(self.layout, self.got_it_button)
        table.insert(self.layout, self.more_button)
    else
        self.has_review_buttons = false
        local star = IconWidget:new{
            icon = "check",
            width = star_width,
            height = star_width,
            dim = true
        }
        right_side_width =  Size.padding.large * 4 + self.item.review_count * (star:getSize().w)

        if self.item.review_count > 0 then
            right_widget = HorizontalGroup:new {
                dimen = Geom:new{w=0, h = self.height}
            }
            for i=1, self.item.review_count, 1 do
                table.insert(right_widget, star)
            end
        else
            star:free()
            right_widget = HorizontalGroup:new{
                dimen = Geom:new{w=0, h = self.height},
                 HorizontalSpan:new {width = Size.padding.default }
            }
        end
        table.insert(right_widget, self.margin_span)
        table.insert(right_widget, self.more_button)
        table.insert(self.layout, self.more_button)
    end

    local text_max_width = self.width - point_widget_width - right_side_width

    local subtitle_prefix = TextWidget:new{
        text = BD.mirroredUILayout() and self:getTimeSinceDue() .. _("From ") or self:getTimeSinceDue() .. _("From ") ,
        face = subtitle_face,
        fgcolor = subtitle_color
    }

    local word_widget = Button:new{
        text = self.item.word,
        bordersize = 0,
        callback = function() self.item.callback(self.item) end,
        padding = 0,
        max_width = math.ceil(math.max(5,text_max_width - Size.padding.fullscreen))
    }

    if self.item.is_dim then
        word_widget.label_widget.fgcolor = dim_color
    end

    table.insert(self.layout, 1, word_widget)

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        HorizontalGroup:new{
            dimen = Geom:new{
                w = self.width,
                h = self.height,
            },
            HorizontalGroup:new{
                dimen = Geom:new{
                    w = self.width - right_side_width,
                    h = self.height,
                },
                VerticalGroup:new{
                    dimen = Geom:new{w = point_widget_width, h = self.height},
                    self.point_v_spacer,
                    point_widget,
                    VerticalSpan:new { width = self.height - point_widget_height - self.point_v_spacer.width}
                },
                VerticalGroup:new{
                    dimen = Geom:new{
                        w = text_max_width,
                        h = self.height,
                    },
                    self.v_spacer,
                    LeftContainer:new{
                        dimen = Geom:new{w = text_max_width, h = word_height},
                        word_widget
                    },
                    LeftContainer:new{
                        dimen = Geom:new{w = text_max_width, h = math.floor(self.height - word_height - self.v_spacer.width*2.2)},
                        HorizontalGroup:new{
                            subtitle_prefix,
                            TextWidget:new{
                                text = self.item.book_title,
                                face = subtitle_italic_face,
                                max_width = math.ceil(math.max(5,text_max_width - subtitle_prefix:getSize().w - Size.padding.fullscreen)),
                                fgcolor = subtitle_color
                            }
                        }
                    },
                    self.v_spacer
                }

            },
            RightContainer:new{
                dimen = Geom:new{ w = right_side_width+Size.padding.default, h = self.height},
                right_widget
            }
        },
    }
end

function VocabItemWidget:getTimeSinceDue()
    if self.item.review_count >= 8 then return "" end

    local elapsed = os.time() - self.item.due_time
    local abs = math.abs(elapsed)
    local readable_time

    local rounding = elapsed > 0 and math.floor or math.ceil
    if abs < 60 then
        readable_time = abs .. C_("Time", "s")
    elseif abs < 3600 then
        readable_time = string.format("%d"..C_("Time", "m"), rounding(abs/60))
    elseif abs < 3600 * 24 then
        readable_time = string.format("%d"..C_("Time", "h"), rounding(abs/3600))
    else
        readable_time = string.format("%d"..C_("Time", "d"), rounding(abs/3600/24))
    end

    if elapsed < 0 then
        return " " .. readable_time .. " | " --hourglass
    else
        return readable_time .. " | "
    end
end

function VocabItemWidget:remover()
    self.item.remove_callback(self.item)
    self.show_parent:removeAt(self.index)
end

function VocabItemWidget:resetProgress()
    self.item.review_count = 0
    self.item.due_time = os.time()
    self.item.review_time = self.item.due_time
    self:initItemWidget()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self[1].dimen end)
end

function VocabItemWidget:removeAndClose()
    self:remover()
    UIManager:close(self.dialogue)
end

function VocabItemWidget:showMore()
    local dialogue = WordInfoDialog:new{
        title = self.item.word,
        book_title = self.item.book_title,
        dates = _("Added on") .. " " .. os.date("%Y-%m-%d", self.item.create_time) .. " | " ..
        _("Review scheduled at") .. " " .. os.date("%Y-%m-%d %H:%M", self.item.due_time),
        prev_context = self.item.prev_context,
        next_context = self.item.next_context,
        remove_callback = function()
            self:remover()
        end,
        reset_callback = function()
            self:resetProgress()
        end,
        show_parent = self
    }

    UIManager:show(dialogue)
end

function VocabItemWidget:onTap(_, ges)
    if self.has_review_buttons then
        if ges.pos.x > self.forgot_button.dimen.x and ges.pos.x < self.forgot_button.dimen.x + self.forgot_button.dimen.w then
            self:onForgot()
        elseif ges.pos.x > self.got_it_button.dimen.x and ges.pos.x < self.got_it_button.dimen.x + self.got_it_button.dimen.w then
            self:onGotIt()
        elseif ges.pos.x > self.more_button.dimen.x and ges.pos.x < self.more_button.dimen.x + self.more_button.dimen.w then
            if self.item.review_count < 6 then
                self:showMore()
            else
                self:remover()
            end
        elseif self.item.callback then
            self.item.callback(self.item)
        end
    else
        if BD.mirroredUILayout() then
            if ges.pos.x > self.more_button.dimen.x and ges.pos.x < self.more_button.dimen.x + self.more_button.dimen.w * 2 then
                if self.show_parent.is_edit_mode or self.item.review_count >= 6 then
                    self:remover()
                else
                    self:showMore()
                end
            elseif self.item.callback then
                self.item.callback(self.item)
            end
        else
            if ges.pos.x > self.more_button.dimen.x - self.more_button.dimen.w and ges.pos.x < self.more_button.dimen.x + self.more_button.dimen.w then
                if self.show_parent.is_edit_mode or self.item.review_count >= 6 then
                    self:remover()
                else
                    self:showMore()
                end
            elseif self.item.callback then
                self.item.callback(self.item)
            end
        end
    end
    return true
end

function VocabItemWidget:onHold(_, ges)
    self:onTap(_, ges)
    return true
end

function VocabItemWidget:onGotIt()
    self.item.got_it_callback(self.item)
    self.item.is_dim = true
    self:initItemWidget()
    if self.show_parent.selected.x == 3 then
        self.show_parent.selected.x = 1
    end
    UIManager:setDirty(self.show_parent, function()
    return "ui", self[1].dimen end)
end

function VocabItemWidget:onForgot(no_lookup)
    self.item.forgot_callback(self.item)
    self.item.is_dim = false
    self:initItemWidget()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self[1].dimen end)
    if not no_lookup and  self.item.callback then
        self.item.callback(self.item)
    end
end



--[[--
Container widget. Same as sortwidget
--]]--
local VocabularyBuilderWidget = FocusManager:new{
    title = "",
    width = nil,
    height = nil,
    -- index for the first item to show
    show_page = 1,
    -- table of items
    item_table = nil, -- mandatory (array)
    is_edit_mode = false,
    callback = nil,
}

function VocabularyBuilderWidget:init()
    self.layout = {}

    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back }, doc = "close dialog" }
        self.key_events.NextPage = { { Device.input.group.PgFwd}, doc = "next page"}
        self.key_events.PrevPage = { { Device.input.group.PgBack}, doc = "prev page"}
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = function() return self.dimen end,
            }
        }
    end
    local padding = Size.padding.large
    self.width_widget = self.dimen.w - 2 * padding
    self.item_width = self.dimen.w - 2 * padding
    self.footer_center_width = math.floor(self.width_widget * 32 / 100)
    self.footer_button_width = math.floor(self.width_widget * 12 / 100)
    -- group for footer
    local chevron_left = "chevron.left"
    local chevron_right = "chevron.right"
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_left, chevron_right = chevron_right, chevron_left
        chevron_first, chevron_last = chevron_last, chevron_first
    end
    self.footer_left = Button:new{
        icon = chevron_left,
        width = self.footer_button_width,
        callback = function() self:prevPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_right = Button:new{
        icon = chevron_right,
        width = self.footer_button_width,
        callback = function() self:nextPage() end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_first_up = Button:new{
        icon = chevron_first,
        width = self.footer_button_width,
        callback = function()
            self:goToPage(1)
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }
    self.footer_last_down = Button:new{
        icon = chevron_last,
        width = self.footer_button_width,
        callback = function()
            self:goToPage(self.pages)
        end,
        bordersize = 0,
        radius = 0,
        show_parent = self,
    }

    self.footer_page = Button:new{
        text = "",
        hold_input = {
            title = _("Enter page number"),
            hint_func = function()
                return "(" .. "1 - " .. self.pages .. ")"
            end,
            type = "number",
            deny_blank_input = true,
            callback = function(input)
                local page = tonumber(input)
                if page and page >= 1 and page <= self.pages then
                    self:goToPage(page)
                end
            end,
            ok_text = _("Go to page"),
        },
        call_hold_input_on_tap = true,
        bordersize = 0,
        margin = 0,
        text_font_face = "pgfont",
        text_font_bold = false,
        width = self.footer_center_width,
        show_parent = self,
    }
    self.page_info = HorizontalGroup:new{
        self.footer_first_up,
        self.footer_left,
        self.footer_page,
        self.footer_right,
        self.footer_last_down,
    }

    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.item_width, h = Size.line.thick },
        background = Blitbuffer.COLOR_LIGHT_GRAY,
    }
    local vertical_footer = VerticalGroup:new{
        bottom_line,
        self.page_info,
    }
    self.footer_height = vertical_footer:getSize().h
    local footer = BottomContainer:new{
        dimen = self.dimen:copy(),
        vertical_footer,
    }
    -- setup title bar
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        align = "center",
        title_face = Font:getFace("smallinfofontbold"),
        bottom_line_color = Blitbuffer.COLOR_LIGHT_GRAY,
        with_bottom_line = true,
        bottom_line_h_padding = padding,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        title = self.title,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    self:setupItemHeight()
    self.main_content = VerticalGroup:new{}

    -- calculate item's review button width once
    local temp_button = Button:new{
        text = _("Got it"),
        padding_h = Size.padding.large
    }
    self.review_button_width = temp_button:getSize().w
    temp_button:setText(_("Forgot"))
    self.review_button_width = math.min(math.max(self.review_button_width, temp_button:getSize().w), Screen:getWidth()/4)
    temp_button:free()

    self:_populateItems()

    local frame_content = FrameContainer:new{
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.title_bar,
            self.main_content,
        },
    }
    local content = OverlapGroup:new{
        dimen = self.dimen:copy(),
        frame_content,
        footer,
    }
    -- assemble page
    self[1] = FrameContainer:new{
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
end

function VocabularyBuilderWidget:setupItemHeight()
    local item_height = Screen:scaleBySize(self.is_edit_mode and 54 or 72)
    self.item_height = item_height
    self.item_margin = math.floor(self.item_height / 8)
    local line_height = self.item_height + self.item_margin
    local content_height = self.dimen.h - self.title_bar:getHeight() - self.footer_height - Size.padding.large
    self.items_per_page = math.floor(content_height / line_height)
    self.item_margin = self.item_margin + math.floor((content_height - self.items_per_page * line_height ) / self.items_per_page )
    self.pages = math.ceil(DB:selectCount() / self.items_per_page)
    self.show_page = math.min(self.pages, self.show_page)
end

function VocabularyBuilderWidget:nextPage()
    local new_page = self.show_page == self.pages and 1 or self.show_page + 1
    self.show_page = new_page
    self:_populateItems()
end

function VocabularyBuilderWidget:prevPage()
    local new_page = self.show_page == 1 and self.pages or self.show_page - 1
    self.show_page = new_page
    self:_populateItems()
end

function VocabularyBuilderWidget:goToPage(page)
    self.show_page = page
    self:_populateItems()
end

function VocabularyBuilderWidget:moveItem(diff)
    local move_to = diff
    if move_to > 0 and move_to <= #self.item_table then
        self.show_page = math.ceil(move_to / self.items_per_page)
        self:_populateItems()
    end
end

function VocabularyBuilderWidget:removeAt(index)
    if index > #self.item_table then return end
    table.remove(self.item_table, index)
    self.show_page = math.ceil(math.min(index, #self.item_table) / self.items_per_page)
    self.pages = math.ceil(#self.item_table / self.items_per_page)
    self:_populateItems()
end

-- make sure self.item_margin and self.item_height are set before calling this
function VocabularyBuilderWidget:_populateItems()
    self.main_content:clear()
    self.layout = {{self.title_bar.left_button, self.title_bar.right_button}} -- title
    local idx_offset = (self.show_page - 1) * self.items_per_page
    local page_last
    if idx_offset + self.items_per_page <= #self.item_table then
        page_last = idx_offset + self.items_per_page
    else
        page_last = #self.item_table
    end

    if self.select_items_callback then
        self.select_items_callback(self.item_table ,idx_offset, page_last)
    end

    for idx = idx_offset + 1, page_last do
        table.insert(self.main_content, VerticalSpan:new{ width = self.item_margin / (idx == idx_offset+1 and 2 or 1) })
        if #self.item_table == 0 or not self.item_table[idx].word then break end
        local item = VocabItemWidget:new{
            height = self.item_height,
            width = self.item_width,
            review_button_width = self.review_button_width,
            item = self.item_table[idx],
            index = idx,
            show_parent = self,
        }
        table.insert(self.layout, #self.layout, item.layout)
        table.insert(
            self.main_content,
            item
        )
    end
    self.footer_page:setText(T(_("Page %1 of %2"), self.show_page, self.pages), self.footer_center_width)
    if self.pages > 1 then
        self.footer_page:enable()
    else
        self.footer_page:disableWithoutDimming()
    end
    if self.pages == 0 then
        self.footer_page:setText(_("No items"), self.footer_center_width)
        self.footer_first_up:hide()
        self.footer_last_down:hide()
        self.footer_left:hide()
        self.footer_right:hide()
    end
    local chevron_first = "chevron.first"
    local chevron_last = "chevron.last"
    if BD.mirroredUILayout() then
        chevron_first, chevron_last = chevron_last, chevron_first
    end

    self.footer_first_up:setIcon(chevron_first, self.footer_button_width)
    self.footer_last_down:setIcon(chevron_last, self.footer_button_width)
    self.footer_left:enableDisable(self.show_page > 1)
    self.footer_right:enableDisable(self.show_page < self.pages)
    self.footer_first_up:enableDisable(self.show_page > 1)
    self.footer_last_down:enableDisable(self.show_page < self.pages)
    if not self.layout[self.selected.y] or not self.layout[self.selected.y][self.selected.x] then
        self.selected = {x=1, y=1}
    end
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function VocabularyBuilderWidget:gotItFromDict(word)
    for i = 1, #self.main_content, 1 do
        if self.main_content[i].item and self.main_content[i].item.word == word then
            self.main_content[i]:onGotIt()
            return
        end
    end
end

function VocabularyBuilderWidget:forgotFromDict(word)
    for i = 1, #self.main_content, 1 do
        if self.main_content[i].item and self.main_content[i].item.word == word then
            self.main_content[i]:onForgot(true)
            return
        end
    end
end

function VocabularyBuilderWidget:resetItems()
    for i, item in ipairs(self.item_table) do
        if self.item_table[i].word then -- selected from DB
            self.item_table[i] = {
                callback = self.item_table[i].callback
            }
        end
    end
    self:_populateItems()
end

function VocabularyBuilderWidget:showMenu()
    UIManager:show(MenuDialog:new{
        is_edit_mode = self.is_edit_mode,
        edit_callback = function()
            self.is_edit_mode = not self.is_edit_mode
            self:setupItemHeight()
            self:_populateItems()
        end,
        clean_callback = function()
            self.item_table = {}
            self.pages = 0
            self:_populateItems()
        end,
        reset_callback = function()
            self:resetItems()
        end,
    })
end

function VocabularyBuilderWidget:onShow()
    UIManager:setDirty(self, "flashui")
end

function VocabularyBuilderWidget:onNextPage()
    self:nextPage()
    return true
end

function VocabularyBuilderWidget:onPrevPage()
    self:prevPage()
    return true
end

function VocabularyBuilderWidget:onSwipe(arg, ges_ev)
    local direction = BD.flipDirectionIfMirroredUILayout(ges_ev.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
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

function VocabularyBuilderWidget:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function VocabularyBuilderWidget:onClose()
    DB:batchUpdateItems(self.item_table)
    UIManager:close(self)
    -- UIManager:setDirty(self, "ui")
    return true
end

function VocabularyBuilderWidget:onCancel()
    self:goToPage(self.show_page)
    return true
end

function VocabularyBuilderWidget:onReturn()
    return self:onClose()
end


--[[--
Item shown in main menu
--]]--
local VocabBuilder = WidgetContainer:new{
    name = "vocabulary_builder",
    is_doc_only = false
}

function VocabBuilder:init()
    self.ui.menu:registerToMainMenu(self)
end

function VocabBuilder:addToMainMenu(menu_items)
    menu_items.vocabbuilder = {
        text = _("Vocabulary builder"),
        callback = function()
            local vocab_items = {}
            for i = 1, DB:selectCount() do
                table.insert(vocab_items, {
                    callback = function(item)
                        -- custom button table
                        local tweak_buttons_func
                        if item.due_time <= os.time() then
                            tweak_buttons_func = function(buttons)
                                local tweaked_button_count = 0
                                local early_break
                                for j = 1, #buttons do
                                    for k = 1, #buttons[j] do
                                        if buttons[j][k].id == "highlight" and not buttons[j][k].enabled then
                                            buttons[j][k] = {
                                                id = "got_it",
                                                text = _("Got it"),
                                                callback = function()
                                                    self.builder_widget:gotItFromDict(item.word)
                                                    UIManager:sendEvent(Event:new("Close"))
                                                end
                                            }
                                            if tweaked_button_count == 1 then
                                                early_break = true
                                                break
                                            end
                                            tweaked_button_count = tweaked_button_count + 1
                                        elseif buttons[j][k].id == "search" and not buttons[j][k].enabled then
                                            buttons[j][k] = {
                                                id = "forgot",
                                                text = _("Forgot"),
                                                callback = function()
                                                    self.builder_widget:forgotFromDict(item.word)
                                                    UIManager:sendEvent(Event:new("Close"))
                                                end
                                            }
                                            if tweaked_button_count == 1 then
                                                early_break = true
                                                break
                                            end
                                            tweaked_button_count = tweaked_button_count + 1
                                        end
                                    end
                                    if early_break then break end
                                end
                            end
                        end

                        self.builder_widget.current_lookup_word = item.word
                        self.ui:handleEvent(Event:new("LookupWord", item.word, true, nil, nil, nil, tweak_buttons_func))
                    end
                })
            end

            self.builder_widget = VocabularyBuilderWidget:new{
                title = _("Vocabulary builder"),
                item_table = vocab_items,
                select_items_callback = function(items, start_idx, end_idx)
                    DB:select_items(items, start_idx, end_idx)
                end
            }

            UIManager:show(self.builder_widget)
        end
    }
end

-- Event sent by readerdictionary "WordLookedUp"
function VocabBuilder:onWordLookedUp(word, title)
    if not settings.enabled then return end
    if self.builder_widget and self.builder_widget.current_lookup_word == word then return true end
    local prev_context
    local next_context
    if settings.with_context then
        prev_context, next_context = self.ui.highlight:getSelectedWordContext(15)
    end
    DB:insertOrUpdate({
        book_title = title,
        time = os.time(),
        word = word,
        prev_context = prev_context,
        next_context = next_context
    })
    return true
end

return VocabBuilder
