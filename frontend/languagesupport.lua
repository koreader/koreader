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

   Called with { [highlight] = Highlight } table as the only argument.

   Must return the new (pos0, pos1) XPointers or nil if the word couldn't be
   expanded.

 - WordLookup (onWordLookup) is called when a dictionary lookup is triggered on
   some text and can be used to adjust the word such that it is in the
   dictionary form and can be found in the dictionary. This is primarily useful
   for languages where StarDict "fuzzy searching" is not usable.

   Called with
     { [document] = document, [text] = string }
   table as the only argument.

   Must return an array of candidate words (in decreasing order of preference)
   which will be looked up or nil if no candidate words could be generated.
   Note that if more than one candidate is found in the dictionary they will
   all be displayed to the user. It is not necessary to include the original
   word in the candidate list -- it will always be given highest priority.
]]
-- TODO: I guess plugins should actually be registering themselves without a
--       specific language code since one plugin could theoretically handle
--       multiple languages, and also there might be multiple possible language
--       codes for a single language.
function LanguageSupport:registerPlugin(language_code, plugin)
    logger.dbg("language support: registering", language_code, "plugin")
    if self.plugins[language_code] ~= nil then
        -- TODO: Figure out how to deal with the fact that plugins are reloaded
        --       each time the UI changes. It's not awful that we re-register
        --       the plugin each time, but it feels like there should be a
        --       nicer solution.
        logger.dbg("language support: overriding existing", language_code, "plugin")
    end
    self.plugins[language_code] = plugin
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
        -- XXX: Should this be an actual pop-up?
        logger.err("language plugin", plugin, "crashed during", handler_name, "handler:", unpack(ret))
        return
    end
    logger.dbg("langauge plugin", handler_name, "returned", ret)
    return ret
end

function LanguageSupport:findAndCallPlugin(language_code, handler_name, ...)
    best = self.plugins[language_code]
    if best ~= nil then
        logger.dbg("language support: trying", language_code, "plugin's", handler_name)
        ret = callPlugin(best, handler_name, ...)
        if ret ~= nil then
            return unpack(ret)
        end
    end

    -- Fallback path. Try every remaining plugin in case the document had the
    -- wrong language defined (or no language defined) or had the correct
    -- language defined but contained text not in the document language.
    for lang, plugin in pairs(self.plugins) do
        if lang ~= language_code then -- don't retry the first plugin
            logger.dbg("language support: trying", language_code, "plugin's", handler_name)
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

local function xpToPosition(document, xp)
    --local y, x = document:getPosFromXPointer(xp)
    local y, x = document:getScreenPositionFromXPointer(xp)
    return { x = x, y = y }
end

-- Called from ReaderHighlight:onHold after the document-specific handler has
-- successfully grabbed a "word" from the document.
function LanguageSupport:expandWordSelection(highlight)
    local document = highlight.ui.document
    local selection = highlight.selected_text

    language_code = document and document:getProps().language or "UNKNOWN"
    logger.dbg("language support expanding", language_code, "selection", selection)
    if document.info.has_pages then
        -- Word selection expansion relies on CreDocument:getNextVisibleChar.
        logger.dbg("language support currently cannot expand document selections in non-EPUB formats")
        return
    end

    local new_pos0, new_pos1 = unpack(self:findAndCallPlugin(
        language_code, "WordSelection",
        { document = document, selection = selection }
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

    -- We cannot use getTextFromPositions here because the conversion to and
    -- from screen co-ordinates leads to issues with text selection of <ruby>
    -- text. In addition, using getTextFromXPointers means we can select text
    -- not on the screen. But this means we need to manually create the text
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
        { document = document, text = text }
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
