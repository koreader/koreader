--[[--
This plugin processes dictionary word lookups and uses spaced repetition to help you remember new words.

@module koplugin.vocabbuilder
--]]--

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local DB = require("db")
local Button = require("ui/widget/button")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DictQuickLookUp = require("ui/widget/dictquicklookup")
local Dispatcher = require("dispatcher")
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
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification = require("ui/widget/notification")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Screen = Device.screen
local Size = require("ui/size")
local SortWidget = require("ui/widget/sortwidget")
local SyncService = require("frontend/apps/cloudstorage/syncservice")
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
local dim_color = Blitbuffer.COLOR_GRAY_3
local settings = G_reader_settings:readSetting("vocabulary_builder", {enabled = false, with_context = true})

local function resetButtonOnLookupWindow()
    if not settings.enabled then -- auto add words
        DictQuickLookUp.tweak_buttons_func = function(obj, buttons)
            if obj.is_wiki_fullpage then
                return
            elseif obj.is_wiki then
                -- make wiki window have the same button_tweak as its presenting dictionary window
                local widget = UIManager:getNthTopWidget(2)
                if widget and widget.tweak_buttons_func then
                    widget:tweak_buttons_func(buttons)
                end
                return
            end
            table.insert(buttons, 1, {{
                id = "vocabulary",
                text = _("Add to vocabulary builder"),
                font_bold = false,
                callback = function()
                    local book_title = obj.ui.doc_settings and obj.ui.doc_settings:readSetting("doc_props").title or _("Dictionary lookup")
                    if book_title == "" then -- no or empty metadata title
                        if obj.ui.document and obj.ui.document.file then
                            local util = require("util")
                            local directory, filename = util.splitFilePathName(obj.ui.document.file) -- luacheck: no unused
                            book_title = util.splitFileNameSuffix(filename)
                        end
                    end
                    obj.ui:handleEvent(Event:new("WordLookedUp", obj.word, book_title, true)) -- is_manual: true
                    local button = obj.button_table.button_by_id["vocabulary"]
                    if button then
                        button:disable()
                        UIManager:setDirty(obj, function()
                            return "ui", button.dimen
                        end)
                    end
                end
            }})
        end
    else
        DictQuickLookUp.tweak_buttons_func = nil
    end
end

local function saveSettings()
    G_reader_settings:saveSetting("vocabulary_builder", settings)
end

--[[--
Menu dialogue widget
--]]--
local MenuDialog = FocusManager:extend{
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
        self.key_events.Close = { { Device.input.group.Back } }
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
    local width = math.floor(size.w * 0.9)

    -- Switch text translations could be long
    local temp_text_widget = TextWidget:new{
        text = _("Auto add new words"),
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
        enabled = true,
        config = self,
        readonly = self.readonly,
    }
    self.context_switch:setPosition(settings.with_context and 2 or 1)
    self:mergeLayoutInVertical(self.context_switch)

    local filter_button = {
        text = _("Filter books"),
        callback = function()
            self:onClose()
            self.show_parent:onShowFilter()
        end
    }

    local reverse_button = {
        text = settings.reverse and _("Reverse order") or _("Reverse order and show only reviewable"),
        callback = function()
            self:onClose()
            settings.reverse = not settings.reverse
            saveSettings()
            self.show_parent:reloadItems()
        end
    }

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

    local show_sync_settings = function()
        if not settings.server then
            local sync_settings = SyncService:new{}
            sync_settings.onClose = function(this)
                UIManager:close(this)
            end
            sync_settings.onConfirm = function(server)
                settings.server = server
                saveSettings()
                DB:batchUpdateItems(self.show_parent.item_table)
                SyncService.sync(server, DB.path, DB.onSync, false)
                self.show_parent:reloadItems()
            end
            UIManager:close(self.sync_dialogue)
            UIManager:close(self)
            UIManager:show(sync_settings)
            return
        end
        local server = settings.server
        local buttons = {
            {
                {
                    text = _("Delete"),
                    callback = function()
                        settings.server = nil
                        UIManager:close(self.sync_dialogue)
                    end
                },
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(self.sync_dialogue)
                        UIManager:close(self)
                        local sync_settings = SyncService:new{}
                        sync_settings.onClose = function(this)
                            UIManager:close(this)
                        end

                        sync_settings.onConfirm = function(chosen_server)
                            settings.server = chosen_server
                        end
                        UIManager:show(sync_settings)
                    end
                },
                {
                    text = _("Synchronize now"),
                    callback = function()
                        UIManager:close(self.sync_dialogue)
                        UIManager:close(self)
                        DB:batchUpdateItems(self.show_parent.item_table)
                        SyncService.sync(server, DB.path, DB.onSync, false)
                        self.show_parent:reloadItems()
                    end
                }
            }
        }
        local type = server.type == "dropbox" and " (DropBox)" or " (WebDAV)"
        self.sync_dialogue = ButtonDialogTitle:new{
            title = T(_("Cloud storage:\n%1\n\nFolder path:\n%2\n\nSet up the same cloud folder on each device to sync across your devices."),
                         server.name.." "..type, SyncService.getReadablePath(server)),
            info_face = Font:getFace("smallinfofont"),
            buttons = buttons,
        }
        UIManager:show(self.sync_dialogue)
    end
    local sync_button = {
        text = _("Cloud sync"),
        callback = function()
            show_sync_settings()
        end
    }
    local search_button = {
        text = _("Search"),
        callback = function()
            UIManager:close(self)
            self.show_parent:showSearchDialog()
        end
    }

    local buttons = ButtonTable:new{
        width = width,
        buttons = {
            {reverse_button},
            {sync_button},
            {search_button},
            {filter_button, edit_button},
            {reset_button, clean_button},
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
                            text = _("Auto add new words"),
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
    saveSettings()
end

function MenuDialog:onChangeEnableStatus(args, position)
    settings.enabled = position == 2
    saveSettings()
    resetButtonOnLookupWindow()
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
local WordInfoDialog = InputContainer:extend{
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
local book_title_triangle = BD.mirroredUILayout() and " ⯇" or " ⯈"
local word_info_dialog_width
function WordInfoDialog:init()
    if self.dismissable then
        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back } }
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

    local buttons = {{reset_button, remove_button}}
    if self.show_parent.item.last_due_time then
        table.insert(buttons, {{
            text = _("Undo study status"),
            callback = function()
                self.undo_callback()
                UIManager:close(self)
            end
        }})
    end

    local focus_button = ButtonTable:new{
        width = width,
        buttons = buttons,
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
    self.book_title_button = Button:new{
        text = self.book_title .. book_title_triangle,
        width = width,
        max_width = width,
        text_font_face = "NotoSans-Italic.ttf",
        text_font_size = 14,
        text_font_bold = false,
        align = self.title_align or "left",
        padding = Size.padding.button,
        bordersize = 0,
        callback = function()
            self.show_parent:onShowBookAssignment(function(new_book_title)
                self.book_title = new_book_title
                self.book_title_button:setText(new_book_title..book_title_triangle, width)
            end)
        end,
        show_parent = self
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
                            self.book_title_button,
                            VerticalSpan:new{width= Size.padding.default},
                            has_context and
                            TextBoxWidget:new{
                                text = "..." .. (self.prev_context or ""):gsub("\n", " ") .. "【" ..self.title.."】" .. (self.next_context or ""):gsub("\n", " ") .. "...",
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
local VocabItemWidget = InputContainer:extend{
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
    if not self.show_parent.is_edit_mode then
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

        if self.item.review_count > 6 then
            right_side_width =  Size.padding.large * 4 + 9 * (star:getSize().w)
            right_widget = HorizontalGroup:new {
                dimen = Geom:new{w=0, h = self.height}
            }
            for i=1, 6, 1 do
                table.insert(right_widget, star)
            end
            table.insert(right_widget,
                TextWidget:new {
                    text = " + ",
                    face = word_face,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY
                }
            )
            table.insert(right_widget, star)
            table.insert(right_widget,
                TextWidget:new {
                    text = "× " .. self.item.review_count-6,
                    face = word_face,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY
                }
            )
        elseif self.item.review_count > 0 then
            right_side_width =  Size.padding.large * 4 + self.item.review_count * (star:getSize().w)
            right_widget = HorizontalGroup:new {
                dimen = Geom:new{w=0, h = self.height}
            }
            for i=1, self.item.review_count, 1 do
                table.insert(right_widget, star)
            end
        else
            star:free()
            right_side_width =  Size.padding.large * 4
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
        text = self:getTimeSinceDue() .. _("From") .. " ",
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

    word_widget.label_widget.fgcolor = self.item.is_dim and dim_color or Blitbuffer.COLOR_BLACK

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

    local elapsed = os.time() - self.item.due_time
    local abs = math.abs(elapsed)
    local readable_time

    local rounding = elapsed > 0 and math.floor or math.ceil
    if abs < 60 then
        readable_time = T(C_("Time", "%1s"), abs)
    elseif abs < 3600 then
        readable_time = T(C_("Time", "%1m"), rounding(abs/60))
    elseif abs < 3600 * 24 then
        readable_time = T(C_("Time", "%1h"), rounding(abs/3600))
    elseif abs < 3600 * 24 * 30 then
        readable_time = T(C_("Time", "%1d"), rounding(abs/3600/24))
    elseif abs < 3600 * 24 * 365 then
        readable_time = T(C_("Time", "%1 mo."), rounding(abs/3600/24/3)/10)
    else
        readable_time = T(C_("Time", "%1 yr."), rounding(abs/3600/24/36.5)/10)
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
    self.item.last_due_time = nil
    self.item.is_dim = false
    self:initItemWidget()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self[1].dimen end)
end

function VocabItemWidget:undo()
    self.item.streak_count = self.item.last_streak_count or self.item.streak_count
    self.item.review_count = self.item.last_review_count or self.item.review_count
    self.item.review_time = self.item.last_review_time
    self.item.due_time = self.item.last_due_time or self.item.due_time
    self.item.last_streak_count = nil
    self.item.last_review_count = nil
    self.item.last_review_time = nil
    self.item.last_due_time = nil
    self.item.is_dim = false
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
        undo_callback = function()
            self:undo()
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
            self:showMore()
        elseif self.item.callback then
            self.item.callback(self.item)
        end
    else
        if BD.mirroredUILayout() then
            if ges.pos.x > self.more_button.dimen.x and ges.pos.x < self.more_button.dimen.x + self.more_button.dimen.w * 2 then
                if self.show_parent.is_edit_mode then
                    self:remover()
                else
                    self:showMore()
                end
            elseif self.item.callback then
                self.item.callback(self.item)
            end
        else
            if ges.pos.x > self.more_button.dimen.x - self.more_button.dimen.w and ges.pos.x < self.more_button.dimen.x + self.more_button.dimen.w then
                if self.show_parent.is_edit_mode then
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
    self:onShowBookAssignment()
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


function VocabItemWidget:onShowBookAssignment(title_changed_cb)
    local sort_items = {}
    local book_data = DB:selectBooks()
    local sort_widget
    local book = self.item.book_title
    local id
    for _, info in pairs(book_data) do
        table.insert(sort_items, {
            text = info.name or "",
            callback = function()
                id = info.id
                book = info.name
            end,
            checked_func = function()
                return info.name == book
            end,
            hold_callback = function(sort_item, onSuccess)
                local book_title = self.item.book_title
                self.show_parent:showChangeBookTitleDialog(sort_item, function()
                    onSuccess()
                    if book_title == info.name then
                        if book == book_title then
                            book = sort_item.text
                        end
                        info.name = sort_item.text
                        if title_changed_cb then title_changed_cb(sort_item.text) end
                    end
                end)
            end
        })
    end
    table.insert(sort_items, {
        text = _("Add virtual book"),
        face = Font:getFace("smallinfofontbold"),
        callback = function()
            local dialog
            dialog = InputDialog:new{
                title = _("Enter book title:"),
                input = "",
                input_type = "text",
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(dialog)
                            end,
                        },
                        {
                            text = _("Add"),
                            is_enter_default = true,
                            callback = function()
                                if dialog:getInputText() == "" then return end
                                local new_book_title = dialog:getInputText()
                                local ok, new_id = pcall(DB.insertNewBook, DB, new_book_title)
                                if ok then
                                    UIManager:close(dialog)
                                    table.insert(sort_items, #sort_items, {
                                        text = new_book_title,
                                        callback = function()
                                            id = new_id
                                            book = new_book_title
                                        end,
                                        checked_func = function()
                                            return new_book_title == book
                                        end,
                                        hold_callback = function(sort_item, onSuccess)
                                            self.show_parent:showChangeBookTitleDialog(sort_item, onSuccess)
                                        end
                                    })
                                    sort_widget:goToPage(sort_widget.show_page)
                                else
                                    UIManager:show(require("ui/widget/notification"):new{
                                        text = _("Book title already in use."),
                                        timeout = 3
                                    })
                                end
                            end,
                        },
                    }
                },
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        end
    })

    sort_widget = SortWidget:new{
        title = T(_("Move \"%1\" to book:"), self.item.word),
        item_table = sort_items,
        sort_disabled = true,
        callback = function()
            if book ~= self.item.book_title then
                self.item.book_title = book
                DB:updateBookIdOfWord(self.item.word, id)
                self:initItemWidget()
                if title_changed_cb then title_changed_cb(book) end
            end
            UIManager:setDirty(nil, "ui")
        end
    }
    UIManager:show(sort_widget)
end


--[[--
Container widget. Same as sortwidget
--]]--
local VocabularyBuilderWidget = FocusManager:extend{
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
    self.item_table = self:reload_items_callback()
    self.layout = {}

    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }
    if self.dimen.h == Screen:getHeight() then
        self.covers_footer = true
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
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
    self.page_info = HorizontalGroup:new{}
    self:refreshFooter()

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
        bottom_line_h_padding = Size.padding.large,
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

function VocabularyBuilderWidget:refreshFooter()
    local has_sync = settings.server ~= nil
    local has_search = self.search_text_sql
    if self.footer_left ~= nil then -- check whether refresh needed
        local should_refresh = has_sync and self.page_info[1] ~= self.footer_sync
                               or not has_sync and self.page_info[1] == self.footer_sync
        if not should_refresh then
            should_refresh = has_search and self.page_info[#self.page_info] ~= self.footer_search
                             or not has_search and self.page_info[#self.page_info] == self.footer_search
        end
        if not should_refresh then return end
    end

    self.page_info:clear()
    local padding = Size.padding.large
    self.width_widget = self.dimen.w - 2 * padding
    self.item_width = self.dimen.w - 2 * padding
    self.footer_center_width = math.floor(self.width_widget * (32/100))
    self.footer_button_width = math.floor(self.width_widget * (12/100))
    local left_ratio = 10
    local right_ratio = 10
    if has_sync and not has_search then
        left_ratio = 9
        right_ratio = 11
    end
    self.footer_left_corner_width = math.floor(self.width_widget * left_ratio/100)
    self.footer_right_corner_width = math.floor(self.width_widget * right_ratio/100)
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
    local footer_height = self.footer_last_down:getSize().h
    local sync_size = TextWidget:getFontSizeToFitHeight("cfont", footer_height, Size.padding.buttontable*2)
    self.footer_sync = Button:new{
        text = "⇅",
        width = self.footer_left_corner_width - Size.padding.large * 2,
        text_font_size = sync_size,
        text_font_bold = false,
        bordersize = 0,
        radius = 0,
        padding_h = Size.padding.large,
        padding_v = Size.padding.button,
        margin = 0,
        show_parent = self,
        callback = function()
            if not settings.server then
                local sync_settings = SyncService:new{}
                sync_settings.onClose = function(this)
                    UIManager:close(this)
                end
                sync_settings.onConfirm = function(server)
                    settings.server = server
                    saveSettings()
                    DB:batchUpdateItems(self.item_table)
                    SyncService.sync(server, DB.path, DB.onSync, false)
                    self:reloadItems()
                end
                UIManager:show(sync_settings)
            else
                -- manual sync
                DB:batchUpdateItems(self.item_table)
                UIManager:nextTick(function()
                    SyncService.sync(settings.server, DB.path, DB.onSync, false)
                    self:reloadItems()
                end)
            end
        end
    }
    self.footer_sync.label_widget.fgcolor = Blitbuffer.COLOR_GRAY_3

    self.footer_search = Button:new{
        icon = "appbar.search",
        width = self.footer_right_corner_width,
        icon_width = math.floor(footer_height - Size.padding.large),
        icon_height = math.floor(footer_height - Size.padding.large),
        callback = function()
            self:showSearchDialog()
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
    table.insert(self.page_info, has_sync and self.footer_sync or HorizontalSpan:new{width=self.footer_left_corner_width})
    table.insert(self.page_info, self.footer_first_up)
    table.insert(self.page_info, self.footer_left)
    table.insert(self.page_info, self.footer_page)
    table.insert(self.page_info, self.footer_right)
    table.insert(self.page_info, self.footer_last_down)
    table.insert(self.page_info, has_search and self.footer_search or HorizontalSpan:new{ width = self.footer_right_corner_width })
end

function VocabularyBuilderWidget:showSearchDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Search words"),
        input = self.search_text or "",
        input_hint = _("Search empty content to exit"),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Info"),
                    callback = function()
                        local text_info = _([[You can use two wildcards when searching: the percent sign (%) and the underscore (_).
% represents any zero or more number of characters and _ represents any single character.

If no wildcard is used, the searched text will be enclosed with two %'s by default.]])
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        self.search_text = dialog:getInputText()
                        if self.search_text == "" then
                            self.search_text_sql = nil
                        elseif self.search_text:find("%", 1, true) or self.search_text:find("_") then
                            self.search_text_sql = self.search_text:gsub("'", "''")
                        else
                            self.search_text_sql = "%" .. self.search_text:gsub("'", "''") .. "%"
                        end
                        UIManager:close(dialog)
                        self:reloadItems()
                    end,
                },
            }
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function VocabularyBuilderWidget:setupItemHeight()
    local item_height = Screen:scaleBySize(self.is_edit_mode and 54 or 72)
    self.item_height = item_height
    self.item_margin = math.floor(self.item_height / 8)
    local line_height = self.item_height + self.item_margin
    local content_height = self.dimen.h - self.title_bar:getHeight() - self.footer_height - Size.padding.large
    self.items_per_page = math.floor(content_height / line_height)
    self.item_margin = self.item_margin + math.floor((content_height - self.items_per_page * line_height ) / self.items_per_page )
    self.pages = math.ceil(#self.item_table / self.items_per_page)
    self.show_page = math.max(1, math.min(self.pages, self.show_page))
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
        self:select_items_callback(idx_offset, page_last)
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
    self:refreshFooter()
    if settings.server then
        table.insert(self.layout, #self.layout, {self.footer_sync})
    end
    if #self.main_content == 0 then
        table.insert(self.main_content, HorizontalSpan:new{width = self.item_width})
    end
    self.footer_page:setText(T(_("Page %1 of %2"), self.show_page, self.pages), self.footer_center_width)
    if self.pages > 1 then
        self.footer_page:enable()
    else
        self.footer_page:disableWithoutDimming()
    end
    if self.pages == 0 then
        local text
        if self.search_text_sql then
            text = _("Search in effect")
        else
            local has_filtered_book = DB:hasFilteredBook()
            text = has_filtered_book and _("Filter in effect") or
                self:check_reverse() and _("No reviewable items") or _("No items")
        end
        self.footer_page:setText(text, self.footer_center_width)
        self.footer_first_up:hide()
        self.footer_last_down:hide()
        self.footer_left:hide()
        self.footer_right:hide()
    elseif self.footer_left.hidden then
        self.footer_first_up:show()
        self.footer_last_down:show()
        self.footer_left:show()
        self.footer_right:show()
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
    self.reload_time = os.time()
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
        show_parent = self
    })
end

function VocabularyBuilderWidget:check_reverse()
    return settings.reverse
end


function VocabularyBuilderWidget:onShowFilter()
    local sort_items = {}
    local book_data = DB:selectBooks()
    local toggled = {}
    for _, info in pairs(book_data) do
        table.insert(sort_items, {
            text = info.name or "",
            callback = function()
                info.filter = not info.filter
                if toggled[info.id] then
                    toggled[info.id] = nil
                else
                    toggled[info.id] = true
                end
            end,
            checked_func = function()
                return info.filter
            end,
            hold_callback = function(sort_item, onSuccess)
                self:showChangeBookTitleDialog(sort_item, onSuccess)
            end,
        })
    end

    local sort_widget = SortWidget:new{
        title = _("Filter words from books"),
        item_table = sort_items,
        sort_disabled = true,
        callback = function()
            if #toggled then
                DB:toggleBookFilter(toggled)
                self:reloadItems()
            end

            UIManager:setDirty(nil, "ui")
        end
    }
    UIManager:show(sort_widget)
end

function VocabularyBuilderWidget:showChangeBookTitleDialog(sort_item, onSuccess)
    local dialog
    dialog = InputDialog:new {
        title = _("Change book title to:"),
        input = sort_item.text,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Change title"),
                    is_enter_default = true,
                    callback = function()
                        if dialog:getInputText() == "" then return end
                        local new_book_title = dialog:getInputText()
                        local ok = pcall(DB.changeBookTitle, DB, sort_item.text, new_book_title)
                        if ok then
                            for i=1, #self.item_table do
                                if self.item_table[i].book_title == sort_item.text then
                                    self.item_table[i].book_title = new_book_title
                                end
                            end
                            sort_item.text = new_book_title
                            UIManager:close(dialog)
                            if onSuccess then onSuccess() end
                            self:_populateItems()
                        else
                            UIManager:show(require("ui/widget/notification"):new {
                                text = _("Book title already in use."),
                                timeout = 3
                            })
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function VocabularyBuilderWidget:reloadItems()
    DB:batchUpdateItems(self.item_table)
    self.item_table = self:reload_items_callback()
    self.pages = math.ceil(#self.item_table / self.items_per_page)
    self:goToPage(1)
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
        -- open filter
        self:onShowFilter()
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function VocabularyBuilderWidget:onMultiSwipe(arg, ges_ev)
    -- if user is drawing a circle or half circle (full circle not always easy), reload
    local space_count = 0
    for space in ges_ev.multiswipe_directions:gmatch(" ") do
        space_count = space_count + 1
        if space_count == 2 then break end
    end
    if space_count == 2 and (
        string.find("east south west north east south west", ges_ev.multiswipe_directions)
        or string.find("east north west south east north west", ges_ev.multiswipe_directions)
    ) then
        self:reloadItems()
        UIManager:show(Notification:new{ text = _("Words reloaded") })
    else
        -- For consistency with other fullscreen widgets where swipe south can't be
        -- used to close and where we then allow any multiswipe to close, allow any
        -- multiswipe to close this widget too.
        self:onClose()
    end
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
local VocabBuilder = WidgetContainer:extend{
    name = "vocabulary_builder",
    is_doc_only = false
}

function VocabBuilder:init()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function VocabBuilder:addToMainMenu(menu_items)
    menu_items.vocabbuilder = {
        text = _("Vocabulary builder"),
        callback = function()
            self:onShowVocabBuilder()
        end
    }
end

function VocabBuilder:setupWidget()
    if self.widget then
        self.widget:reloadItems()
    else
        -- We initiate the widget with proper
        -- callback definition for reload_items
        local reload_items = function(widget)
                widget.reload_time = os.time()
                local vocab_items = {}
                for i = 1, DB:selectCount(widget) do
                    table.insert(vocab_items, {
                        callback = function(item)
                            -- custom button table
                            local tweak_buttons_func = function() end
                            if item.due_time <= os.time() then
                                tweak_buttons_func = function(obj, buttons)
                                    local tweaked_button_count = 0
                                    local early_break
                                    for j = 1, #buttons do
                                        for k = 1, #buttons[j] do
                                            if buttons[j][k].id == "highlight" and not buttons[j][k].enabled then
                                                buttons[j][k] = {
                                                    id = "got_it",
                                                    text = _("Got it"),
                                                    callback = function()
                                                        self.widget:gotItFromDict(item.word)
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
                                                        self.widget:forgotFromDict(item.word)
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

                            widget.current_lookup_word = item.word
                            self.ui:handleEvent(Event:new("LookupWord", item.word, true, nil, nil, nil, tweak_buttons_func))
                        end
                    })
                end
            return vocab_items
        end

        self.widget = VocabularyBuilderWidget:new{
            title = _("Vocabulary builder"),
            select_items_callback = function(obj, start_idx, end_idx)
                DB:select_items(obj, start_idx, end_idx)
            end,
            reload_items_callback = reload_items
        }
    end
end

function VocabBuilder:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_vocab_builder",
        {category="none", event="ShowVocabBuilder", title=_("Open vocabulary builder"), general=true, separator=true})
end

function VocabBuilder:onShowVocabBuilder()
    self:setupWidget()
    UIManager:show(self.widget)
end

-- Event sent by readerdictionary "WordLookedUp"
function VocabBuilder:onWordLookedUp(word, title, is_manual)
    if not settings.enabled and not is_manual then return end
    if self.widget and self.widget.current_lookup_word == word then return true end
    local prev_context
    local next_context
    if settings.with_context and self.ui.highlight then
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

-- register button in readerdictionary
resetButtonOnLookupWindow()

return VocabBuilder
