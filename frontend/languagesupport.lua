--[[--
Language-specific handling module.

This module defines a somewhat generic system by which language-specific
plugins can improve KoReader's support for languages that are not close enough
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

local logger = require("logger")
local UIManager = require("ui/uimanager")

local LanguageSupport = {
    plugins = {},
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
            get_prev_char(pos: XPointer) -> XPointer,
            -- Equivalent to document:getNextVisibleChar(pos).
            get_next_char(pos: XPointer) -> XPointer,
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
]]
function LanguageSupport:registerPlugin(plugin)
    assert(plugin.name ~= "" and plugin.name ~= nil)
    logger.dbg("language support: registering", plugin.name, "plugin")
    if self.plugins[plugin.name] ~= nil then
        -- TODO: Figure out how to deal with the fact that plugins are reloaded
        --       each time the UI changes. It's not awful that we re-register
        --       the plugin each time, but it feels like there should be a
        --       nicer solution.
        logger.dbg("language support: overriding existing", language_code, "plugin")
    end
    self.plugins[plugin.name] = plugin
    return true
end

local function callPlugin(plugin, handler_name, ...)
    local handler = plugin["on"..handler_name]
    if handler == nil then
        logger.dbg("langauge plugin", plugin, "missing handler", handler)
        return
    end
    -- Handler could return any number of values, collect them all.
    ret = {pcall(handler, plugin, ...)}
    ok = ret[1]
    table.remove(ret, 1)
    if not ok then
        logger.err("language plugin", plugin, "crashed during", handler_name, "handler:", unpack(ret))
        return
    end
    logger.dbg("langauge plugin", handler_name, "returned", ret)
    return ret
end

function LanguageSupport:findAndCallPlugin(language_code, handler_name, ...)
    -- First try any plugin that supports the language code specified.
    for name, plugin in pairs(self.plugins) do
        if plugin:supportsLanguage(language_code) then
            logger.dbg("language support: trying", name, "plugin's", handler_name)
            ret = callPlugin(plugin, handler_name, ...)
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
            ret = callPlugin(plugin, handler_name, ...)
            if ret ~= nil then
                return unpack(ret)
            end
        end
    end
end

-- TODO TODO: Copied from readerhighlight. Move to util.
local function cleanupSelectedText(text)
    -- Trim spaces and new lines at start and end
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    -- Trim spaces around newlines
    text = text:gsub("%s*\n%s*", "\n")
    -- Trim consecutive spaces (that would probably have collapsed
    -- in rendered CreDocuments)
    text = text:gsub("%s%s+", " ")
    return text
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
        get_prev_char = function(pos) return document:getPrevVisibleChar(pos) end,
        get_next_char = function(pos) return document:getNextVisibleChar(pos) end,
        get_text_in_range = function(pos0, pos1) return document:getTextFromXPointers(pos0, pos1) end,
    }
end

-- Called from ReaderHighlight:onHold after the document-specific handler has
-- successfully grabbed a "word" from the document.
function LanguageSupport:expandWordSelection(highlight)
    local document = highlight.ui.document
    local selection = highlight.selected_text

    language_code = document and document:getProps().language or "UNKNOWN"
    logger.dbg("language support expanding", language_code, "selection", selection)

    -- Rather than requiring each language plugin to use document: methods
    -- correctly, return a set of callbacks that are document-agnostic (and
    -- close over the document handle) and could be used for non-EPUB formats
    -- in the future.
    callbacks = createDocumentCallbacks(document)
    if not callbacks then
        return
    end

    local new_pos0, new_pos1 = unpack(self:findAndCallPlugin(
        language_code, "WordSelection",
        { pos0 = selection.pos0, pos1 = selection.pos1, callbacks = callbacks }
    ) or {})
    -- If no plugin could expand the selection (or after "expansion" the
    -- selection is the same) then we can safely skip all of the subsequent
    -- re-selection work.
    if not new_pos0 or not new_pos1 or
        (new_pos0 == selection.pos0 and new_pos1 == selection.pos1) then
        logger.dbg("no language plugin could expand the selection")
        return
    end
    logger.dbg("expanding selection\n",
        selection.pos0, ":", selection.pos1, "to\n", new_pos0, ":", new_pos1)

    -- We want to use native crengine text selection here, but we cannot use
    -- getTextFromPositions because the conversion to and from screen
    -- co-ordinates leads to issues with text selection of <ruby> text. In
    -- addition, using getTextFromXPointers means we can select text not on the
    -- screen. But this means we need to manually create the text
    -- selection object returned by getTextFromPositions.
    local new_text = document:getTextFromXPointers(new_pos0, new_pos1, true)
    if not new_text then
        logger.dbg("no text found in selection", new_pos0, ":", new_pos1)
        return
    end

    highlight.selected_text = {
        text = cleanupSelectedText(new_text),
        pos0 = new_pos0,
        pos1 = new_pos1,
        sboxes = document:getScreenBoxesFromPositions(new_pos0, new_pos1, true),
    }
end

-- Called from ReaderHighlight:startSdcv after the selected has text has been
-- OCR'd, cleaned, and otherwise made ready for sdcv.
function LanguageSupport:dictionaryFormCandidates(document, text)
    language_code = document and document:getProps().language or "UNKNOWN"
    logger.dbg("language support: convert", text, "to dictionary form (marked as", language_code..")")

    return self:findAndCallPlugin(
        language_code, "WordLookup",
        { text = text }
    )
end

function LanguageSupport:addToMainMenu(menu_items)
    -- TODO TODO: Still not sure how the menu system should work.
    sub_table = {}
    for language_code, plugin in pairs(self.plugin) do
        menu_name = plugin.name or language_code
        if plugin.addToSubMenu ~= nil then
            -- The plugin wants to create a special sub-menu
        else
        end
    end
    menu_items.language_support = {
        text = _("Language Support"),
        callback = function()
            logger.dbg("tapped language support")
        end,
        sub_item_table = sub_table,
    }
end

return LanguageSupport
