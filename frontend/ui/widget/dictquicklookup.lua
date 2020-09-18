local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CloseButton = require("ui/widget/closebutton")
local Device = require("device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local T = require("ffi/util").template

--[[
Display quick lookup word definition
]]
local DictQuickLookup = InputContainer:new{
    results = nil,
    lookupword = nil,
    dictionary = nil,
    definition = nil,
    displayword = nil,
    images = nil,
    is_wiki = false,
    is_fullpage = false,
    is_html = false,
    dict_index = 1,
    title_face = Font:getFace("x_smalltfont"),
    content_face = Font:getFace("cfont", 20),
    image_alt_face = Font:getFace("cfont", 16),
    width = nil,
    height = nil,
    -- box of highlighted word, quick lookup window tries to not hide the word
    word_box = nil,

    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    word_padding = Size.padding.default,
    word_margin = Size.margin.default,
    -- alt padding/margin for wiki to compensate for reduced font size
    wiki_word_padding = Screen:scaleBySize(7),
    wiki_word_margin = Screen:scaleBySize(3),
    definition_padding = Screen:scaleBySize(2),
    definition_margin = Screen:scaleBySize(2),
    button_padding = Screen:scaleBySize(14),
    -- refresh_callback will be called before we trigger full refresh in onSwipe
    refresh_callback = nil,
    html_dictionary_link_tapped_callback = nil,
}

local highlight_strings = {
    highlight =_("Highlight"),
    unhighlight = _("Unhighlight"),
}

function DictQuickLookup:init()
    local font_size = G_reader_settings:readSetting("dict_font_size") or 20
    self.content_face = Font:getFace("cfont", font_size)
    local font_size_alt = font_size - 4
    if font_size_alt < 8 then
        font_size_alt = 8
    end
    self.image_alt_face = Font:getFace("cfont", font_size_alt)
    self:changeToDefaultDict()
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "close quick lookup" }
        }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            TapCloseDict = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = range,
                },
            },
            -- This was for selection of a single word with simple hold
            -- HoldWord = {
            --     GestureRange:new{
            --         ges = "hold",
            --         range = function()
            --             return self.region
            --         end,
            --     },
            --     -- callback function when HoldWord is handled as args
            --     args = function(word)
            --         self.ui:handleEvent(
            --             -- don't pass self.highlight to subsequent lookup, we want
            --             -- the first to be the only one to unhighlight selection
            --             -- when closed
            --             Event:new("LookupWord", word, self.word_box))
            --     end
            -- },
            -- Allow selection of one or more words (see textboxwidget.lua) :
            HoldStartText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new{
                    ges = "hold",
                    range = range,
                },
            },
            HoldReleaseText = {
                GestureRange:new{
                    ges = "hold_release",
                    range = range,
                },
                -- callback function when HoldReleaseText is handled as args
                args = function(text, hold_duration)
                    local lookup_target
                    if hold_duration < 3.0 then
                        -- do this lookup in the same domain (dict/wikipedia)
                        lookup_target = self.is_wiki and "LookupWikipedia" or "LookupWord"
                    else
                        -- but allow switching domain with a long hold
                        lookup_target = self.is_wiki and "LookupWord" or "LookupWikipedia"
                    end
                    if lookup_target == "LookupWikipedia" then
                        self:resyncWikiLanguages()
                    end
                    self.ui:handleEvent(
                        -- don't pass self.highlight to subsequent lookup, we want
                        -- the first to be the only one to unhighlight selection
                        -- when closed
                        Event:new(lookup_target, text)
                    )
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end
end

-- Whether currently DictQuickLookup is working without a document.
function DictQuickLookup:isDocless()
    return self.ui == nil or self.ui.highlight == nil
end

function DictQuickLookup:getHtmlDictionaryCss()
    -- Using Noto Sans because Nimbus doesn't contain the IPA symbols.
    -- 'line-height: 1.3' to have it similar to textboxwidget,
    -- and follow user's choice on justification
    local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
    local css = [[
        @page {
            margin: 0;
            font-family: 'Noto Sans';
        }

        body {
            margin: 0;
            line-height: 1.3;
            ]]..css_justify..[[
        }

        blockquote, dd {
            margin: 0 1em;
        }
    ]]
    -- MuPDF doesn't currently scale CSS pixels, so we have to use a font-size based measurement.
    -- Unfortunately MuPDF doesn't properly support `rem` either, which it bases on a hard-coded
    -- value of `16px`, so we have to go with `em` (or `%`).
    --
    -- These `em`-based margins can vary slightly, but it's the best available compromise.
    --
    -- We also keep left and right margin the same so it'll display as expected in RTL.
    -- Because MuPDF doesn't currently support `margin-start`, this results in a slightly
    -- unconventional but hopefully barely noticeable right margin for <dd>.

    if self.css then
        return css .. self.css
    end
    return css
end

function DictQuickLookup:update()
    local orig_dimen = self.dict_frame and self.dict_frame.dimen or Geom:new{}
    local orig_moved_offset = self.movable and self.movable:getMovedOffset()
    -- Free our previous widget and subwidgets' resources (especially
    -- definitions' TextBoxWidget bb, HtmlBoxWidget bb and MuPDF instance,
    -- and scheduled image_update_action)
    if self[1] then
        self[1]:free()
    end
    -- calculate window dimension
    self.align = "center"
    self.region = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if self.is_fullpage or G_reader_settings:isTrue("dict_largewindow") then
        -- bigger window if fullpage being shown - this will let
        -- some room anyway for footer display (time, battery...)
        self.height = Screen:getHeight()
        self.width = Screen:getWidth() - Screen:scaleBySize(40)
    else
        -- smaller window otherwise
        -- try to not hide highlighted word
        if self.word_box then
            local box = self.word_box
            if box.y + box.h/2 < Screen:getHeight()*0.3 then
                self.region.y = box.y + box.h
                self.region.h = Screen:getHeight() - box.y - box.h
                self.align = "top"
            elseif box.y + box.h/2 > Screen:getHeight()*0.7 then
                self.region.y = 0
                self.region.h = box.y
                self.align = "bottom"
            end
        end
        self.height = math.floor(math.min(self.region.h*0.7, Screen:getHeight()*0.5))
    end
    -- dictionary title
    local close_button = CloseButton:new{ window = self, padding_top = self.title_margin, }
    local btn_width = close_button:getSize().w + Size.padding.default * 2
    local dict_title_text = TextWidget:new{
        text = self.dictionary,
        face = self.title_face,
        bold = true,
        max_width = self.width - btn_width,
    }
    -- Some different UI tweaks for dict or wiki
    local lookup_word_font_size, lookup_word_padding, lookup_word_margin
    local dict_title_widget
    if self.is_wiki then
        -- visual hint : dictionary title left adjusted, Wikipedia title centered
        dict_title_widget = CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = dict_title_text:getSize().h,
                },
                dict_title_text,
        }
        -- Wikipedia has longer titles, so use a smaller font
        lookup_word_font_size = 18
        lookup_word_padding = self.wiki_word_padding
        lookup_word_margin = self.wiki_word_margin
        -- Keep a copy of self.wiki_languages for use
        -- by DictQuickLookup:resyncWikiLanguages()
        self.wiki_languages_copy = self.wiki_languages and {unpack(self.wiki_languages)} or nil
    else
        dict_title_widget = dict_title_text
        -- Usual font size for dictionary
        lookup_word_font_size = 22
        lookup_word_padding = self.word_padding
        lookup_word_margin = self.word_margin
    end
    self.dict_title = FrameContainer:new{
        padding = self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        dict_title_widget,
    }
    -- lookup word
    local lookup_word = Button:new{
        padding = lookup_word_padding,
        margin = lookup_word_margin,
        bordersize = 0,
        max_width = self.width,
        text = self.displayword,
        text_font_face = "tfont",
        text_font_size = lookup_word_font_size,
        hold_callback = function() self:lookupInputWord(self.lookupword) end,
    }

    local text_widget

    if self.is_html then
        text_widget = ScrollHtmlWidget:new{
            html_body = self.definition,
            css = self:getHtmlDictionaryCss(),
            default_font_size = Screen:scaleBySize(G_reader_settings:readSetting("dict_font_size") or 20),
            width = self.width,
            height = self.is_fullpage and math.floor(self.height*0.75) or math.floor(self.height*0.7),
            dialog = self,
            html_link_tapped_callback = function(link)
                self.html_dictionary_link_tapped_callback(self.dictionary, link)
            end,
         }
    else
        text_widget = ScrollTextWidget:new{
            text = self.definition,
            face = self.content_face,
            width = self.width,
            -- get a bit more height for definition as wiki has one less button raw
            height = self.is_fullpage and math.floor(self.height*0.75) or math.floor(self.height*0.7),
            dialog = self,
            -- allow for disabling justification
            justified = G_reader_settings:nilOrTrue("dict_justify"),
            lang = self.lang and self.lang:lower(), -- only available on wikipedia results
            para_direction_rtl = self.rtl_lang,     -- only available on wikipedia results
            auto_para_direction = not self.is_wiki, -- only for dict results (we don't know their lang)
            image_alt_face = self.image_alt_face,
            images = self.images,
        }
    end

    -- word definition
    self.definition_widget = FrameContainer:new{
        padding = self.definition_padding,
        margin = self.definition_margin,
        bordersize = 0,
        text_widget,
    }
    -- Different sets of buttons if fullpage or not
    local buttons
    if self.is_fullpage then
        -- A save and a close button
        buttons = {
            {
                {
                    text = _("Save as EPUB"),
                    callback = function()
                        local InfoMessage = require("ui/widget/infomessage")
                        local ConfirmBox = require("ui/widget/confirmbox")
                        -- if forced_lang was specified, it may not be in our wiki_languages,
                        -- but ReaderWikipedia will have put it in result.lang
                        local lang = self.lang or self.wiki_languages_copy[1]
                        -- Find a directory to save file into
                        local dir
                        if G_reader_settings:isTrue("wikipedia_save_in_book_dir") and not self:isDocless() then
                            local last_file = G_reader_settings:readSetting("lastfile")
                            if last_file then
                                dir = last_file:match("(.*)/")
                            end
                        end
                        if not dir then dir = G_reader_settings:readSetting("wikipedia_save_dir") end
                        if not dir then dir = G_reader_settings:readSetting("home_dir") end
                        if not dir then dir = require("apps/filemanager/filemanagerutil").getDefaultDir() end
                        if not dir or not util.pathExists(dir) then
                            UIManager:show(InfoMessage:new{
                                text = _("No directory to save article to could be found."),
                            })
                            return
                        end
                        -- Just to be safe (none of the invalid chars, except ':' for uninteresting
                        -- Portal: or File: wikipedia pages, should be in lookupword)
                        local filename = self.lookupword .. "."..string.upper(lang)..".epub"
                        filename = util.getSafeFilename(filename, dir):gsub("_", " ")
                        local epub_path = dir .. "/" .. filename
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Save as %1?"), BD.filename(filename)),
                            ok_callback = function()
                                UIManager:scheduleIn(0.1, function()
                                    local Wikipedia = require("ui/wikipedia")
                                    Wikipedia:createEpubWithUI(epub_path, self.lookupword, lang, function(success)
                                        if success then
                                            UIManager:show(ConfirmBox:new{
                                                text = T(_("Article saved to:\n%1\n\nWould you like to read the downloaded article now?"), BD.filepath(epub_path)),
                                                ok_callback = function()
                                                    -- close all dict/wiki windows, without scheduleIn(highlight.clear())
                                                    self:onHoldClose(true)
                                                    -- close current ReaderUI in 1 sec, and create a new one
                                                    UIManager:scheduleIn(1.0, function()
                                                        local ReaderUI = require("apps/reader/readerui")
                                                        local reader = ReaderUI:_getRunningInstance()
                                                        if reader then
                                                            -- close Highlight menu if any still shown
                                                            if reader.highlight then
                                                                reader.highlight:onClose()
                                                            end
                                                            reader:onClose()
                                                        end
                                                        ReaderUI:showReader(epub_path)
                                                    end)
                                                end,
                                            })
                                        else
                                            UIManager:show(InfoMessage:new{
                                                text = _("Saving Wikipedia article failed or canceled."),
                                            })
                                        end
                                    end)
                                end)
                            end
                        })
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(self)
                    end,
                },
            },
        }
    else
        local prev_dict_text = "◁◁"
        local next_dict_text = "▷▷"
        if BD.mirroredUILayout() then
            prev_dict_text, next_dict_text = next_dict_text, prev_dict_text
        end
        buttons = {
            {
                {
                    text = prev_dict_text,
                    enabled = self:isPrevDictAvaiable(),
                    callback = function()
                        self:changeToPrevDict()
                    end,
                },
                {
                    text = self:getHighlightText(),
                    enabled = self.highlight ~= nil,
                    callback = function()
                        if self:getHighlightText() == highlight_strings.highlight then
                            self.ui:handleEvent(Event:new("Highlight"))
                        else
                            self.ui:handleEvent(Event:new("Unhighlight"))
                        end
                        self:update()
                    end,
                },
                {
                    text = next_dict_text,
                    enabled = self:isNextDictAvaiable(),
                    callback = function()
                        self:changeToNextDict()
                    end,
                },
            },
            {
                {
                    -- if dictionary result, do the same search on wikipedia
                    -- if already wiki, get the full page for the current result
                    text_func = function()
                        if self.is_wiki then
                            -- @translators Full Wikipedia article.
                            return C_("Button", "Wikipedia full")
                        else
                            return _("Wikipedia")
                        end
                    end,
                    callback = function()
                        UIManager:scheduleIn(0.1, function()
                            self:lookupWikipedia(self.is_wiki) -- will get_fullpage if is_wiki
                        end)
                    end,
                },
                -- Rotate thru available wikipedia languages (disabled if dictionary window)
                -- (replace previous unimplemented "Add Note")
                {
                    -- if more than one language, enable it and display "current lang > next lang"
                    -- otherwise, just display current lang
                    text = self.is_wiki
                        and ( #self.wiki_languages > 1 and BD.wrap(self.wiki_languages[1]).." > "..BD.wrap(self.wiki_languages[2])
                                                        or self.wiki_languages[1] ) -- (this " > " will be auro-mirrored by bidi)
                        or _("Follow Link"),
                    enabled = (self.is_wiki and #self.wiki_languages > 1) or self.selected_link ~= nil,
                    callback = function()
                        if self.is_wiki then
                            self:resyncWikiLanguages(true) -- rotate & resync them
                            UIManager:close(self)
                            self:lookupWikipedia()
                        else
                            local link = self.selected_link.link or self.selected_link
                            self.ui.link:onGotoLink(link)
                            self:onClose()
                        end
                    end,
                },
                {
                    text = (self.is_wiki or self:isDocless()) and _("Close") or _("Search"),
                    callback = function()
                        if not self.is_wiki then
                            self.ui:handleEvent(Event:new("HighlightSearch"))
                        end
                        UIManager:close(self)
                    end,
                },
            },
        }
    end

    local button_table = ButtonTable:new{
        width = math.max(self.width, self.definition_widget:getSize().w),
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    local title_bar = LineWidget:new{
        dimen = Geom:new{
            w = button_table:getSize().w + self.button_padding,
            h = Size.line.thick,
        }
    }

    self.dict_bar = OverlapGroup:new{
        dimen = {
            w = button_table:getSize().w + self.button_padding,
            h = self.dict_title:getSize().h
        },
        self.dict_title,
        close_button,
    }
    -- Fix dict title max width now that we know the final width
    dict_title_text:setMaxWidth(self.dict_bar.dimen.w - close_button:getSize().w)

    self.dict_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.dict_bar,
            title_bar,
            -- word
            LeftContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = lookup_word:getSize().h,
                },
                lookup_word,
            },
            -- definition
            CenterContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = self.definition_widget:getSize().h,
                },
                self.definition_widget,
            },
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = title_bar:getSize().w,
                    h = button_table:getSize().h,
                },
                button_table,
            }
        }
    }

    self.movable = MovableContainer:new{
        -- We'll handle these events ourselves, and call appropriate
        -- MovableContainer's methods when we didn't process the event
        ignore_events = {
            -- These have effects over the definition widget, and may
            -- or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            -- These do not have direct effect over the definition widget,
            -- but may happen while selecting text: we need to check
            -- a few things before forwarding them
            "touch", "pan", "pan_release",
        },
        self.dict_frame,
    }
    self.movable:setMovedOffset(orig_moved_offset)

    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }
    UIManager:setDirty(self, function()
        local update_region = self.dict_frame and self.dict_frame.dimen and self.dict_frame.dimen:combine(orig_dimen) or orig_dimen
        logger.dbg("update dict region", update_region)
        return "partial", update_region
    end)
end

function DictQuickLookup:onCloseWidget()
    -- Free our widget and subwidgets' resources (especially
    -- definitions' TextBoxWidget bb, HtmlBoxWidget bb and MuPDF instance,
    -- and scheduled image_update_action)
    if self[1] then
        self[1]:free()
    end
    if self.images_cleanup_needed then
        logger.dbg("freeing lookup results images blitbuffers")
        for _, r in ipairs(self.results) do
            if r.images and #r.images > 0 then
                for _, im in ipairs(r.images) do
                    if im.bb then im.bb:free() end
                    if im.hi_bb then im.hi_bb:free() end
                end
            end
        end
    end
    -- NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
    return true
end

function DictQuickLookup:onShow()
    UIManager:setDirty(self, function()
        return "flashui", self.dict_frame.dimen
    end)
    return true
end

function DictQuickLookup:getHighlightedItem()
    if self:isDocless() then return end
    return self.ui.highlight:getHighlightBookmarkItem()
end

function DictQuickLookup:getHighlightText()
    local item = self:getHighlightedItem()
    if not item then
        return highlight_strings.highlight, false
    elseif self.ui.bookmark:isBookmarkAdded(item) then
        return highlight_strings.unhighlight, false
    else
        return highlight_strings.highlight, true
    end
end

function DictQuickLookup:isPrevDictAvaiable()
    return self.dict_index > 1
end

function DictQuickLookup:isNextDictAvaiable()
    return self.dict_index < #self.results
end

function DictQuickLookup:changeToPrevDict()
    if self:isPrevDictAvaiable() then
        self:changeDictionary(self.dict_index - 1)
    elseif #self.results > 1 then -- restart at end if first reached
        self:changeDictionary(#self.results)
    end
end

function DictQuickLookup:changeToNextDict()
    if self:isNextDictAvaiable() then
        self:changeDictionary(self.dict_index + 1)
    elseif #self.results > 1 then -- restart at first if end reached
        self:changeDictionary(1)
    end
end

function DictQuickLookup:changeDictionary(index)
    if not self.results[index] then return end
    self.dict_index = index
    self.dictionary = self.results[index].dict
    self.lookupword = self.results[index].word
    self.definition = self.results[index].definition
    self.is_fullpage = self.results[index].is_fullpage
    self.is_html = self.results[index].is_html
    self.css = self.results[index].css
    self.lang = self.results[index].lang
    self.rtl_lang = self.results[index].rtl_lang
    self.images = self.results[index].images
    if self.images and #self.images > 0 then
        -- We'll be giving some images to textboxwidget that will
        -- load and display them. We'll need to free these blitbuffers
        -- when we're done.
        self.images_cleanup_needed = true
    end
    if self.is_fullpage then
        self.displayword = self.lookupword
    else
        -- add "dict_index / nbresults" to displayword, so we know where
        -- we're at and what's yet to see
        self.displayword = self.lookupword.."   "..index.." / "..#self.results
        -- add queried word to 1st result's definition, so we can see
        -- what was the selected text and if we selected wrong
        if index == 1 then
            if self.is_html then
                self.definition = self.definition.."<br/>_______<br/>"
            else
                self.definition = self.definition.."\n_______\n"
            end
            self.definition = self.definition..T(_("(query : %1)"), self.word)
        end
    end

    self:update()
end

function DictQuickLookup:changeToDefaultDict()
    if self.dictionary then
        -- dictionaries that have definition of the first word(accurate word)
        -- excluding Fuzzy queries.
        local n_accurate_dicts = nil
        local default_word = self.results[1].word
        for i=1, #self.results do
            if self.results[i].word == default_word then
                n_accurate_dicts = i
            else
                break
            end
        end
        -- change to dictionary specified by self.dictionary
        for i=1, n_accurate_dicts do
            if self.results[i].dict == self.dictionary then
                self:changeDictionary(i)
                break
            end
            -- cannot find definition in default dictionary
            if i == n_accurate_dicts then
                self:changeDictionary(1)
            end
        end
    else
        self:changeDictionary(1)
    end
end

function DictQuickLookup:onAnyKeyPressed()
    -- triggered by our defined key events
    UIManager:close(self)
    return true
end

function DictQuickLookup:onTapCloseDict(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dict_frame.dimen) then
        self:onClose()
        return true
    elseif not ges_ev.pos:notIntersectWith(self.dict_title.dimen) and not self.is_wiki then
        self.ui:handleEvent(Event:new("UpdateDefaultDict", self.dictionary))
        return true
    end
    -- Allow for changing dict with tap (tap event will be first
    -- processed for scrolling definition by ScrollTextWidget, which
    -- will pop it up for us here when it can't scroll anymore).
    -- This allow for continuous reading of results' definitions with tap.
    if BD.flipIfMirroredUILayout(ges_ev.pos.x < Screen:getWidth()/2) then
        local prev_index = self.dict_index
        self:changeToPrevDict()
        if self.dict_index ~= prev_index then
            -- Jump directly to bottom of previous dict definition
            -- to keep "continuous reading with tap" consistent
            self.definition_widget[1]:scrollToRatio(1) -- 1 = 100% = bottom
        end
    else
        self:changeToNextDict()
    end
    return true
end

function DictQuickLookup:onClose()
    UIManager:close(self)
    for i = #self.window_list, 1, -1 do
        local window = self.window_list[i]
        if window == self then
            table.remove(self.window_list, i)
        end
    end
    if self.highlight then
        -- delay unhighlight of selection, so we can see where we stopped when
        -- back from our journey into dictionary or wikipedia
        local clear_id = self.highlight:getClearId()
        UIManager:scheduleIn(0.5, function()
            self.highlight:clear(clear_id)
        end)
    end
    return true
end

function DictQuickLookup:onHoldClose(no_clear)
    self:onClose()
    for i = #self.window_list, 1, -1 do
        local window = self.window_list[i]
        -- if one holds a highlight, let's clear it like in onClose()
        if window.highlight and not no_clear then
            local clear_id = window.highlight:getClearId()
            UIManager:scheduleIn(0.5, function()
                window.highlight:clear(clear_id)
            end)
        end
        UIManager:close(window)
        table.remove(self.window_list, i)
    end
    return true
end

function DictQuickLookup:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.definition_widget.dimen) then
    -- if we want changeDict to still work with swipe outside window :
    -- or not ges.pos:intersectWith(self.dict_frame.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self:changeToNextDict()
        elseif direction == "east" then
            self:changeToPrevDict()
        else
            if self.refresh_callback then self.refresh_callback() end
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
        return true
    end
    -- Let our MovableContainer handle swipe outside of definition
    return self.movable:onMovableSwipe(arg, ges)
end

function DictQuickLookup:onHoldStartText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function DictQuickLookup:onHoldPanText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    -- We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function DictQuickLookup:onHoldReleaseText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

-- These 3 event processors are just used to forward these events
-- to our MovableContainer, under certain conditions, to avoid
-- unwanted moves of the window while we are selecting text in
-- the definition widget.
function DictQuickLookup:onForwardingTouch(arg, ges)
    -- This Touch may be used as the Hold we don't get (for example,
    -- when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.definition_widget.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        -- Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function DictQuickLookup:onForwardingPan(arg, ges)
    -- We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function DictQuickLookup:onForwardingPanRelease(arg, ges)
    -- We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end

function DictQuickLookup:lookupInputWord(hint)
    self:onClose()
    self.input_dialog = InputDialog:new{
        title = _("Input lookup word"),
        input = hint,
        input_hint = hint or "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:closeInputDialog()
                    end,
                },
                {
                    text = _("Lookup"),
                    is_enter_default = true,
                    callback = function()
                        self:closeInputDialog()
                        self:inputLookup()
                    end,
                },
            }
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function DictQuickLookup:inputLookup()
    local word = self.input_dialog:getInputText()
    if word and word ~= "" then
        local event
        if self.is_wiki then
            event = "LookupWikipedia"
            self:resyncWikiLanguages()
        else
            event = "LookupWord"
        end
        self.ui:handleEvent(Event:new(event, word))
    end
end

function DictQuickLookup:closeInputDialog()
    UIManager:close(self.input_dialog)
end

function DictQuickLookup:resyncWikiLanguages(rotate)
    -- Resync the current language or rotate it from its state when
    -- this window was created (we may have rotated it later in other
    -- wikipedia windows that we closed and went back here, and its
    -- state would not be what the wikipedia language button is showing.
    if not self.wiki_languages_copy then
        return
    end
    if rotate then
        -- rotate our saved wiki_languages copy
        local current_lang = table.remove(self.wiki_languages_copy, 1)
        table.insert(self.wiki_languages_copy, current_lang)
    end
    -- re-set self.wiki_languages with original (possibly rotated) items
    for i, lang in ipairs(self.wiki_languages_copy) do
        self.wiki_languages[i] = lang
    end
end

function DictQuickLookup:lookupWikipedia(get_fullpage)
    local word
    if get_fullpage then
        -- we use the word of the displayed result's definition, which
        -- is the exact title of the full wikipedia page
        word = self.lookupword
    else
        -- we use the original word that was querried
        word = self.word
    end
    self:resyncWikiLanguages()
    -- strange : we need to pass false instead of nil if word_box is nil,
    -- otherwise get_fullpage is not passed
    self.ui:handleEvent(Event:new("LookupWikipedia", word, self.word_box and self.word_box or false, get_fullpage))
end

return DictQuickLookup
