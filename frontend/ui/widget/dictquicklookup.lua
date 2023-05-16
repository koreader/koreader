local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local IconButton = require("ui/widget/iconbutton")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local time = require("ui/time")

--[[
Display quick lookup word definition
]]
local DictQuickLookup = InputContainer:extend{
    results = nil,
    lookupword = nil,
    dictionary = nil,
    definition = nil,
    displayword = nil,
    images = nil,
    is_wiki = false,
    is_wiki_fullpage = false,
    is_html = false,
    dict_index = 1,
    width = nil,
    height = nil,
    -- sboxes containing highlighted text, quick lookup window tries to not hide the word
    word_boxes = nil,

    -- refresh_callback will be called before we trigger full refresh in onSwipe
    refresh_callback = nil,
    html_dictionary_link_tapped_callback = nil,

    -- Static class member, holds a ref to the currently opened widgets (in instantiation order).
    window_list = {},
    -- Static class member, used by ReaderWiktionary to communicate state from a closed widget to the next opened one.
    rotated_update_wiki_languages_on_close = nil,
}

local highlight_strings = {
    highlight =_("Highlight"),
    unhighlight = _("Unhighlight"),
}

function DictQuickLookup:canSearch()
    if self.is_wiki then
        -- In the Wiki variant of this widget, the Search button is coopted to cycle between enabled languages.
        if #self.wiki_languages > 1 then
            return true
        end
    else
        if self:isDocless() then
            return false
        end
        -- This is to prevent an ineffective button when we're launched from the Reader's menu.
        if self.highlight then
            return true
        end
    end

    return false
end

function DictQuickLookup:init()
    self.dict_font_size = G_reader_settings:readSetting("dict_font_size") or 20
    self.content_face = Font:getFace("cfont", self.dict_font_size)
    local font_size_alt = self.dict_font_size - 4
    if font_size_alt < 8 then
        font_size_alt = 8
    end
    self.image_alt_face = Font:getFace("cfont", font_size_alt)
    if Device:hasKeys() then
        self.key_events = {
            ReadPrevResult = { { Input.group.PgBack } },
            ReadNextResult = { { Input.group.PgFwd } },
            Close = { { Input.group.Back } },
        }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            Tap = {
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
            --             Event:new("LookupWord", word, true, {self.word_box}))
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
                    -- do this lookup in the same domain (dict/wikipedia)
                    local lookup_wikipedia = self.is_wiki
                    if hold_duration >= time.s(3) then
                        -- but allow switching domain with a long hold
                        lookup_wikipedia = not lookup_wikipedia
                    end
                    -- We don't pass self.highlight to subsequent lookup, we want the
                    -- first to be the only one to unhighlight selection when closed
                    if lookup_wikipedia then
                        self:lookupWikipedia(false, text)
                    else
                        self.ui:handleEvent(Event:new("LookupWord", text))
                    end
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new{ ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new{ ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new{ ges = "pan_release", range = range, }, },
        }
    end

    -- We no longer support setting a default dict with Tap on title.
    -- self:changeToDefaultDict()
    -- Now, dictionaries can be ordered (although not yet per-book), so trust the order set
    self:changeDictionary(1, true) -- don't call update

    -- And here comes the initial widget layout...
    if self.is_wiki then
        -- Get a copy of ReaderWikipedia.wiki_languages, with the current result
        -- lang first (rotated, or added)
        self.wiki_languages, self.update_wiki_languages_on_close = self.ui.wikipedia:getWikiLanguages(self.lang)
    end

    -- Bigger window if fullpage Wikipedia article being shown,
    -- or when large windows for dict requested
    local is_large_window = self.is_wiki_fullpage or G_reader_settings:isTrue("dict_largewindow")
    if is_large_window then
        self.width = Screen:getWidth() - 2*Size.margin.default
    else
        self.width = Screen:getWidth() - Screen:scaleBySize(80)
    end
    local frame_bordersize = Size.border.window
    local inner_width = self.width - 2*frame_bordersize
    -- Height will be computed below, after we build top an bottom
    -- components, when we know how much height they are taking.

    -- Dictionary title
    self.dict_title = TitleBar:new{
        width = inner_width,
        title = self.displaydictname,
        with_bottom_line = true,
        bottom_v_padding = 0, -- padding handled below
        close_callback = function() self:onClose() end,
        close_hold_callback = function() self:onHoldClose() end,
        -- visual hint: title left aligned for dict, centered for Wikipedia
        align = self.is_wiki and "center" or "left",
        show_parent = self,
        lang = self.lang_out,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function()
            if self.is_wiki then
                self:showWikiResultsMenu()
            else
                self:showResultsMenu()
            end
        end,
        left_icon_hold_callback = not self.is_wiki and function() self:showResultsAltMenu() end or nil,
    }
    -- Scrollable offsets of the various showResults* menus and submenus,
    -- so we can reopen them in the same state they were when closed.
    self.menu_scrolled_offsets = {}
    -- We'll also need to close any opened such menu when closing this DictQuickLookup
    -- (needed if closing all DictQuickLookups via long-press on Close on the top one)
    self.menu_opened = {}

    -- This padding and the resulting width apply to the content
    -- below the title:  lookup word and definition
    local content_padding_h = Size.padding.large
    local content_padding_v = Size.padding.large -- added via VerticalSpan
    self.content_width = inner_width - 2*content_padding_h

    -- Spans between components
    local top_to_word_span = VerticalSpan:new{ width = content_padding_v }
    local word_to_definition_span = VerticalSpan:new{ width = content_padding_v }
    local definition_to_bottom_span = VerticalSpan:new{ width = content_padding_v }

    -- Lookup word
    local word_font_face = "tfont"
    -- Ensure this word doesn't get smaller than its definition
    local word_font_size = math.max(22, self.dict_font_size)
    -- Get the line height of the normal font size, as a base for sizing this component
    if not self.word_line_height then
        local test_widget = TextWidget:new{
            text = "z",
            face = Font:getFace(word_font_face, word_font_size),
        }
        self.word_line_height = test_widget:getSize().h
        test_widget:free()
    end
    if self.is_wiki then
        -- Wikipedia has longer titles, so use a smaller font,
        word_font_size = math.max(18, self.dict_font_size)
    end
    local icon_size = Screen:scaleBySize(32)
    local lookup_height = math.max(self.word_line_height, icon_size)
    -- Edit button
    local lookup_edit_button = IconButton:new{
        icon = "edit",
        width = icon_size,
        height = icon_size,
        padding = 0,
        padding_left = Size.padding.small,
        callback = function()
            -- allow adjusting the queried word
            self:lookupInputWord(self.word)
        end,
        hold_callback = function()
            -- allow adjusting the current result word
            self:lookupInputWord(self.lookupword)
        end,
        overlap_align = "right",
        show_parent = self,
    }
    local lookup_edit_button_w = lookup_edit_button:getSize().w
    -- Nb of results (if set)
    local lookup_word_nb
    local lookup_word_nb_w = 0
    if self.displaynb then
        self.displaynb_text = TextWidget:new{
            text = self.displaynb,
            face = Font:getFace("cfont", word_font_size),
            padding = 0, -- smaller height for better aligmnent with icon
        }

        lookup_word_nb = FrameContainer:new{
            margin = 0,
            bordersize = 0,
            padding = 0,
            padding_left = Size.padding.small,
            padding_right = lookup_edit_button_w + Size.padding.default,
            overlap_align = "right",
            self.displaynb_text,
        }
        lookup_word_nb_w = lookup_word_nb:getSize().w
    end
    -- Lookup word
    self.lookup_word_text = TextWidget:new{
        text = self.displayword,
        face = Font:getFace(word_font_face, word_font_size),
        bold = true,
        max_width = self.content_width - math.max(lookup_edit_button_w, lookup_word_nb_w),
        padding = 0, -- to be aligned with lookup_word_nb
        lang = self.lang_in
    }
    -- Group these 3 widgets
    local lookup_word = OverlapGroup:new{
        dimen = {
            w = self.content_width,
            h = lookup_height,
        },
        self.lookup_word_text,
        lookup_edit_button,
        lookup_word_nb, -- last, as this might be nil
    }

    -- Different sets of buttons whether fullpage or not
    local buttons
    if self.is_wiki_fullpage then
        -- A save and a close button
        buttons = {
            {
                {
                    id = "save",
                    text = _("Save as EPUB"),
                    callback = function()
                        local InfoMessage = require("ui/widget/infomessage")
                        local ConfirmBox = require("ui/widget/confirmbox")
                        -- if forced_lang was specified, it may not be in our wiki_languages,
                        -- but ReaderWikipedia will have put it in result.lang
                        local lang = self.lang or self.wiki_languages[1]
                        -- Find a directory to save file into
                        local dir
                        if G_reader_settings:isTrue("wikipedia_save_in_book_dir") and not self:isDocless() then
                            local last_file = G_reader_settings:readSetting("lastfile")
                            if last_file then
                                dir = last_file:match("(.*)/")
                            end
                        end
                        if not dir then dir = G_reader_settings:readSetting("wikipedia_save_dir")
                                           or G_reader_settings:readSetting("home_dir")
                                           or require("apps/filemanager/filemanagerutil").getDefaultDir() end
                        if not dir or not util.pathExists(dir) then
                            UIManager:show(InfoMessage:new{
                                text = _("No folder to save article to could be found."),
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
                                                        UIManager:broadcastEvent(Event:new("SetupShowReader"))

                                                        if self.ui then
                                                            -- close Highlight menu if any still shown
                                                            if self.ui.highlight and self.ui.highlight.highlight_dialog then
                                                                self.ui.highlight:onClose()
                                                            end
                                                            self.ui:onClose()
                                                        end

                                                        local ReaderUI = require("apps/reader/readerui")
                                                        ReaderUI:showReader(epub_path)
                                                    end)
                                                end,
                                            })
                                        else
                                            UIManager:show(InfoMessage:new{
                                                text = _("Saving Wikipedia article failed or interrupted."),
                                            })
                                        end
                                    end)
                                end)
                            end
                        })
                    end,
                },
                {
                    id = "close",
                    text = _("Close"),
                    callback = function()
                        self:onClose()
                    end,
                    hold_callback = function()
                        self:onHoldClose()
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
                    id = "prev_dict",
                    text = prev_dict_text,
                    vsync = true,
                    enabled = self:isPrevDictAvaiable(),
                    callback = function()
                        self:changeToPrevDict()
                    end,
                    hold_callback = function()
                        self:changeToFirstDict()
                    end,
                },
                {
                    id = "highlight",
                    text = self:getHighlightText(),
                    enabled = not self:isDocless() and self.highlight ~= nil,
                    callback = function()
                        if self:getHighlightText() == highlight_strings.highlight then
                            self.ui:handleEvent(Event:new("Highlight"))
                        else
                            self.ui:handleEvent(Event:new("Unhighlight"))
                        end
                        -- Just update, repaint and refresh *this* button
                        local this = self.button_table:getButtonById("highlight")
                        if not this then return end
                        this:enableDisable(self.highlight ~= nil)
                        this:setText(self:getHighlightText(), this.width)
                        this:refresh()
                    end,
                },
                {
                    id = "next_dict",
                    text = next_dict_text,
                    vsync = true,
                    enabled = self:isNextDictAvaiable(),
                    callback = function()
                        self:changeToNextDict()
                    end,
                    hold_callback = function()
                        self:changeToLastDict()
                    end,
                },
            },
            {
                {
                    id = "wikipedia",
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
                -- Rotate thru available wikipedia languages, or Search in book if dict window
                {
                    id = "search",
                    -- if more than one language, enable it and display "current lang > next lang"
                    -- otherwise, just display current lang
                    text = self.is_wiki
                        and ( #self.wiki_languages > 1 and BD.wrap(self.wiki_languages[1]).." > "..BD.wrap(self.wiki_languages[2])
                                                        or self.wiki_languages[1] ) -- (this " > " will be auro-mirrored by bidi)
                        or _("Search"),
                    enabled = self:canSearch(),
                    callback = function()
                        if self.is_wiki then
                            -- We're rotating: forward this flag from the one we're closing so
                            -- that ReaderWikipedia can give it to the one we'll be showing
                            DictQuickLookup.rotated_update_wiki_languages_on_close = self.update_wiki_languages_on_close
                            self:lookupWikipedia(false, nil, nil, self.wiki_languages[2])
                            self:onClose(true)
                        else
                            self.ui:handleEvent(Event:new("HighlightSearch"))
                            self:onClose(true) -- don't unhighlight (or we might erase a search hit)
                        end
                    end,
                },
                {
                    id = "close",
                    text = _("Close"),
                    callback = function()
                        self:onClose()
                    end,
                    hold_callback = function()
                        self:onHoldClose()
                    end,
                },
            },
        }
        if not self.is_wiki and self.selected_link ~= nil then
            -- If highlighting some word part of a link (which should be rare),
            -- add a new first row with a single button to follow this link.
            table.insert(buttons, 1, {
                {
                    id = "link",
                    text = _("Follow Link"),
                    callback = function()
                        local link = self.selected_link.link or self.selected_link
                        self.ui.link:onGotoLink(link)
                        self:onClose()
                    end,
                },
            })
        end
    end
    if self.tweak_buttons_func then
        self:tweak_buttons_func(buttons)
    end
    -- Bottom buttons get a bit less padding so their line separators
    -- reach out from the content to the borders a bit more
    local buttons_padding = Size.padding.default
    local buttons_width = inner_width - 2*buttons_padding
    self.button_table = ButtonTable:new{
        width = buttons_width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    -- Margin from screen edges
    local margin_top = Size.margin.default
    local margin_bottom = Size.margin.default
    if self.ui and self.ui.view and self.ui.view.footer_visible then
        -- We want to let the footer visible (as it can show time, battery level
        -- and wifi state, which might be useful when spending time reading
        -- definitions or wikipedia articles)
        margin_bottom = margin_bottom + self.ui.view.footer:getHeight()
    end
    local avail_height = Screen:getHeight() - margin_top - margin_bottom
    -- Region in which the window will be aligned center/top/bottom:
    self.region = Geom:new{
        x = 0,
        y = margin_top,
        w = Screen:getWidth(),
        h = avail_height,
    }
    self.align = "center"

    local others_height = frame_bordersize * 2 -- DictQuickLookup border
                        + self.dict_title:getHeight()
                        + top_to_word_span:getSize().h
                        + lookup_word:getSize().h
                        + word_to_definition_span:getSize().h
                        + definition_to_bottom_span:getSize().h
                        + self.button_table:getSize().h

    -- To properly adjust the definition to the height of text, we need
    -- the line height a ScrollTextWidget will use for the current font
    -- size (we'll then use this perfect height for ScrollTextWidget,
    -- but also for ScrollHtmlWidget, where it doesn't matter).
    if not self.definition_line_height then
        local test_widget = ScrollTextWidget:new{
            text = "z",
            face = self.content_face,
            width = self.content_width,
            height = self.definition_height,
            for_measurement_only = true, -- flag it as a dummy, so it won't trigger any bogus repaint/refresh...
        }
        self.definition_line_height = test_widget:getLineHeight()
        test_widget:free(true)
    end

    if is_large_window then
        -- Available height for definition + components
        self.height = avail_height
        self.definition_height = self.height - others_height
        local nb_lines = math.floor(self.definition_height / self.definition_line_height)
        self.definition_height = nb_lines * self.definition_line_height
        local pad = self.height - others_height - self.definition_height
        -- put that unused height on the above span
        word_to_definition_span.width = word_to_definition_span.width + pad
    else
        -- Definition height was previously computed as 0.5*0.7*screen_height, so keep
        -- it that way. Components will add themselves to that.
        self.definition_height = math.floor(avail_height * 0.5 * 0.7)
        -- But we want it to fit to the lines that will show, to avoid
        -- any extra padding
        local nb_lines = Math.round(self.definition_height / self.definition_line_height)
        self.definition_height = nb_lines * self.definition_line_height
        self.height = self.definition_height + others_height
        if self.word_boxes and #self.word_boxes > 0 then
            -- Try to not hide the highlighted word. We don't want to always
            -- get near it if we can stay center, so that more context around
            -- the word is still visible with the dict result.
            -- But if we were to be drawn over the word, move a bit if possible.

            -- In most cases boxes will be a single sbox, but handle multiple
            -- sboxes by taking the top and bottom y values.
            local word_box_top
            local word_box_bottom
            for _, box in ipairs(self.word_boxes) do
                local box_top = box.y
                local box_bottom = box.y + box.h
                if not word_box_top or word_box_top > box_top then
                    word_box_top = box_top
                end
                if not word_box_bottom or word_box_bottom < box_bottom then
                    word_box_bottom = box_bottom
                end
            end

            -- Don't stick to the box, ensure a minimal padding between box and
            -- window.
            word_box_top = word_box_top - Size.padding.small
            word_box_bottom = word_box_bottom + Size.padding.small

            local half_visible_height = (avail_height - self.height) / 2
            if word_box_bottom > half_visible_height and word_box_top <= half_visible_height + self.height then
                -- word would be covered by our centered window
                if word_box_bottom <= avail_height - self.height then
                    -- Window can be moved just below word
                    self.region.y = word_box_bottom
                    self.region.h = self.region.h - word_box_bottom
                    self.align = "top"
                elseif word_box_top > self.height then
                    -- Window can be moved just above word
                    self.region.y = 0
                    self.region.h = word_box_top
                    self.align = "bottom"
                end
            end
        end
    end

    -- Instantiate self.text_widget
    self:_instantiateScrollWidget()

    -- word definition
    self.definition_widget = FrameContainer:new{
        padding = 0,
        padding_left = content_padding_h,
        padding_right = content_padding_h,
        margin = 0,
        bordersize = 0,
        self.text_widget,
    }

    self.dict_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = frame_bordersize,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.dict_title,
            top_to_word_span,
            -- word
            CenterContainer:new{
                dimen = Geom:new{
                    w = inner_width,
                    h = lookup_word:getSize().h,
                },
                lookup_word,
            },
            word_to_definition_span,
            -- definition
            CenterContainer:new{
                dimen = Geom:new{
                    w = inner_width,
                    h = self.definition_widget:getSize().h,
                },
                self.definition_widget,
            },
            definition_to_bottom_span,
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = inner_width,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
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

    self[1] = WidgetContainer:new{
        align = self.align,
        dimen = self.region,
        self.movable,
    }

    -- We're a new window
    table.insert(DictQuickLookup.window_list, self)
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

        ol, ul, menu {
            margin: 0; padding: 0 1.7em;
        }
    ]]
    -- For reference, MuPDF declarations with absolute units:
    --  "blockquote{margin:1em 40px}"
    --  "dd{margin:0 0 0 40px}"
    --  "ol,ul,menu {margin:1em 0;padding:0 0 0 30pt}"
    --  "hr{border-width:1px;}"
    --  "td,th{padding:1px}"
    --
    -- MuPDF doesn't currently scale CSS pixels, so we have to use a font-size based measurement.
    -- Unfortunately MuPDF doesn't properly support `rem` either, which it bases on a hard-coded
    -- value of `16px`, so we have to go with `em` (or `%`).
    --
    -- These `em`-based margins can vary slightly, but it's the best available compromise.
    --
    -- We also keep left and right margin the same so it'll display as expected in RTL.
    -- Because MuPDF doesn't currently support `margin-start`, this results in a slightly
    -- unconventional but hopefully barely noticeable right margin for <dd>.
    --
    -- For <ul> and <ol>, bullets and numbers are displayed in the margin/padding, so
    -- we need a bit more for them to not get truncated (1.7em allows for 2 digits list
    -- item numbers). Unfortunately, because we want this also for RTL, this space is
    -- wasted on the other side...

    if self.css then
        return css .. self.css
    end
    return css
end

-- Used in init & update to instantiate the Scroll*Widget that self.text_widget points to
function DictQuickLookup:_instantiateScrollWidget()
    if self.is_html then
        self.shw_widget = ScrollHtmlWidget:new{
            html_body = self.definition,
            css = self:getHtmlDictionaryCss(),
            default_font_size = Screen:scaleBySize(self.dict_font_size),
            width = self.content_width,
            height = self.definition_height,
            dialog = self,
            html_link_tapped_callback = function(link)
                self.html_dictionary_link_tapped_callback(self.dictionary, link)
            end,
        }
        self.text_widget = self.shw_widget
    else
        self.stw_widget = ScrollTextWidget:new{
            text = self.definition,
            face = self.content_face,
            width = self.content_width,
            height = self.definition_height,
            dialog = self,
            justified = G_reader_settings:nilOrTrue("dict_justify"), -- allow for disabling justification
            lang = self.lang and self.lang:lower() or self.lang_out,
            para_direction_rtl = self.rtl_lang,     -- only available on wikipedia results
            auto_para_direction = not self.is_wiki, -- only for dict results (we don't know their lang)
            image_alt_face = self.image_alt_face,
            images = self.images,
        }
        self.text_widget = self.stw_widget
    end
end

function DictQuickLookup:update()
    -- self[1] is a WidgetContainer, its free method will call free on each of its child widget with a free method.
    -- Here, that's the definitions' TextBoxWidget & HtmlBoxWidget,
    -- to release their bb, MuPDF instance, and scheduled image_update_action.
    self[1]:free()

    -- Update TextWidgets
    self.dict_title:setTitle(self.displaydictname)
    if self.displaynb then
        self.displaynb_text:setText(self.displaynb)
    end
    self.lookup_word_text:setText(self.displayword)
    self.lookup_word_text.lang = self.lang_in

    -- Update Buttons
    if not self.is_wiki_fullpage then
        local prev_dict_btn = self.button_table:getButtonById("prev_dict")
        if prev_dict_btn then
            prev_dict_btn:enableDisable(self:isPrevDictAvaiable())
        end
        local next_dict_btn = self.button_table:getButtonById("next_dict")
        if next_dict_btn then
            next_dict_btn:enableDisable(self:isNextDictAvaiable())
        end
    end

    -- Update main text widgets
    if self.is_html and self.shw_widget then
        -- Re-use our ScrollHtmlWidget (self.shw_widget)
        -- NOTE: The recursive free via our WidgetContainer (self[1]) above already released the previous MµPDF document instance ;)
        self.text_widget.htmlbox_widget:setContent(self.definition, self:getHtmlDictionaryCss(), Screen:scaleBySize(self.dict_font_size))
        -- Scroll back to top
        self.text_widget:resetScroll()
    elseif not self.is_html and self.stw_widget then
        -- Re-use our ScrollTextWidget (self.stw_widget)
        -- Update properties that may change across results (as done in DictQuickLookup:_instantiateScrollWidget())
        self.text_widget.text_widget.text = self.definition
        self.text_widget.text_widget.charlist = nil -- (required when use_xtext=false for proper re-init)
        self.text_widget.text_widget.lang = self.lang and self.lang:lower() or self.lang_out
        self.text_widget.text_widget.para_direction_rtl = self.rtl_lang
        self.text_widget.text_widget.images = self.images
        -- Scroll back to the top, àla TextBoxWidget:scrollToTop
        self.text_widget.text_widget.virtual_line_num = 1
        -- NOTE: The recursive free via our WidgetContainer (self[1]) above already free'd us ;)
        self.text_widget.text_widget:init()
        -- Reset the scrollbar's state
        self.text_widget:resetScroll()
    else
        -- We jumped from HTML to Text (or vice-versa), we need a new widget instance
        self:_instantiateScrollWidget()
        -- Update *all* the references to self.text_widget
        self.definition_widget[1] = self.text_widget
        -- Destroy the previous "opposite type" widget
        if self.is_html then
            self.stw_widget = nil
        else
            self.shw_widget = nil
        end
    end

    -- If we're translucent, reset alpha to make the new definition actually readable.
    if self.movable.alpha then
        self.movable.alpha = nil
    end

    UIManager:setDirty(self, function()
        return "partial", self.dict_frame.dimen
    end)
end

function DictQuickLookup:getInitialVisibleArea()
    -- Some positionning happens only at paintTo() time, but we want
    -- to know this before. So, do a bit like WidgetContainer does
    -- (without any MovableContainer offset)
    local dict_size = self.dict_frame:getSize()
    local area = Geom:new{
        w = dict_size.w,
        h = dict_size.h,
        x = self.region.x + math.floor((self.region.w - dict_size.w)/2)
    }
    if self.align == "top" then
        area.y = self.region.y
    elseif self.align == "bottom" then
        area.y = self.region.y + self.region.h - dict_size.h
    elseif self.align == "center" then
        area.x = self.region.y + math.floor((self.region.h - dict_size.h)/2)
    end
    return area
end

function DictQuickLookup:onCloseWidget()
    -- Our TextBoxWidget/HtmlBoxWidget/TextWidget/ImageWidget are proper child widgets,
    -- so this event will propagate to 'em, and they'll free their resources.

    -- What's left is stuff that isn't directly in our widget tree...
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

    -- Drop our ref from the static class member
    for i = #DictQuickLookup.window_list, 1, -1 do
        local window = DictQuickLookup.window_list[i]
        -- We should only find a single match, but, better safe than sorry...
        if window == self then
            table.remove(DictQuickLookup.window_list, i)
        end
    end

    -- NOTE: Drop region to make it a full-screen flash
    UIManager:setDirty(nil, function()
        return "flashui", nil
    end)
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

function DictQuickLookup:changeToFirstDict()
    if self:isPrevDictAvaiable() then
        self:changeDictionary(1)
    end
end

function DictQuickLookup:changeToLastDict()
    if self:isNextDictAvaiable() then
        self:changeDictionary(#self.results)
    end
end

function DictQuickLookup:changeDictionary(index, skip_update)
    if not self.results[index] then return end
    self.dict_index = index
    self.dictionary = self.results[index].dict
    self.lookupword = self.results[index].word
    self.definition = self.results[index].definition
    self.is_wiki_fullpage = self.results[index].is_wiki_fullpage
    self.is_html = self.results[index].is_html
    self.css = self.results[index].css
    self.lang = self.results[index].lang
    local ifo_lang = self.results[index].ifo_lang
    self.lang_in = ifo_lang and ifo_lang.lang_in or nil
    self.lang_out = ifo_lang and ifo_lang.lang_out or nil
    self.rtl_lang = self.results[index].rtl_lang
    self.images = self.results[index].images
    if self.images and #self.images > 0 then
        -- We'll be giving some images to textboxwidget that will
        -- load and display them. We'll need to free these blitbuffers
        -- when we're done.
        self.images_cleanup_needed = true
    end
    if self.is_wiki_fullpage then
        self.displayword = self.lookupword
        self.displaynb = nil
    else
        self.displayword = self.lookupword
        -- show "dict_index / nbresults" so we know where we're at and what's yet to see
        self.displaynb = T("%1 / %2", index, #self.results)
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
    self.displaydictname = self.dictionary
    if self.preferred_dictionaries then
        -- If current result is from a preferred dictionary, prepend dict name
        -- (shown in the window title) with its preference number
        for idx, name in ipairs(self.preferred_dictionaries) do
            if self.dictionary == name then
                -- Use number in circle symbol (U+2460...2473)
                local symbol = util.unicodeCodepointToUtf8(0x245F + (idx < 20 and idx or 20))
                self.displaydictname = symbol .. " " .. self.displaydictname
                break
            end
        end
    end

    -- Don't call update when called from init
    if not skip_update then
        self:update()
    end
end

--[[ No longer used
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
]]--

function DictQuickLookup:onReadNextResult()
    self:changeToNextDict()
    return true
end

function DictQuickLookup:onReadPrevResult()
    local prev_index = self.dict_index
    self:changeToPrevDict()
    if self.dict_index ~= prev_index then
        -- Jump directly to bottom of previous dict definition
        -- to keep "continuous reading with tap" consistent
        self.definition_widget[1]:scrollToRatio(1) -- 1 = 100% = bottom
    end
    return true
end

function DictQuickLookup:onTap(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.dict_frame.dimen) then
        self:onClose()
        return true
    end
    if ges_ev.pos:intersectWith(self.dict_title.dimen) and not self.is_wiki then
        self.ui:handleEvent(Event:new("TogglePreferredDict", self.dictionary))
        -- Re-display current result, with title bar updated
        self:changeDictionary(self.dict_index)
        return true
    end
    if ges_ev.pos:intersectWith(self.definition_widget.dimen) then
        -- Allow for changing dict with tap (tap event will be first
        -- processed for scrolling definition by ScrollTextWidget, which
        -- will pop it up for us here when it can't scroll anymore).
        -- This allow for continuous reading of results' definitions with tap.
        if BD.flipIfMirroredUILayout(ges_ev.pos.x < Screen:getWidth()/2) then
            self:onReadPrevResult()
        else
            self:onReadNextResult()
        end
    end
    return true
end

function DictQuickLookup:onClose(no_clear)
    for menu, _ in pairs(self.menu_opened) do
        UIManager:close(menu)
    end
    self.menu_opened = {}

    UIManager:close(self)

    if self.update_wiki_languages_on_close then
        -- except if we got no result for current language
        if not self.results.no_result then
            self.ui:handleEvent(Event:new("UpdateWikiLanguages", self.wiki_languages))
        end
    end
    if self.highlight and not no_clear then
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
    -- Pop the windows FILO
    for i = #DictQuickLookup.window_list, 1, -1 do
        local window = DictQuickLookup.window_list[i]
        window:onClose(no_clear)
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
            -- update footer (time & battery)
            self.ui:handleEvent(Event:new("UpdateFooter", true))
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
    self.input_dialog = InputDialog:new{
        title = _("Enter a word or phrase to look up"),
        input = hint,
        input_hint = hint,
        buttons = {
            {
                {
                    text = _("Translate"),
                    callback = function()
                        local text = self.input_dialog:getInputText()
                        if text ~= "" then
                            UIManager:close(self.input_dialog)
                            Translator:showTranslation(text, true)
                        end
                    end,
                },
                {
                    text = _("Search Wikipedia"),
                    is_enter_default = self.is_wiki,
                    callback = function()
                        local text = self.input_dialog:getInputText()
                        if text ~= "" then
                            UIManager:close(self.input_dialog)
                            self.is_wiki = true
                            self:lookupWikipedia(false, text, true)
                        end
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("Search dictionary"),
                    is_enter_default = not self.is_wiki,
                    callback = function()
                        local text = self.input_dialog:getInputText()
                        if text ~= "" then
                            UIManager:close(self.input_dialog)
                            self.is_wiki = false
                            self.ui:handleEvent(Event:new("LookupWord", text, true))
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function DictQuickLookup:lookupWikipedia(get_fullpage, word, is_sane, lang)
    if not lang then
        -- Use the lang of the current or nearest is_wiki DictQuickLookup.
        -- Otherwise, first lang in ReaderWikipedia.wiki_languages will be used.
        for i = #DictQuickLookup.window_list, 1, -1 do
            local window = DictQuickLookup.window_list[i]
            if window.is_wiki and window.lang then
                lang = window.lang
                break
            end
        end
    end
    if not word then
        if get_fullpage then
            -- we use the word of the displayed result's definition, which
            -- is the exact title of the full wikipedia page
            word = self.lookupword
            is_sane = true
        else
            -- we use the original word that was querried
            word = self.word
            is_sane = false
        end
    end
    -- Keep providing self.word_boxes so new windows keep being positionned to not hide it
    self.ui:handleEvent(Event:new("LookupWikipedia", word, is_sane, self.word_boxes, get_fullpage, lang))
end

function DictQuickLookup:showResultsMenu()
    -- Show one row: "| word | dict |" for each result
    local width = math.floor(self.width * 0.75)
    local right_width = math.floor(width * 0.5)
    local font_size = 18
    local button_dialog
    local buttons = {}
    for idx, result in ipairs(self.results) do
        -- Show in bold the currently displayed result
        local bold = idx == self.dict_index
        local row = {
            {
                text = result.word,
                lang = result.ifo_lang and result.ifo_lang.lang_in or nil,
                font_size = font_size,
                font_bold = bold,
                align = "left",
                callback = function()
                    self.menu_scrolled_offsets["main"] = button_dialog:getScrolledOffset()
                    self.menu_opened[button_dialog] = nil
                    UIManager:close(button_dialog)
                    self:changeDictionary(idx)
                end,
                hold_callback = function()
                    -- Allow doing another lookup with this result word
                    self.ui:handleEvent(Event:new("LookupWord", result.word))
                end,
            },
            {
                text = result.dict,
                lang = result.ifo_lang and result.ifo_lang.lang_out or nil,
                font_size = font_size,
                font_bold = bold,
                width = right_width,
                callback = function()
                    self.menu_scrolled_offsets["main"] = button_dialog:getScrolledOffset()
                    self.menu_opened[button_dialog] = nil
                    UIManager:close(button_dialog)
                    self:changeDictionary(idx)
                end,
            },
        }
        table.insert(buttons, row)
    end
    button_dialog = ButtonDialog:new{
        width = width,
        -- We don't provide shrink_unneeded_width=true as it's ugly with small words
        buttons = buttons,
        anchor = function()
            return self.dict_title.left_button.image.dimen, true -- pop down
        end,
        tap_close_callback = function()
            self.menu_scrolled_offsets["main"] = button_dialog:getScrolledOffset()
            self.menu_opened[button_dialog] = nil
        end
    }
    button_dialog:setScrolledOffset(self.menu_scrolled_offsets["main"])
    self.menu_opened[button_dialog] = true
    UIManager:show(button_dialog)
end

function DictQuickLookup:showResultsAltMenu()
    -- Alternative listing with long-press:
    -- Show one row: "| dict | word or N results |" for each dictionary returning results
    local dicts = {}
    local dict_results = {}
    for idx, result in ipairs(self.results) do
        local dict = result.dict
        if not dict_results[dict] then
            dict_results[dict] = { idx }
            table.insert(dicts, dict)
        else
            table.insert(dict_results[dict], idx)
        end
    end
    local max_width = math.floor(self.width * 0.75)
    local right_width = math.floor(max_width * 0.25)
    local font_size = 18
    local button_dialog
    local buttons = {}
    for dictnum, dict in ipairs(dicts) do
        local results = dict_results[dict]
        local first_result = self.results[results[1]]
        -- Show in bold only the currently displayed result's dict
        local bold = util.arrayContains(results, self.dict_index)
        local row = {{
            text = dict,
            lang = first_result.ifo_lang and first_result.ifo_lang.lang_out or nil,
            font_size = font_size,
            font_bold = bold,
            align = "left",
            callback = function()
                self.menu_scrolled_offsets["alt"] = button_dialog:getScrolledOffset()
                self.menu_opened[button_dialog] = nil
                UIManager:close(button_dialog)
                self:changeDictionary(results[1])
            end,
        }}
        -- Right button
        local button_id = "button"..dictnum
        local text, lang, avoid_text_truncation, is_single_result, hold_callback
        if #results == 1 then
            -- Show the headword, possibly truncated (otherwise, long words
            -- would get displayed in a really small font size).
            -- If truncated, we'll show it full in a popup
            text = first_result.word
            lang = first_result.ifo_lang and first_result.ifo_lang.lang_in or nil
            avoid_text_truncation = false
            is_single_result = true
            hold_callback = function()
                -- Allow doing another lookup with this result word
                self.ui:handleEvent(Event:new("LookupWord", first_result.word))
            end
        else
            text = T(_("%1 results"), #results)
        end
        local callback = function()
            local source_button = button_dialog:getButtonById(button_id)
            if is_single_result and not source_button.label_widget:isTruncated() then
                -- Not truncated: jump directly to the result
                self.menu_scrolled_offsets["alt"] = button_dialog:getScrolledOffset()
                self.menu_opened[button_dialog] = nil
                UIManager:close(button_dialog)
                self:changeDictionary(results[1])
                return
            end
            local button_dialog2
            local buttons2 = {}
            local lang2 = first_result.ifo_lang and first_result.ifo_lang.lang_in or nil -- same for all results
            for res=1, #results do
                table.insert(buttons2, {{
                    text = self.results[results[res]].word,
                    lang = lang2,
                    font_size = font_size,
                    font_bold = results[res] == self.dict_index,
                    callback = function()
                        self.menu_scrolled_offsets["alt_sub"..dictnum] = button_dialog2:getScrolledOffset()
                        self.menu_opened[button_dialog2] = nil
                        UIManager:close(button_dialog2)
                        self.menu_scrolled_offsets["alt"] = button_dialog:getScrolledOffset()
                        self.menu_opened[button_dialog] = nil
                        UIManager:close(button_dialog)
                        self:changeDictionary(results[res])
                    end,
                    hold_callback = function()
                        -- Allow doing another lookup with this result word
                        self.ui:handleEvent(Event:new("LookupWord", self.results[results[res]].word))
                    end,
                }})
            end
            button_dialog2 = ButtonDialog:new{
                width = right_width*2, -- larger, to have room for long words
                buttons = buttons2,
                anchor = function()
                    return source_button.dimen, true -- pop down
                end,
                tap_close_callback = function()
                    self.menu_scrolled_offsets["alt_sub"..dictnum] = button_dialog2:getScrolledOffset()
                    self.menu_opened[button_dialog2] = nil
                end
            }
            button_dialog2:setScrolledOffset(self.menu_scrolled_offsets["alt_sub"..dictnum])
            self.menu_opened[button_dialog2] = true
            UIManager:show(button_dialog2)
        end
        table.insert(row, {
            text = text,
            lang = lang,
            avoid_text_truncation = avoid_text_truncation,
            font_size = font_size,
            font_bold = bold,
            width = right_width,
            callback = callback,
            hold_callback = hold_callback,
            id = button_id,
        })
        table.insert(buttons, row)
    end
    button_dialog = ButtonDialog:new{
        width = max_width,
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.dict_title.left_button.image.dimen, true -- pop down
        end,
        tap_close_callback = function()
            self.menu_scrolled_offsets["alt"] = button_dialog:getScrolledOffset()
            self.menu_opened[button_dialog] = nil
        end
    }
    button_dialog:setScrolledOffset(self.menu_scrolled_offsets["alt"])
    self.menu_opened[button_dialog] = true
    UIManager:show(button_dialog)
end

function DictQuickLookup:showWikiResultsMenu()
    -- Show one row with each result's article title
    local max_width = math.floor(self.width * 0.75)
    local font_size = 18
    local button_dialog
    local buttons = {}
    for idx, result in ipairs(self.results) do
        local bold = idx == self.dict_index
        local row = {{
            text = result.word,
            lang = result.lang,
            font_size = font_size,
            font_bold = bold,
            align = "left",
            callback = function()
                self.menu_scrolled_offsets["wiki"] = button_dialog:getScrolledOffset()
                self.menu_opened[button_dialog] = nil
                UIManager:close(button_dialog)
                self:changeDictionary(idx)
            end,
            hold_callback = function()
                -- Allow doing another lookup with this result title
                self:lookupWikipedia(false, result.word)
            end,
        }}
        table.insert(buttons, row)
    end
    button_dialog = ButtonDialog:new{
        width = max_width,
        shrink_unneeded_width = true,
        buttons = buttons,
        -- We requested 30 results, so we will probably be scrolling.
        -- If we do, ensure we use these values (they will all make full pages
        -- if we get 30 results), depending on what the screen height allows.
        rows_per_page = { 15, 10, 6 },
        anchor = function()
            return self.dict_title.left_button.image.dimen, true -- pop down
        end,
        tap_close_callback = function()
            self.menu_scrolled_offsets["wiki"] = button_dialog:getScrolledOffset()
            self.menu_opened[button_dialog] = nil
        end
    }
    button_dialog:setScrolledOffset(self.menu_scrolled_offsets["wiki"])
    self.menu_opened[button_dialog] = true
    UIManager:show(button_dialog)
end

return DictQuickLookup
