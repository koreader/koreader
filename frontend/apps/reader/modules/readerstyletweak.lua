local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CssTweaks = require("ui/data/css_tweaks")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

-- Simple widget for showing tweak info
local TweakInfoWidget = InputContainer:new{
    tweak = nil,
    is_global_default = nil,
    toggle_global_default_callback = function() end,
    modal = true,
    width = math.floor(Screen:getWidth() * 0.75),
}

function TweakInfoWidget:init()
    local tweak = self.tweak
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            Close = { {"Back"}, doc = "cancel" }
        }
    end

    local content = VerticalGroup:new{
        TextBoxWidget:new{
            text = tweak.title,
            bold = true,
            face = Font:getFace("infofont"),
            width = self.width,
        },
        VerticalSpan:new{
            width = Size.padding.large,
        },
    }
    if tweak.description then
        table.insert(content,
            TextBoxWidget:new{
                text = tweak.description,
                face = Font:getFace("smallinfofont"),
                width = self.width,
            }
        )
        table.insert(content, VerticalSpan:new{
            width = Size.padding.large,
        })
    end

    -- This css TextBoxWidget may make the widget overflow screen with
    -- large css text. For now, we don't bother with the complicated
    -- setup of a scrollable ScrollTextWidget.
    local css = tweak.css
    if not css and tweak.css_path then
        css = ""
        local f = io.open(tweak.css_path, "r")
        if f then
            css = f:read("*all")
            f:close()
        end
    end
    self.css_text = util.trim(css)
    self.css_frame = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.large,
        TextBoxWidget:new{
            text = self.css_text,
            face = Font:getFace("infont", 16),
            width = self.width - 2*Size.padding.large,
            para_direction_rtl = false, -- LTR
        }
    }
    table.insert(content, self.css_frame)

    if self.is_global_default then
        table.insert(content, VerticalSpan:new{
            width = Size.padding.large,
        })
        table.insert(content,
            TextBoxWidget:new{
                text = _("This tweak is applied on all books."),
                face = Font:getFace("smallinfofont"),
                width = self.width,
            }
        )
    end

    content = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.large,
        padding_top = Size.padding.default,
        content,
    }

    local buttons = {
        {
            text = _("Close"),
            callback = function()
                UIManager:close(self)
            end,
        },
        {
            text = self.is_global_default and _("Don't use on all books") or _("Use on all books"),
            callback = function()
                self.toggle_global_default_callback()
                UIManager:close(self)
            end,
        },
    }

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = { buttons },
        zero_sep = true,
        show_parent = self,
    }

    self.movable = MovableContainer:new{
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            radius = Size.radius.window,
            margin = Size.margin.default,
            padding = Size.padding.default,
            padding_bottom = 0, -- no padding below buttontable
            VerticalGroup:new{
                align = "left",
                content,
                button_table,
            }
        }
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable
    }
end

function TweakInfoWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function TweakInfoWidget:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function TweakInfoWidget:onClose()
    UIManager:close(self)
    return true
end

function TweakInfoWidget:onTap(arg, ges)
    if ges.pos:intersectWith(self.css_frame.dimen) and Device:hasClipboard() then
        -- Tap inside CSS text copies it into clipboard (so it
        -- can be pasted into the book-specific tweak editor)
        -- (Add \n on both sides for easier pasting)
        Device.input.setClipboardText("\n"..self.css_text.."\n")
        UIManager:show(Notification:new{
            text = _("CSS text copied to clipboard"),
            timeout = 2
        })
        return true
    elseif ges.pos:notIntersectWith(self.movable.dimen) then
        -- Tap outside closes widget
        self:onClose()
        return true
    end
    return false
end

function TweakInfoWidget:onSelect()
    if self.selected.x == 1 then
        self:toggle_global_default_callback()
    end
    UIManager:close(self)
    return true
end

-- Ordering function for tweaks when appened to css_test.
-- The order needs to be consistent for crengine's stylesheet change
-- detection code to not invalidate cache across loadings.
local function tweakOrdering(l, r)
    if l.priority ~= r.priority then
        -- lower priority first in the CSS text
        return l.priority < r.priority
    end
    -- same priority: order by ids
    return l.id < r.id
end

-- Reader component for managing tweaks. The aggregated css_text
-- is actually requested from us and applied by ReaderTypeset
local ReaderStyleTweak = InputContainer:new{
    tweaks_by_id = nil,
    tweaks_table = nil, -- sub-menu items
    nb_enabled_tweaks = 0, -- for use by main menu item
    css_text = nil, -- aggregated css text from tweaks individual css snippets
    enabled = true, -- allows for toggling between selected tweaks / none
}

function ReaderStyleTweak:isTweakEnabled(tweak_id)
    local g_enabled = false
    local enabled = false
    if self.global_tweaks[tweak_id] then
        enabled = true
        g_enabled = true
    end
    if self.doc_tweaks[tweak_id] == true then
        enabled = true
    elseif self.doc_tweaks[tweak_id] == false then
        enabled = false
    end
    return enabled, g_enabled
end

function ReaderStyleTweak:nbTweaksEnabled(sub_item_table)
    local nb_enabled = 0
    local nb_found = 0
    for _, item in ipairs(sub_item_table) do
        if item.sub_item_table then
            local sub_nb_enabled, sub_nb_found = self:nbTweaksEnabled(item.sub_item_table)
            nb_enabled = nb_enabled + sub_nb_enabled
            nb_found = nb_found + sub_nb_found
        elseif item.tweak_id then
            if self:isTweakEnabled(item.tweak_id) then
                nb_enabled = nb_enabled + 1
            end
            nb_found = nb_found + 1
        end
    end
    return nb_enabled, nb_found
end

-- Called by ReaderTypeset, returns the already built string
function ReaderStyleTweak:getCssText()
    return self.css_text
end

-- Build css_text, and request ReaderTypeset to apply it if wanted
function ReaderStyleTweak:updateCssText(apply)
    if self.enabled then
        local tweaks = {}
        for id, enabled in pairs(self.global_tweaks) do
            -- there are only enabled tweaks in global_tweaks, but we don't
            -- add them here if they appear in doc_tweaks (if enabled in
            -- doc_tweaks, they'll be added below; if disabled, they should
            -- not be added)
            if self.doc_tweaks[id] == nil then
                table.insert(tweaks, self.tweaks_by_id[id])
            end
        end
        for id, enabled in pairs(self.doc_tweaks) do
            -- there are enabled (true) and disabled (false) tweaks in doc_tweaks
            if self.doc_tweaks[id] == true then
                table.insert(tweaks, self.tweaks_by_id[id])
            end
        end
        table.sort(tweaks, tweakOrdering)
        self.nb_enabled_tweaks = 0
        local css_snippets = {}
        for _, tweak in ipairs(tweaks) do
            self.nb_enabled_tweaks = self.nb_enabled_tweaks + 1
            local css = tweak.css
            if not css and tweak.css_path then
                css = ""
                local f = io.open(tweak.css_path, "r")
                if f then
                    css = f:read("*all")
                    f:close()
                end
                -- We could store what's been read into tweak.css to avoid
                -- re-reading it, but this will allow a user to experiment
                -- wihout having to restart KOReader
            end
            css = util.trim(css)
            table.insert(css_snippets, css)
        end
        if self.book_style_tweak and self.book_style_tweak_enabled then
            self.nb_enabled_tweaks = self.nb_enabled_tweaks + 1
            table.insert(css_snippets, self.book_style_tweak)
        end
        self.css_text = table.concat(css_snippets, "\n")
        logger.dbg("made tweak css:\n".. self.css_text .. "[END]")
    else
        self.css_text = nil
        logger.dbg("made no tweak css (Style tweaks disabled)")
    end
    if apply then
        self.ui:handleEvent(Event:new("ApplyStyleSheet"))
    end
end

function ReaderStyleTweak:onReadSettings(config)
    self.enabled = not (config:readSetting("style_tweaks_enabled") == false)
    self.doc_tweaks = config:readSetting("style_tweaks") or {}
    -- Default globally enabled style tweaks (for new installations)
    -- are defined in css_tweaks.lua
    self.global_tweaks = G_reader_settings:readSetting("style_tweaks") or CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS
    self.book_style_tweak = config:readSetting("book_style_tweak") -- string or nil
    self.book_style_tweak_enabled = config:readSetting("book_style_tweak_enabled")
    self.book_style_tweak_last_edit_pos = config:readSetting("book_style_tweak_last_edit_pos")
    self:updateCssText()
end

function ReaderStyleTweak:onSaveSettings()
    if self.enabled then
        self.ui.doc_settings:delSetting("style_tweaks_enabled")
    else
        self.ui.doc_settings:saveSetting("style_tweaks_enabled", false)
    end
    self.ui.doc_settings:saveSetting("style_tweaks", util.tableSize(self.doc_tweaks) > 0 and self.doc_tweaks or nil)
    G_reader_settings:saveSetting("style_tweaks", self.global_tweaks)
    self.ui.doc_settings:saveSetting("book_style_tweak", self.book_style_tweak)
    self.ui.doc_settings:saveSetting("book_style_tweak_enabled", self.book_style_tweak_enabled)
    self.ui.doc_settings:saveSetting("book_style_tweak_last_edit_pos", self.book_style_tweak_last_edit_pos)
end

function ReaderStyleTweak:init()
    self.tweaks_by_id = {}
    self.tweaks_table = {}

    -- Add first item of sub-menu, that allows toggling between
    -- enabled tweaks / none (without the need to disable each of
    -- them)
    table.insert(self.tweaks_table, {
        text = _("Enable style tweaks (hold for info)"),
        checked_func = function() return self.enabled end,
        callback = function()
            self.enabled = not self.enabled
            self:updateCssText(true) -- apply it immediately
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new{
                text = _([[
Style tweaks allow changing small parts of book styles (including the publisher/embedded styles) to make visual adjustments or disable unwanted publisher layout choices.

Some tweaks may be useful with some books, while resulting in undesirable effects with others.

You can enable individual tweaks on this book with a tap, or view more details about a tweak and enable it on all books with hold.]])
            })
        end,
        separator = true,
    })

    -- Single function for use as enabled_func
    local is_enabled = function() return self.enabled end

    -- Generic function to recursively build a sub_item_table (as expected
    -- by TouchMenu) from a table of tweak definitions (like CssTweaks from
    -- css_tweaks.lua, or like the one we build from user styletweaks
    -- directory files and sub-directories)
    local addTweakMenuItem
    addTweakMenuItem = function(menu, item, max_per_page)
        if type(item) == "table" and #item > 0 then -- sub-menu
            local sub_item_table = {}
            sub_item_table.max_per_page = max_per_page
            for _, it in ipairs(item) do
                addTweakMenuItem(sub_item_table, it, max_per_page) -- recurse
            end
            table.insert(menu, {
                text_func = function()
                    local text = item.title or "### undefined submenu title ###"
                    local nb_enabled, nb_found = self:nbTweaksEnabled(sub_item_table) -- luacheck: no unused
                    -- We could add nb_enabled/nb_found, but that makes for
                    -- a busy/ugly menu
                    -- text = string.format("%s (%d/%d)", text, nb_enabled, nb_found)
                    if nb_enabled > 0 then
                        text = string.format("%s (%d)", text, nb_enabled)
                    end
                    return text
                end,
                enabled_func = is_enabled,
                sub_item_table = sub_item_table,
                separator = item.separator,
            })
        elseif item.id then -- tweak menu item
            -- Set a default priority of 0 if item doesn't have one
            if not item.priority then item.priority = 0 end
            self.tweaks_by_id[item.id] = item
            table.insert(menu, {
                tweak_id = item.id,
                enabled_func = is_enabled,
                checked_func = function() return self:isTweakEnabled(item.id) end,
                -- text = item.title or "### undefined tweak title ###",
                text_func = function()
                    local title = item.title or "### undefined tweak title ###"
                    if self.global_tweaks[item.id] then
                        title = title .. "   ★"
                    end
                    return title
                end,
                hold_callback = function(touchmenu_instance)
                    UIManager:show(TweakInfoWidget:new{
                        tweak = item,
                        is_global_default = self.global_tweaks[item.id],
                        toggle_global_default_callback = function()
                            if self.global_tweaks[item.id] then
                                self.global_tweaks[item.id] = nil
                            else
                                self.global_tweaks[item.id] = true
                            end
                            touchmenu_instance:updateItems()
                            self:updateCssText(true) -- apply it immediately
                        end
                    })
                end,
                callback = function()
                    -- enable/disable only for this book
                    local enabled, g_enabled = self:isTweakEnabled(item.id)
                    if enabled then
                        if g_enabled then
                            -- if globaly enabled, mark it as disabled
                            -- for this document only
                            self.doc_tweaks[item.id] = false
                        else
                            self.doc_tweaks[item.id] = nil
                        end
                    else
                        self.doc_tweaks[item.id] = true
                    end
                    self:updateCssText(true) -- apply it immediately
                end,
                separator = item.separator,
            })
        elseif item.info_text then -- informative menu item
            table.insert(menu, {
                text = item.title or "### undefined menu title ###",
                -- No check box.
                -- Show the info text when either tap or hold
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = item.info_text,
                    })
                end,
                hold_callback = function()
                    UIManager:show(InfoMessage:new{
                        text = item.info_text,
                    })
                end,
                separator = item.separator,
            })
        else
            table.insert(menu, {
                text = item.if_empty_menu_title or _("This section is empty"),
                enabled = false,
            })
        end
    end

    -- Add each of CssTweaks' top-level items as a sub-menu
    for _, item in ipairs(CssTweaks) do
        addTweakMenuItem(self.tweaks_table, item)
    end

    -- Users can put their own style tweaks as individual .css files into
    -- koreader/styletweaks/ directory. These can be organized into
    -- sub-directories that will show up as sub-menus.
    local user_styletweaks_dir = DataStorage:getDataDir() .. "/styletweaks"
    local user_tweaks_table = { title = _("User style tweaks") }

    -- Build a tweak definition table from the content of a directory
    local process_tweaks_dir
    process_tweaks_dir = function(dir, item_table, if_empty_menu_title)
        local file_list = {}
        local dir_list = {}
        if lfs.attributes(dir, "mode") == "directory" then
            for f in lfs.dir(dir) do
                if f ~= "." and f ~= ".."  then
                    local mode = lfs.attributes(dir.."/"..f, "mode")
                    if mode == "directory" then
                        table.insert(dir_list, f)
                    elseif mode == "file" and string.match(f, "%.css$") then
                        table.insert(file_list, f)
                    end
                end
            end
        end
        table.sort(dir_list)
        table.sort(file_list)
        for __, subdir in ipairs(dir_list) do
            local sub_item_table = { title = subdir:gsub("_", " ") }
            process_tweaks_dir(dir.."/"..subdir, sub_item_table)
            table.insert(item_table, sub_item_table)
        end
        for __, file in ipairs(file_list) do
            local title = file:gsub("%.css$", ""):gsub("_", " ")
            local filepath = dir.."/"..file
            table.insert(item_table, {
                title = title,
                id = file, -- keep ".css" in id, to distinguish between koreader/user tweaks
                description = T(_("User style tweak at %1"), BD.filepath(filepath)),
                priority = 10, -- give user tweaks a higher priority
                css_path = filepath,
            })
        end
        if #item_table == 0 then
            table.insert(item_table, {
                if_empty_menu_title = if_empty_menu_title or _("No CSS tweak found in this directory"),
            })
        end
    end
    local if_empty_menu_title = _("Add your own tweaks in koreader/styletweaks/")
    process_tweaks_dir(user_styletweaks_dir, user_tweaks_table, if_empty_menu_title)
    self.tweaks_table[#self.tweaks_table].separator = true
    addTweakMenuItem(self.tweaks_table, user_tweaks_table, 6)
                                            -- limit to 6 user tweaks per page

    -- Book-specific editable tweak
    self.tweaks_table[#self.tweaks_table].separator = true
    local book_tweak_item = {
        text_func = function()
            if self.book_style_tweak then
                return _("Book-specific tweak (hold to edit)")
            else
                return _("Book-specific tweak")
            end
        end,
        enabled_func = function() return self.enabled end,
        checked_func = function() return self.book_style_tweak_enabled end,
        callback = function(touchmenu_instance)
            if self.book_style_tweak then
                -- There is a tweak: toggle it on tap, like other tweaks
                self.book_style_tweak_enabled = not self.book_style_tweak_enabled
                self:updateCssText(true) -- apply it immediately
            else
                -- No tweak defined: launch editor
                self:editBookTweak(touchmenu_instance)
            end
        end,
        hold_callback = function(touchmenu_instance)
            self:editBookTweak(touchmenu_instance)
        end,
    }
    table.insert(self.tweaks_table, book_tweak_item)

    self.ui.menu:registerToMainMenu(self)
end

function ReaderStyleTweak:addToMainMenu(menu_items)
    -- insert table to main reader menu
    menu_items.style_tweaks = {
        text_func = function()
            if self.enabled and self.nb_enabled_tweaks > 0 then
                return T(_("Style tweaks (%1)"), self.nb_enabled_tweaks)
            else
                return _("Style tweaks")
            end
        end,
        sub_item_table = self.tweaks_table,
    }
end

local BOOK_TWEAK_SAMPLE_CSS = [[
p.someTitleClassName { text-indent: 0; }

DIV.advertisement { display: none !important; }

.footnoteContainerClassName {
    font-size: 0.8rem !important;
    text-align: justify !important;
    margin: 0 !important;
    -cr-hint: footnote-inpage;
}
]]

local BOOK_TWEAK_INPUT_HINT = T([[
/* %1 */

%2]], _("You can add CSS snippets which will be applied only to this book."), BOOK_TWEAK_SAMPLE_CSS)

function ReaderStyleTweak:editBookTweak(touchmenu_instance)
    local InputDialog = require("ui/widget/inputdialog")
    local editor -- our InputDialog instance
    local tweak_button_id = "editBookTweakButton"
    -- We add a button on the left, which can have 3 states/labels:
    local BUTTON_USE_SAMPLE = _("Use sample")
    local BUTTON_PRETTIFY = _("Prettify")
    local BUTTON_CONDENSE = _("Condense")
    -- Initial button state differs whether we already have some CSS content
    local tweak_button_state = self.book_style_tweak and BUTTON_PRETTIFY or BUTTON_USE_SAMPLE
    local toggle_tweak_button = function(state)
        if state then -- use provided state
            tweak_button_state = state
        else -- natural toggling
            if tweak_button_state == BUTTON_USE_SAMPLE then
                tweak_button_state = BUTTON_PRETTIFY
            elseif tweak_button_state == BUTTON_PRETTIFY then
                tweak_button_state = BUTTON_CONDENSE
            elseif tweak_button_state == BUTTON_CONDENSE then
                tweak_button_state = BUTTON_PRETTIFY
            end
        end
        local tweak_button = editor.button_table:getButtonById(tweak_button_id)
        tweak_button:init()
        editor:refreshButtons()
    end
    -- The Save and Close buttons default behaviour, how they trigger
    -- the callbacks and how they show or not a notification, is not
    -- the most convenient here. We try to tweak that a bit.
    local SAVE_BUTTON_LABEL
    if self.book_style_tweak_enabled or not self.book_style_tweak then
        SAVE_BUTTON_LABEL = _("Apply")
    else
        SAVE_BUTTON_LABEL = _("Save")
    end
    -- This message might be shown by multiple notifications at the
    -- same time: having it similar will make that unnoticed.
    local NOT_MODIFIED_MSG = _("Book tweak not modified.")
    editor = InputDialog:new{
        title =  _("Edit book-specific style tweak"),
        input = self.book_style_tweak or "",
        input_hint = BOOK_TWEAK_INPUT_HINT,
        input_face = Font:getFace("infont", 16), -- same as in TweakInfoWidget
        para_direction_rtl = false,
        lang = "en",
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = {{
            -- First button on first row (row will be completed with Reset|Save|Close)
            {
                id = tweak_button_id,
                text_func = function()
                    return tweak_button_state -- usable as a label
                end,
                callback = function()
                    if tweak_button_state == BUTTON_USE_SAMPLE then
                        editor:setInputText(BOOK_TWEAK_SAMPLE_CSS, true)
                        -- will have edited_callback() called, which will do toggle_tweak_button()
                    else
                        local css_text = editor:getInputText()
                        css_text = util.prettifyCSS(css_text, tweak_button_state == BUTTON_CONDENSE)
                        editor:setInputText(css_text, true)
                        toggle_tweak_button()
                    end
                end,
            },
        }},
        edited_callback = function()
            if not editor then
                -- We might be called while the InputDialog is being
                -- initialized (so not yet assigned to 'editor')
                return
            end
            if #editor:getInputText() == 0 then
                -- No content: show "Use sample"
                if tweak_button_state ~= BUTTON_USE_SAMPLE then
                    toggle_tweak_button(BUTTON_USE_SAMPLE)
                end
            else
                -- Some content: get rid of "Use sample" to not risk
                -- overriding content
                if tweak_button_state == BUTTON_USE_SAMPLE then
                    toggle_tweak_button()
                end
            end
        end,
        -- Set/save view and cursor position callback
        view_pos_callback = function(top_line_num, charpos)
            -- This same callback is called with no argument to get initial position,
            -- and with arguments to give back final position when closed.
            if top_line_num and charpos then
                self.book_style_tweak_last_edit_pos = {top_line_num, charpos}
            else
                local prev_pos = self.book_style_tweak_last_edit_pos
                if type(prev_pos) == "table" and prev_pos[1] and prev_pos[2] then
                    return prev_pos[1], prev_pos[2]
                end
                return nil, nil -- no previous position known
            end
        end,
        reset_button_text = _("Restore"),
        reset_callback = function(content) -- Will add a Reset button
            return self.book_style_tweak or "", _("Book tweak restored")
        end,
        save_button_text = SAVE_BUTTON_LABEL,
        close_save_button_text = SAVE_BUTTON_LABEL,
        save_callback = function(content, closing) -- Will add Save/Close buttons
            if content and content == "" then
                content = nil -- we store nil when empty
            end
            local was_empty = self.book_style_tweak == nil
            local is_empty = content == nil
            local tweak_updated = content ~= self.book_style_tweak
            local should_apply = false
            local msg -- returned and shown as a notification by InputDialog
            if was_empty and not is_empty then
                -- Tweak was empty, and so just created: enable book tweak
                -- so it's immediately applied, and checked in the menu
                self.book_style_tweak_enabled = true
                should_apply = true
                msg = _("Book tweak created, applying…")
            elseif is_empty then
                if not was_empty and self.book_style_tweak_enabled then
                    -- Tweak was enabled, but has been emptied: make it
                    -- disabled in the menu, but apply CSS without it
                    should_apply = true
                    msg = _("Book tweak removed, rendering…")
                else
                    msg = _("Book tweak emptied and removed.")
                end
                self.book_style_tweak_enabled = false
            elseif tweak_updated then
                if self.book_style_tweak_enabled then
                    should_apply = true
                    msg = _("Book tweak updated, applying…")
                else
                    msg = _("Book tweak saved (not enabled).")
                end
            else
                msg = NOT_MODIFIED_MSG
            end
            self.book_style_tweak = content
            -- We always close the editor when this callback is called.
            -- If closing=true, InputDialog will call close_callback().
            -- If not, let's do it ourselves.
            if not closing then
                UIManager:close(editor)
            end
            if should_apply then
                -- Let menu be closed and previous page be refreshed,
                -- so one can see how the text is changed by the tweak.
                touchmenu_instance:closeMenu()
                UIManager:scheduleIn(0.2, function()
                    self:updateCssText(true) -- have it applied
                end)
            else
                touchmenu_instance:updateItems()
            end
            editor.save_callback_called = true
            return true, msg
        end,
        close_callback = function()
            -- save_callback() will always have shown some notification,
            -- so don't add another one
            if not editor.save_callback_called then
                UIManager:show(Notification:new{
                    text = NOT_MODIFIED_MSG,
                    timeout = 2,
                })
                -- This has to be the same message above and below: when
                -- discarding, we can't prevent these 2 notifications from
                -- being shown: having them identical will hide that.
            end
        end,
        close_discarded_notif_text = NOT_MODIFIED_MSG;

    }
    UIManager:show(editor)
    editor:onShowKeyboard(true)
        -- ignore first hold release, as we may be invoked from hold
end

return ReaderStyleTweak
