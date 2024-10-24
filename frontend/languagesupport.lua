--[[--
Language-specific handling module.

This module defines a somewhat generic system by which language-specific
plugins can improve KOReader's support for languages that are not close enough
to European languages to "just work".

This was originally designed to improve KoReader's Japanese support through the
Japanese plugin (plugins/japanese.koplugin) but it should be generic enough for
other language plugins to build off this framework. Examples of languages which
may require such a plugin include highly inflected/agglutinative languages
(Japanese and Korean) and languages where spaces are not used as a delimiting
character between words (Japanese and Chinese) and languages that use a
character set where KoReader's dependencies define a "word" as being a single
character.

This module works by providing a mechanism to define a series of callbacks (not
unlike UI Events) which are called during operations where language-specific
knowledge may be necessary (such as during text selection and dictionary lookup
of a text fragment).
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dbg = require("dbg")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- Shared among all LanguageSupport instances to make sure we don't lose
-- plugins when reloading different viewers.
local PluginListSingleton = {}

local LanguageSupport = WidgetContainer:extend{
    name = "language_support",
    plugins = PluginListSingleton,
}

--[[--
Registers a new language-specific plugin with given language_code.

If a plugin using the same language code already exists, the loading is
skipped. The language code is used to prioritise which language plugin should
be called first (if that plugin fails to handle the text, there is no such
plugin, or the document has no language defined then all of the plugins are
called one-by-one until one succeeds).

The follow handlers are defined (if you wish to support the handler create the
corresponding onHandler method):

 - WordSelection (onWordSelection) is called when a highlight is
   first created and can be used to modify the default "word boundary" word
   selection to match user expectations.

   Note that "XPointer" is used here but code written should take it as an
   opaque object and only use the given callbacks since in future this feature
   may work with PDFs and all of the XPointers will instead be PDF equivalents.

   Called with {
        pos0 = [XPointer], pos1 = [XPointer],
        callbacks = {
            -- Equivalent to document:getPrevVisibleChar(pos).
            get_prev_char_pos(pos: XPointer) -> XPointer,
            -- Equivalent to document:getNextVisibleChar(pos).
            get_next_char_pos(pos: XPointer) -> XPointer,
            -- Equivalent to document:getTextFromXPointers(pos0, pos1).
            get_text_in_range(pos0: XPointer, pos1: XPointer) -> string,
        }
   } table as the only argument.

   Must return the new (pos0, pos1) XPointers or nil if the word couldn't be
   expanded.

 - WordLookup (onWordLookup) is called when a dictionary lookup is triggered on
   some text and can be used to adjust the word such that it is in the
   dictionary form and can be found in the dictionary. This is primarily useful
   for languages where StarDict "fuzzy searching" is not usable.

   Called with
     { text = [string] }
   table as the only argument.

   Must return an array of candidate words (in decreasing order of preference)
   which will be looked up or nil if no candidate words could be generated.
   Note that if more than one candidate is found in the dictionary they will
   all be displayed to the user. It is not necessary to include the original
   word in the candidate list -- it will always be given highest priority.

@param Plugin to register (plugin.name is used as the internal name and must not be nil or "").
@treturn bool Whether the plugin was successfully registered.
]]
function LanguageSupport:registerPlugin(plugin)
    if not dbg.dassert(plugin.name ~= nil and plugin.name ~= "", "plugin name must be non-empty") then
        logger.warn("language support: ignoring attempted registration of plugin with empty name")
        return false
    end
    if self.plugins[plugin.name] ~= nil then
        logger.dbg("language support: overriding existing", plugin.name, "plugin")
    else
        logger.dbg("language support: registering", plugin.name, "plugin")
    end
    self.plugins[plugin.name] = plugin
    return true
end

--- Returns whether there are any language plugins currently enabled.
-- @treturn bool whether there are any registered plugins
function LanguageSupport:hasActiveLanguagePlugins()
    return next(self.plugins) ~= nil
end

local function callPlugin(plugin, handler_name, ...)
    local handler = plugin["on"..handler_name]
    if handler == nil then
        logger.dbg("language plugin", plugin, "missing handler", handler)
        return
    end
    -- Handler could return any number of values, collect them all.
    local ret = {pcall(handler, plugin, ...)}
    local ok = table.remove(ret, 1)
    if not ok then
        logger.err("language plugin", plugin, "crashed during", handler_name, "handler:", unpack(ret))
        return
    end
    logger.dbg("language plugin", handler_name, "returned", ret)
    return ret
end

function LanguageSupport:_findAndCallPlugin(language_code, handler_name, ...)
    -- First try any plugin that supports the language code specified.
    for name, plugin in pairs(self.plugins) do
        if plugin:supportsLanguage(language_code) then
            logger.dbg("language support: trying", name, "plugin's", handler_name)
            local ret = callPlugin(plugin, handler_name, ...)
            if ret ~= nil then
                return unpack(ret)
            end
        end
    end

    -- Fallback path. Try every remaining plugin in case the document had the
    -- wrong language defined (or no language defined) or had the correct
    -- language defined but contained text not in the document language.
    for name, plugin in pairs(self.plugins) do
        if not plugin:supportsLanguage(language_code) then
            logger.dbg("language support (fallback): trying", name, "plugin's", handler_name)
            local ret = callPlugin(plugin, handler_name, ...)
            if ret ~= nil then
                return unpack(ret)
            end
        end
    end
end

local function createDocumentCallbacks(document)
    if not document or document.info.has_pages then
        -- We need document:get{Prev,Next}VisibleChar at a minimum and there
        -- isn't an alternative for PDFs at the moment (not to mention for
        -- quite a few CJK PDFs, MuPDF seems to be unable to create selections
        -- at a character level even using hold-and-pan).
        logger.dbg("language support currently cannot expand document selections in non-EPUB formats")
        return
    end
    return {
        get_prev_char_pos = function(pos) return document:getPrevVisibleChar(pos) end,
        get_next_char_pos = function(pos) return document:getNextVisibleChar(pos) end,
        get_text_in_range = function(pos0, pos1) return document:getTextFromXPointers(pos0, pos1) end,
    }
end

--- Called from ReaderHighlight:onHold after the document-specific handler has
-- successfully grabbed a "word" from the document. If the selection is to
-- updated, improveWordSelection will also update the document's internal
-- selection state (for crengine) to correctly display the right selection.
-- @param selection Text selection table to improve if possible.
-- @return New updated selected_text table which should be used (or nil).
function LanguageSupport:improveWordSelection(selection)
    if not self:hasActiveLanguagePlugins() then return end -- nothing to do

    if not self.document then
        logger.dbg("language support: cannot improve word selection outside document")
        return
    end

    local language_code = self.ui.doc_props.language or "unknown"
    logger.dbg("language support: improving", language_code, "selection", selection)

    -- Rather than requiring each language plugin to use document: methods
    -- correctly, return a set of callbacks that are document-agnostic (and
    -- have the document handle as an upvalue of the closure) and could be used
    -- for non-EPUB formats in the future.
    local callbacks = createDocumentCallbacks(self.document)
    if not callbacks then
        return
    end

    local new_pos0, new_pos1 = unpack(self:_findAndCallPlugin(
        language_code, "WordSelection",
        { text = selection.text, pos0 = selection.pos0, pos1 = selection.pos1, callbacks = callbacks }
    ) or {})
    -- If no plugin could update the selection (or after "expansion" the
    -- selection is the same) then we can safely skip all of the subsequent
    -- re-selection work.
    if not new_pos0 or not new_pos1 or
        (new_pos0 == selection.pos0 and new_pos1 == selection.pos1) then
        logger.dbg("language support: no plugin could improve the selection")
        return
    end
    logger.dbg("language support: updating selection\nfrom",
        selection.pos0, ":", selection.pos1, "\nto", new_pos0, ":", new_pos1)

    -- We want to use native crengine text selection here, but we cannot use
    -- getTextFromPositions because the conversion to and from screen
    -- coordinates leads to issues with text selection of <ruby> text. In
    -- addition, using getTextFromXPointers means we can select text not on the
    -- screen. But this means we need to manually create the text selection
    -- object returned by getTextFromPositions (though this is not a big deal
    -- because we'd have to generate the sboxes anyway).
    local new_text = self.document:getTextFromXPointers(new_pos0, new_pos1, true)
    if not new_text then
        -- This really shouldn't happen since we started with some text.
        logger.warn("language support: no text found in selection", new_pos0, ":", new_pos1)
        return
    end

    return {
        text = util.cleanupSelectedText(new_text),
        pos0 = new_pos0,
        pos1 = new_pos1,
        sboxes = self.document:getScreenBoxesFromPositions(new_pos0, new_pos1, true),
    }
end

--- Called from ReaderHighlight:startSdcv after the selected has text has been
-- OCR'd, cleaned, and otherwise made ready for sdcv.
-- @tparam string text Original text being searched by the user.
-- @treturn {string,...} Extra dictionary form candidates to search (or nil).
function LanguageSupport:extraDictionaryFormCandidates(text)
    if not self:hasActiveLanguagePlugins() then return end -- nothing to do

    local language_code = (self.ui.doc_props and self.ui.doc_props.language) or "unknown"
    logger.dbg("language support: convert", text, "to dictionary form (marked as", language_code..")")

    return self:_findAndCallPlugin(
        language_code, "WordLookup",
        { text = text }
    )
end

function LanguageSupport:addToMainMenu(menu_items)
    if not self:hasActiveLanguagePlugins() then return end -- nothing to do

    -- Sort the plugin keys so we have consistent ordering in the menu.
    local plugin_names = {}
    for name in pairs(self.plugins) do
        table.insert(plugin_names, name)
    end
    table.sort(plugin_names)

    -- Link up each plugin's submenu.
    local sub_table = {}
    for _, name in ipairs(plugin_names) do
        local plugin = self.plugins[name]
        if plugin.genMenuItem ~= nil then
            local menuItem = plugin:genMenuItem()
            -- Set help_text in case the plugin hasn't.
            if not menuItem.help_text and not menuItem.help_text_func then
                menuItem.help_text = plugin.description
            end
            table.insert(sub_table, menuItem)
        else
            -- Plugin didn't have a menu defined so use a basic fallback menu,
            -- showing a description of the plugin when held for help.
            table.insert(sub_table, {
                text = plugin.pretty_name or plugin.fullname or name,
                help_text = plugin.description,
                keep_menu_open = true
            })
        end
    end

    -- Only show the menu item if there are some plugins enabled.
    if #sub_table ~= 0 then
        menu_items.language_support = {
            text = _("Language support plugins"),
            sorting_hint = "document",
            help_text = _([[
This menu lets you manage KOReader's language support plugins and their associated settings.

These plugins provide language-specific helpers to KOReader, to improve the reading experience with languages that require some extra handling when compared to most European languages.

In order to disable a language plugin, you need to disable it from the Plugin Management menu.]]),
            sub_item_table = sub_table,
        }
    end
end

function LanguageSupport:init()
    self.document = self.document or self.ui and self.ui.document
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

return LanguageSupport
