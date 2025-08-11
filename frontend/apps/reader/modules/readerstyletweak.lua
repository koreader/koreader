local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CssTweaks = require("ui/data/css_tweaks")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local T = require("ffi/util").template

-- Simple widget for showing tweak info
local TweakInfoWidget = InputContainer:extend{
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
    self:registerKeyEvents()

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
            {
                text = self.is_tweak_in_dispatcher and _("Don't show in action list") or _("Show in action list"),
                callback = function()
                    self.toggle_tweak_in_dispatcher_callback()
                    UIManager:close(self)
                end,
            },
        },
        {
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
        },
    }

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    self.movable = MovableContainer:new{
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            radius = Size.radius.window,
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

function TweakInfoWidget:registerKeyEvents()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

TweakInfoWidget.onPhysicalKeyboardConnected = TweakInfoWidget.registerKeyEvents

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

-- Ordering function for tweaks when appended to css_test.
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
local ReaderStyleTweak = WidgetContainer:extend{
    tweaks_by_id = nil,
    tweaks_table = nil, -- sub-menu items
    nb_enabled_tweaks = 0, -- for use by main menu item
    css_text = nil, -- aggregated css text from tweaks individual css snippets
    enabled = true, -- allows for toggling between selected tweaks / none
    dispatcher_prefix_set = "style_tweak_set_",
    dispatcher_prefix_toggle = "style_tweak_",
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

function ReaderStyleTweak:resolveConflictsBeforeEnabling(id, conflicts_with)
    -- conflicts_with may be a string, an array or hash table of ids, or a function:
    -- make it a function for us here
    local conflicts_with_type = type(conflicts_with)
    local conflicts_with_func
    if conflicts_with_type == "function" then
        conflicts_with_func = conflicts_with
    elseif conflicts_with_type == "string" then
        conflicts_with_func = function(otid) return otid == conflicts_with end
    elseif conflicts_with_type == "table" then
        conflicts_with_func = function(otid) return conflicts_with[otid] ~= nil or util.arrayContains(conflicts_with, otid) end
    else
        conflicts_with_func = function(otid) return false end
    end
    local to_remove = {}
    for other_id, other_enabled in pairs(self.doc_tweaks) do
        -- We also reset the provided "id" for a complete cleanup,
        -- it is expected the caller will re-enable it
        if other_enabled and (other_id == id or conflicts_with_func(other_id)) then
            table.insert(to_remove, other_id)
        end
    end
    for _, other_id in ipairs(to_remove) do
        self.doc_tweaks[other_id] = nil
    end
    -- global_tweaks may also contain some conflicting ids: we need to make them false
    -- in doc_tweaks to have them disabled (but we keep them in global_tweaks)
    local to_make_false = {}
    for other_id, other_enabled in pairs(self.global_tweaks) do
        -- (We shouldn't be called if the provided "id" is already enabled
        -- in global_tweaks. So we don't check for that here.)
        if other_enabled and conflicts_with_func(other_id) then
            table.insert(to_make_false, other_id)
        end
    end
    for _, other_id in ipairs(to_make_false) do
        self.doc_tweaks[other_id] = false
    end
end

function ReaderStyleTweak:resolveConflictsBeforeMakingDefault(id, conflicts_with)
    local conflicts_with_type = type(conflicts_with)
    local conflicts_with_func
    if conflicts_with_type == "function" then
        conflicts_with_func = conflicts_with
    elseif conflicts_with_type == "string" then
        conflicts_with_func = function(otid) return otid == conflicts_with end
    elseif conflicts_with_type == "table" then
        conflicts_with_func = function(otid) return conflicts_with[otid] ~= nil or util.arrayContains(conflicts_with, otid) end
    else
        conflicts_with_func = function(otid) return false end
    end
    local to_remove = {}
    for other_id, other_enabled in pairs(self.global_tweaks) do
        -- We also reset the provided "id" for a complete cleanup,
        -- it is expected the caller will re-enable it
        if other_id == id or conflicts_with_func(other_id) then
            table.insert(to_remove, other_id)
        end
    end
    for _, other_id in ipairs(to_remove) do
        self.global_tweaks[other_id] = nil
    end
    -- Also remove the provided "id" and any conflicting one from doc_tweaks (where
    -- they may be false and prevent this new default to apply to current book)
    to_remove = {}
    for other_id, other_enabled in pairs(self.doc_tweaks) do
        if other_id == id or conflicts_with_func(other_id) then
            table.insert(to_remove, other_id)
        end
    end
    for _, other_id in ipairs(to_remove) do
        self.doc_tweaks[other_id] = nil
    end
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
                -- without having to restart KOReader
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
    self.enabled = config:nilOrTrue("style_tweaks_enabled")
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
        self.ui.doc_settings:makeFalse("style_tweaks_enabled")
    end
    self.ui.doc_settings:saveSetting("style_tweaks", util.tableSize(self.doc_tweaks) > 0 and self.doc_tweaks or nil)
    G_reader_settings:saveSetting("style_tweaks", self.global_tweaks)
    G_reader_settings:saveSetting("style_tweaks_in_dispatcher", self.tweaks_in_dispatcher)
    self.ui.doc_settings:saveSetting("book_style_tweak", self.book_style_tweak)
    self.ui.doc_settings:saveSetting("book_style_tweak_enabled", self.book_style_tweak_enabled)
    self.ui.doc_settings:saveSetting("book_style_tweak_last_edit_pos", self.book_style_tweak_last_edit_pos)
end

local function dispatcherRegisterStyleTweak(tweak_id, tweak_title)
    Dispatcher:registerAction(ReaderStyleTweak.dispatcher_prefix_set..tweak_id,
        {category="string", event="ToggleStyleTweak", arg=tweak_id, title=T(_("Style tweak '%1'"), tweak_title), rolling=true,
            args={true, false}, toggle={_("on"), _("off")}})
    Dispatcher:registerAction(ReaderStyleTweak.dispatcher_prefix_toggle..tweak_id,
        {category="none", event="ToggleStyleTweak", arg=tweak_id, title=T(_("Style tweak '%1' toggle"), tweak_title), rolling=true})
end

function ReaderStyleTweak:init()
    self.tweaks_in_dispatcher = G_reader_settings:readSetting("style_tweaks_in_dispatcher") or {}
    self.tweaks_by_id = {}
    self.tweaks_table = {}

    -- Add first item of sub-menu, that allows toggling between
    -- enabled tweaks / none (without the need to disable each of
    -- them)
    table.insert(self.tweaks_table, {
        text = _("Enable style tweaks (long-press for help)"),
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
                text_func = function()
                    local title = item.title or "### undefined tweak title ###"
                    if self.global_tweaks[item.id] then
                        title = title .. "   ★"
                    end
                    if self.tweaks_in_dispatcher[item.id] then
                        title = title .. "   \u{F144}"
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
                                if self.doc_tweaks[item.id] == false then
                                    self.doc_tweaks[item.id] = nil
                                end
                            else
                                if item.conflicts_with and item.global_conflicts_with ~= false then
                                    -- For hold/makeDefault/global_tweaks, the tweak may provide 'global_conflicts_with':
                                    --   if 'false': no conflict checks
                                    --   if nil or 'true', use item.conflicts_with
                                    --   otherwise, use it instead of item.conflicts_with
                                    if item.global_conflicts_with ~= true and item.global_conflicts_with ~= nil then
                                        self:resolveConflictsBeforeMakingDefault(item.id, item.global_conflicts_with)
                                    else
                                        self:resolveConflictsBeforeMakingDefault(item.id, item.conflicts_with)
                                    end
                                    -- Remove all references in doc_tweak
                                    self:resolveConflictsBeforeEnabling(item.id, item.conflicts_with)
                                    self.doc_tweaks[item.id] = nil
                                end
                                self.global_tweaks[item.id] = true
                            end
                            touchmenu_instance:updateItems()
                            self:updateCssText(true) -- apply it immediately
                        end,
                        is_tweak_in_dispatcher = self.tweaks_in_dispatcher[item.id],
                        toggle_tweak_in_dispatcher_callback = function()
                            if self.tweaks_in_dispatcher[item.id] then
                                self.tweaks_in_dispatcher[item.id] = nil
                                Dispatcher:removeAction(self.dispatcher_prefix_toggle..item.id)
                                UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                                    { old_name = self.dispatcher_prefix_toggle..item.id, new_name = nil }))
                                Dispatcher:removeAction(self.dispatcher_prefix_set..item.id)
                                UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged",
                                    { old_name = self.dispatcher_prefix_set..item.id, new_name = nil }))
                            else
                                self.tweaks_in_dispatcher[item.id] = item.title
                                dispatcherRegisterStyleTweak(item.id, item.title)
                            end
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
                callback = function()
                    -- enable/disable only for this book
                    self:onToggleStyleTweak(item.id, item, true) -- no notification
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
                    elseif mode == "file" and string.match(f, "%.css$") and not util.stringStartsWith(f, "._") then
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
                return _("Book-specific tweak (long-press to edit)")
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
    self:onDispatcherRegisterActions()
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

function ReaderStyleTweak:onToggleStyleTweak(tweak_id, item, no_notification)
    local toggle
    if type(tweak_id) == "table" then -- Dispatcher action 'Style tweak set on/off'
        tweak_id, toggle = unpack(tweak_id)
    end
    if self.tweaks_by_id[tweak_id] == nil then return true end
    local enabled, g_enabled = self:isTweakEnabled(tweak_id)
    if enabled == toggle then return true end
    local text
    if enabled then
        if g_enabled then
            -- if globally enabled, mark it as disabled
            -- for this document only
            self.doc_tweaks[tweak_id] = false
        else
            self.doc_tweaks[tweak_id] = nil
        end
        text = T(C_("Style tweak", "Off: %1"), self.tweaks_in_dispatcher[tweak_id])
    else
        local conflicts_with
        if item then
            conflicts_with = item.conflicts_with
        else -- called from Dispatcher
            for _, v in ipairs(CssTweaks) do
                if v.id == tweak_id then
                    conflicts_with = v.conflicts_with
                    break
                end
            end
        end
        if conflicts_with then
            self:resolveConflictsBeforeEnabling(tweak_id, conflicts_with)
        end
        self.doc_tweaks[tweak_id] = true
        text = T(C_("Style tweak", "On: %1"), self.tweaks_in_dispatcher[tweak_id])
    end
    self:updateCssText(true) -- apply it immediately
    if not no_notification then
        UIManager:show(Notification:new{
            text = text,
        })
    end
    return true
end

function ReaderStyleTweak:onDispatcherRegisterActions()
    for tweak_id, tweak_title in pairs(self.tweaks_in_dispatcher) do
        dispatcherRegisterStyleTweak(tweak_id, tweak_title)
    end
end

local BOOK_TWEAK_SAMPLE_CSS = [[
/* Remove indent from some P used as titles */
p.someTitleClassName {
    text-indent: 0;
}
/* Get in-page footnotes when no tweak works */
.footnoteContainerClassName {
    -cr-hint: footnote-inpage;
}
/* Help getting some alternative ToC when no headings */
.someSeparatorClassName {
    -cr-hint: toc-level1;
    break-before: always;
}
/* Hide annoying content */
DIV.someAdvertisement {
    display: none !important;
}
]]

local BOOK_TWEAK_INPUT_HINT = T([[
/* %1 */

%2]], _("You can add CSS snippets which will be applied only to this book."), BOOK_TWEAK_SAMPLE_CSS)

local CSS_SUGGESTIONS = {
    { _("Long-press for info ⓘ"), _([[
This menu provides a non-exhaustive CSS syntax and properties list. It also shows some KOReader-specific, non-standard CSS features that can be useful with e-books.

Most of these bits are already used by our categorized 'Style tweaks' (found in the top menu). Long-press on any style-tweak option to see its code and its expected results. Should these not be enough to achieve your desired look, you may need to adjust them slightly: tap once on the CSS code-box to copy the code to the clipboard, paste it here and edit it.

Long-press on any item in this popup to get more information on what it does and what it can help solving.

Tap on the item to insert it: you can then edit it and combine it with others.]]), true },

    { _("Matching elements"), {
        { "p.className", _([[
p.className matches a <p> with class='className'.

*.className matches any element with class='className'.

p:not([class]) matches a <p> without any class= attribute.]])},
        { "aside > p", _([[
aside > p matches a <p> children of an <aside> element.

aside p (without any intermediate symbol) matches a <p> descendant of an <aside> element.]])},
        { "p + img", _([[
p + img matches a <img> if its immediate previous sibling is a <p>.

p ~ img matches a <img> if any of its previous siblings is a <p>.]])},

        { "p[name='what']", _([[
[name="what"] matches if the element has the attribute 'name' and its value is exactly 'what'.

[name] matches if the attribute 'name' is present.

[name~="what"] matches if the value of the attribute 'name' contains 'what' as a word (among other words separated by spaces).]])},

        { "p[name*='what' i]", _([[
[name*="what" i] matches any element having the attribute 'name' with a value that contains 'what', case insensitive.

[name^="what"] matches if the attribute value starts with 'what'.

[name$="what"] matches if the attribute value ends with 'what'.]])},

        { "p[_='what']", _([[
Similar in syntax to attribute matching, but matches the inner text of an element.

p[_="what"] matches any <p> whose text is exactly 'what'.

p[_] matches any non-empty <p>.

p:not([_]) matches any empty <p>.

p[_~="what"] matches any <p> that contains the word 'what'.]])},

        { "p[_*='what' i]", _([[
Similar in syntax to attribute matching, but matches the inner text of an element.

p[_*="what" i] matches any <p> that contains 'what', case insensitive.

p[_^="what"] matches any <p> whose text starts with 'what'.
(This can be used to match "Act" or "Scene", or character names in plays, and make them stand out.)

p[_$="what"] matches any <p> whose text ends with 'what'.]])},

        { "p:first-child", _([[
p:first-child matches a <p> that is the first child of its parent.

p:last-child matches a <p> that is the last child of its parent.

p:nth-child(odd) matches any other <p> in a series of sibling <p>.]])},

        { "Tip: use View HTML ⓘ", _([[
On a book page, select some text spanning around (before and after) the element you are interested in, and use 'View HTML'.
In the HTML viewer, long press on tags or text to get a list of selectors matching the element: tap on one of them to copy it to the clipboard.
You can then paste it here with long-press in the text box.]]), true},

    }},

    { _("Common classic properties"), {
        { "font-size: 1rem !important;", _("1rem will enforce your main font size.")},
        { "font-weight: normal !important;", _("Remove bold. Use 'bold' to get bold.")},
        { "hyphens: none !important;", _("Disables hyphenation inside the targeted elements.")},
        { "text-indent: 1.2em !important;", _("1.2em is our default text indentation.")},
        { "break-before: always !important;", _("Start a new page with this element. Use 'avoid' to avoid a new page.")},
        { "color: black !important;", _("Force text to be black.")},
        { "background: transparent !important;", _("Remove any background color.")},
        { "max-width: 50vw !important;", _("Limit an element width to 50% of your screen width (use 'max-height: 50vh' for 50% of the screen height). Can be useful with <img> to limit their size.")},
    }},

    { _("Private CSS properties"), {
        { "-cr-hint: footnote-inpage;", _("When set on a block element containing the target id of a href, this block element will be shown as an in-page footnote.")},
        { "-cr-hint: extend-footnote-inpage;", _("When set on a block element following a block element marked `footnote-inpage`, this block will be shown as part of the same in-page footnote as the previous element. Can be chained across multiple elements following an in-page footnote.")},
        { "-cr-hint: non-linear;", _("Can be set on some specific DocFragments (e.g. DocFragment[id$=_16]) to ignore them in the linear pages flow.")},
        { "-cr-hint: non-linear-combining;", _("Can be set on contiguous footnote blocks to ignore them in the linear pages flow.")},
        { "-cr-hint: toc-level1;", _("When set on an element, its text can be used to build the alternative table of contents. toc-level2 to toc-level6 can be used for nested chapters.")},
        { "-cr-hint: toc-ignore;", _("When set on an element, it will be ignored when building the alternative table of contents.")},
        { "-cr-hint: footnote;", _("Can be set on target of links (<div id='..'>) to have their link trigger as footnote popup, in case KOReader wrongly detect this target is not a footnote.")},
        { "-cr-hint: noteref;", _("Can be set on links (<a href='#..'>) to have them trigger as footnote popups, in case KOReader wrongly detect the links is not to a footnote.")},
        { "-cr-hint: noteref-ignore;", _([[
Can be set on links (<a href='#..'>) to have them NOT trigger footnote popups and in-page footnotes.
If some DocFragment presents an index of names with cross references, resulting in in-page footnotes taking half of these pages, you can avoid this with:
DocFragment[id$=_16] a { -cr-hint: noteref-ignore }]])},
    }},

    { _("Useful 'content:' values"), {
        { _("Caution ⚠"), _([[
Be careful with these: stick them to a proper discriminating selector, like:

span.specificClassName

p[_*="keyword" i]

If used as-is, they will act on ALL elements!]]), true},
        { "::before {content: ' '}", _("Insert a visible space before an element.")},
        { "::before {content: '\\A0 '}", _("Insert a visible non-breakable space before an element, so it sticks to what's before.")},
        { "::before {content: '\\2060'}", _("U+2060 WORD JOINER may act as a glue (like an invisible non-breakable space) before an element, so it sticks to what's before.")},
        { "::before {content: '\\200B'}", _("U+200B ZERO WIDTH SPACE may allow a linebreak before an element, in case the absence of any space prevents that.")},
        { "::before {content: attr(title)}", _("Insert the value of the attribute 'title' at start of an element content.")},
        { "::before {content: '▶ '}", _("Prepend a visible marker.")},
        { "::before {content: '● '}", _("Prepend a visible marker.")},
        { "::before {content: '█ '}", _("Prepend a visible marker.")},
    }},
}

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
            -- First buttons on first row (row will be completed with Reset|Save|Close)
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
            {
                id = "css_suggestions_button_id",
                text = "CSS \u{2261}",
                callback = function()
                    local suggestions_popup_widget
                    local buttons = {}
                    for _, suggestion in ipairs(CSS_SUGGESTIONS) do
                        local title = suggestion[1]
                        local is_submenu, submenu_items, description
                        if type(suggestion[2]) == "table" then
                            is_submenu = true
                            submenu_items = suggestion[2]
                        else
                            description = suggestion[2]
                        end
                        local is_info_only = suggestion[3]
                        local text
                        if is_submenu then -- add the same arrow we use for top menu submenus
                            text = require("ui/widget/menu").getMenuText({text=title, sub_item_table=true})
                        elseif is_info_only then
                            text = title
                        else
                            text = BD.ltr(title) -- CSS code, keep it LTR
                        end
                        table.insert(buttons, {{
                            text = text,
                            id = title,
                            align = "left",
                            callback = function()
                                if is_info_only then
                                    -- No CSS bit to insert, show description also on tap
                                    UIManager:show(InfoMessage:new{ text = description })
                                    return
                                end
                                if not is_submenu then -- insert as-is on tap
                                    UIManager:close(suggestions_popup_widget)
                                    editor:addTextToInput(title)
                                else
                                    local sub_suggestions_popup_widget
                                    local sub_buttons = {}
                                    for _, sub_suggestion in ipairs(submenu_items) do
                                        -- (No 2nd level submenu needed for now)
                                        local sub_title = sub_suggestion[1]
                                        local sub_description = sub_suggestion[2]
                                        local sub_is_info_only = sub_suggestion[3]
                                        local sub_text = sub_is_info_only and sub_title or BD.ltr(sub_title)
                                        table.insert(sub_buttons, {{
                                            text = sub_text,
                                            align = "left",
                                            callback = function()
                                                if sub_is_info_only then
                                                    UIManager:show(InfoMessage:new{ text = sub_description })
                                                    return
                                                end
                                                UIManager:close(sub_suggestions_popup_widget)
                                                UIManager:close(suggestions_popup_widget)
                                                editor:addTextToInput(sub_title)
                                            end,
                                            hold_callback = sub_description and function()
                                                UIManager:show(InfoMessage:new{ text = sub_description })
                                            end,
                                        }})
                                    end
                                    local anchor_func = function()
                                        local d = suggestions_popup_widget:getButtonById(title).dimen:copy()
                                        if BD.mirroredUILayout() then
                                            d.x = d.x - d.w + Size.padding.default
                                        else
                                            d.x = d.x + d.w - Size.padding.default
                                        end
                                        -- As we don't know if we will pop up or down, anchor it on the middle of the item
                                        d.y = d.y + math.floor(d.h / 2)
                                        d.h = 1
                                        return d, true
                                    end
                                    sub_suggestions_popup_widget = ButtonDialog:new{
                                        modal = true, -- needed when keyboard is shown
                                        width = math.floor(Screen:getWidth() * 0.9), -- max width, will get smaller
                                        shrink_unneeded_width = true,
                                        buttons = sub_buttons,
                                        anchor = anchor_func,
                                    }
                                    UIManager:show(sub_suggestions_popup_widget)
                                end
                            end,
                            hold_callback = description and function()
                                UIManager:show(InfoMessage:new{ text = description })
                            end or nil
                        }})
                    end
                    suggestions_popup_widget = ButtonDialog:new{
                        modal = true, -- needed when keyboard is shown
                        width = math.floor(Screen:getWidth() * 0.9), -- max width, will get smaller
                        shrink_unneeded_width = true,
                        buttons = buttons,
                        anchor = function()
                            -- we return prefers_pop_down=true so it pops over the keyboard
                            -- instead of the text if it can
                            return editor.button_table:getButtonById("css_suggestions_button_id").dimen, true
                        end,
                    }
                    UIManager:show(suggestions_popup_widget)
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
        -- Store/retrieve view and cursor position callback
        view_pos_callback = function(top_line_num, charpos)
            -- This same callback is called with no arguments on init to retrieve the stored initial position,
            -- and with arguments to store the final position on close.
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
        close_callback = function(close_status)
            -- save_callback() will always have shown some notification,
            -- so don't add another one.
            -- If close_status is false, text was modified but then discarded, and
            -- InputDialog will show our close_discarded_notif_text
            if not editor.save_callback_called and close_status ~= false then
                UIManager:show(Notification:new{
                    text = NOT_MODIFIED_MSG
                })
            end
        end,
        close_discarded_notif_text = NOT_MODIFIED_MSG,
    }
    UIManager:show(editor)
    editor:onShowKeyboard(true)
        -- ignore first hold release, as we may be invoked from hold
end

return ReaderStyleTweak
