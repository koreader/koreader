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

local function xpEqual(document, xp1, xp2)
    return document:compareXPointers(xp1, xp2) == 0
end

-- Called from ReaderHighlight:onHold after the document-specific handler has
-- successfully grabbed a "word" from the document.
function LanguageSupport:expandWordSelection(highlight)
    local document = highlight.ui.document
    local selection = highlight.selected_text

    language_code = document:getProps().language
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
        (xpEqual(document, new_pos0, selection.pos0) and
         xpEqual(document, new_pos1, selection.pos1)) then
        logger.dbg("no language plugin could expand the selection")
        return
    end
    if document:getPageFromXPointer(new_pos0) ~= document:getPageFromXPointer(new_pos1) then
        -- TODO: Handle cross-page words by switch to the multi-page scroll
        --       mechanism used for hold-and-pan.
        logger.dbg("entire word is not visible (cross-page word) so skipping expansion")
        return
    end
    logger.dbg("expanding selection\n",
        selection.pos0, ":", selection.pos1, "to\n", new_pos0, ":", new_pos1)

    -- Get {x,y} positions from XPointers. This is needed because the only way
    -- we can set the crengine internal selection is through page positions not
    -- XPointers. Not doing this would require us to set the readerview temp
    -- highlighter which isn't as accurate as crengine and requries
    -- clearSelection() which is somewhat expensive.
    local new_pos0_xy = xpToPosition(document, new_pos0)
    local new_pos1_xy = xpToPosition(document, new_pos1)
    local new_text = document:getTextFromPositions(new_pos0_xy, new_pos1_xy)
    if not new_text then
        -- TODO: Figure out what causes this.
        logger.dbg("could not find text in positions", new_pos0_xy, new_pos1_xy)
        return
    end

    -- getTextFromPositions struggles to handle <ruby> text properly. The
    -- position you get from getScreenPositionFromXPointer skips over the end
    -- of <ruby> text and selects the character after the text -- this even
    -- more apparent when you note that the returned XPointers from
    -- getTextFromPositions don't match the XPointers we used to generate the
    -- screen positions in the first place. However, getTextFromXPointers
    -- handles it correctly and fixing up the {pos0, pos1} afterwards appears
    -- to set the highlight correctly.
    if not xpEqual(document, new_text.pos0, new_pos0) or
       not xpEqual(document, new_text.pos1, new_pos1) then
        logger.dbg("getTextFromPositions returned incorrect selection", new_text.pos0, ":", new_text.pos1)
        local accurate_text = document:getTextFromXPointers(new_pos0, new_pos1)
        -- We only need to do this adjustment if the text is actually different.
        if accurate_text and accurate_text ~= new_text.text then
            logger.dbg("correcting screen-position selection to be XPointer-accurate")
            new_text.pos0 = new_pos0
            new_text.pos1 = new_pos1
            new_text.text = accurate_text
        end
    end

    -- getTextFromPositions doesn't set the sboxes correctly so we have to
    -- manually fetch them and recreate the highlight text.
    new_text.sboxes = document:getScreenBoxesFromPositions(new_text.pos0, new_text.pos1, true)
    new_text.text = cleanupSelectedText(new_text.text)

    highlight.selected_text = new_text
end

-- Called from ReaderHighlight:startSdcv after the selected has text has been
-- OCR'd, cleaned, and otherwise made ready for sdcv.
function LanguageSupport:dictionaryFormCandidates(document, text)
    language_code = document:getProps().language
    logger.dbg("language support: convert", text, "to dictionary form (marked as", language_code..")")

    return self:findAndCallPlugin(
        language_code, "WordLookup",
        { document = document, text = text }
    )
end

function LanguageSupport:addToMainMenu(menu_items)
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
