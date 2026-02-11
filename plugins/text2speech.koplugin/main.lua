local Device = require("device")
if not Device:isAndroid() then
    return { disabled = true }
end

local isAndroid, android = pcall(require, "android")
if not isAndroid or not android or not android.tts then
    return { disabled = true }
end

local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local PluginShare = require("pluginshare")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local DEFAULT_SETTINGS = {
    rate_percent = 100,
    pitch_percent = 100,
    pause_seconds = 0.2,
    poll_interval = 0.2,
    auto_advance = true,
    max_chunk_len = 3200,
}

local MAX_SPEAK_FAILS = 50
local SETTINGS_KEY = "text2speech"
local LEGACY_SETTINGS_KEY = "readaloud"

local ReadAloud = WidgetContainer:extend{
    name = "text2speech",
    is_doc_only = true,

    playing = false,
    chunks = nil,
    chunk_index = 1,

    _poll_func = nil,
    _continue_func = nil,
    _pageupdate_func = nil,
    _internal_page_turn = false,
    _advance_from_key = nil,
}

local function fillDefaults(settings)
    settings = settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if settings[k] == nil then
            settings[k] = v
        end
    end
    return settings
end

local function normalizeText(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    return util.cleanupSelectedText(text)
end

local function chunkText(text, max_len)
    text = normalizeText(text)
    if text == "" then return {} end
    max_len = tonumber(max_len) or DEFAULT_SETTINGS.max_chunk_len
    if max_len < 200 then max_len = 200 end

    if #text <= max_len then
        return { text }
    end

    local chunks = {}
    local i = 1
    local n = #text

    -- NOTE: KOReader ships utf8proc and various UTF-8 helpers (see util.UTF8_CHAR_PATTERN).
    -- Here we only need to ensure we don't split inside a multibyte codepoint at a byte boundary,
    -- so a continuation-byte check is sufficient and fast.

    local function isUtf8ContinuationByte(b)
        return b ~= nil and b >= 128 and b <= 191
    end

    local function utf8SafeCut(start_pos, cut_pos)
        local b = text:byte(cut_pos)
        if isUtf8ContinuationByte(b) then
            local k = cut_pos
            while k > start_pos and isUtf8ContinuationByte(text:byte(k)) do
                k = k - 1
            end
            -- k now points to a likely leading byte; cut before it.
            cut_pos = k - 1
            if cut_pos < start_pos then
                cut_pos = start_pos
            end
        end
        return cut_pos
    end

    while i <= n do
        local j = math.min(i + max_len - 1, n)
        local cut = nil

        -- Try to cut at a sentence boundary first.
        for k = j, i, -1 do
            local c = text:sub(k, k)
            if c == "." or c == "!" or c == "?" then
                cut = k
                break
            end
        end

        -- Fallback to newline boundary.
        if not cut then
            for k = j, i, -1 do
                if text:sub(k, k) == "\n" then
                    cut = k
                    break
                end
            end
        end

        -- Last resort: cut at whitespace.
        if not cut then
            for k = j, i, -1 do
                if text:sub(k, k):match("%s") then
                    cut = k
                    break
                end
            end
        end

        cut = utf8SafeCut(i, cut or j)
        local chunk = normalizeText(text:sub(i, cut))
        if chunk ~= "" then
            table.insert(chunks, chunk)
        end
        i = cut + 1
    end

    return chunks
end

function ReadAloud:init()
    local settings = G_reader_settings:readSetting(SETTINGS_KEY)
    if settings == nil then
        settings = G_reader_settings:readSetting(LEGACY_SETTINGS_KEY, {})
    end
    self.settings = fillDefaults(settings)

    self._poll_func = function()
        self:_poll()
    end
    self._continue_func = function()
        self:_continueAfterTurn()
    end
    self._pageupdate_func = function()
        self:_restartFromCurrentView()
    end

    self.ui.menu:registerToMainMenu(self)
end

function ReadAloud:_saveSettings()
    G_reader_settings:saveSetting(SETTINGS_KEY, self.settings)
end

function ReadAloud:_showInfo(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function ReadAloud:_ttsEnsureReady()
    if not android.tts.init() then
        self:_showInfo(_("Failed to initialize the text-to-speech engine.\n\nPlease install a text-to-speech engine and voice data in system settings."))
        return false
    end
    android.tts.setSpeechRate(self.settings.rate_percent)
    android.tts.setPitch(self.settings.pitch_percent)
    return true
end

function ReadAloud:_getCurrentViewText()
    local doc = self.ui.document
    if not doc then return end

    local w, h = Screen:getWidth(), Screen:getHeight()
    if self.ui.rolling then
        local res = doc:getTextFromPositions({ x = 0, y = 0 }, { x = w, y = h }, true)
        return res and res.text
    end

    local page = self.ui:getCurrentPage()
    local res = doc:getTextFromPositions({ page = page, x = 0, y = 0 }, { page = page, x = w, y = h })
    return res and res.text
end

function ReadAloud:_prepareChunksForCurrentView()
    local text = self:_getCurrentViewText()
    if not text then
        return nil
    end
    local chunks = chunkText(text, self.settings.max_chunk_len)
    if #chunks == 0 then
        return nil
    end
    return chunks
end

function ReadAloud:_speakNextChunk()
    if not self.playing then
        return false
    end
    if not self.chunks or self.chunk_index > #self.chunks then
        return false
    end

    local chunk = self.chunks[self.chunk_index]
    local ok = android.tts.speak(chunk, android.tts.QUEUE_FLUSH)
    if ok then
        self._speak_fail_count = 0
        self.chunk_index = self.chunk_index + 1
        return true
    end

    self._speak_fail_count = (self._speak_fail_count or 0) + 1
    logger.warn("ReadAloud: ttsSpeak returned false")
    if self._speak_fail_count >= MAX_SPEAK_FAILS then
        self:stop()
        self:_showInfo(_("The text-to-speech engine is not ready.\n\nPlease install a text-to-speech engine and voice data in system settings."))
    end
    return false
end

function ReadAloud:_schedulePoll()
    UIManager:unschedule(self._poll_func)
    UIManager:scheduleIn(self.settings.poll_interval, self._poll_func)
end

function ReadAloud:_poll()
    if not self.playing then
        return
    end

    local speaking = false
    local ok, res = pcall(android.tts.isSpeaking)
    if ok then
        speaking = res and true or false
    else
        logger.warn("ReadAloud: android.tts.isSpeaking failed:", res)
    end

    if speaking then
        self:_schedulePoll()
        return
    end

    -- Not speaking: either speak next chunk, or advance.
    if self.chunks and self.chunk_index <= #self.chunks then
        self:_speakNextChunk()
        self:_schedulePoll()
        return
    end

    if not self.settings.auto_advance then
        self:stop()
        return
    end

    -- Advance to next view/page.
    self._internal_page_turn = true
    self._advance_from_key = self:_getLocationKey()
    UIManager:unschedule(self._continue_func)
    UIManager:broadcastEvent(Event:new("GotoViewRel", 1))
    local pause = tonumber(self.settings.pause_seconds) or DEFAULT_SETTINGS.pause_seconds
    if pause < 0 then pause = 0 end
    UIManager:scheduleIn(pause, self._continue_func)
end

function ReadAloud:_getLocationKey()
    -- Best-effort location key to detect end-of-document loops.
    if self.ui.rolling and self.ui.rolling.xpointer then
        return tostring(self.ui.rolling.xpointer)
    end
    local ok, page = pcall(function() return self.ui:getCurrentPage() end)
    if ok and page then
        return tostring(page)
    end
end

function ReadAloud:_continueAfterTurn()
    if not self.playing then
        return
    end
    self._internal_page_turn = false

    local prev_key = self._advance_from_key
    self._advance_from_key = nil
    if prev_key then
        local new_key = self:_getLocationKey()
        if new_key and new_key == prev_key then
            self:stop()
            self:_showInfo(_("End of document reached."))
            return
        end
    end

    self.chunks = self:_prepareChunksForCurrentView()
    self.chunk_index = 1
    if not self.chunks then
        -- No text found on this view; stop to avoid infinite loops.
        self:stop()
        self:_showInfo(_("No text found on this page."))
        return
    end

    self:_speakNextChunk()
    self:_schedulePoll()
end

function ReadAloud:_restartFromCurrentView()
    if not self.playing then
        return
    end
    if self._internal_page_turn then
        return
    end
    pcall(android.tts.stop)
    UIManager:unschedule(self._continue_func)
    UIManager:scheduleIn(0.05, self._continue_func)
end

function ReadAloud:start()
    if self.playing then
        return
    end
    if not self:_ttsEnsureReady() then
        return
    end

    PluginShare.pause_auto_suspend = true
    self.playing = true
    self._speak_fail_count = 0
    self.chunks = self:_prepareChunksForCurrentView()
    self.chunk_index = 1

    if not self.chunks then
        self:stop()
        self:_showInfo(_("No text found on this page."))
        return
    end

    self:_speakNextChunk()
    self:_schedulePoll()
end

function ReadAloud:stop()
    if not self.playing then
        return
    end
    self.playing = false
    self._internal_page_turn = false
    self._speak_fail_count = 0

    UIManager:unschedule(self._poll_func)
    UIManager:unschedule(self._continue_func)
    UIManager:unschedule(self._pageupdate_func)

    pcall(android.tts.stop)
    PluginShare.pause_auto_suspend = false
end

function ReadAloud:_showRateDialog(menu)
    local dialog = SpinWidget:new{
        title_text = _("Speech rate"),
        value = self.settings.rate_percent,
        value_min = 50,
        value_max = 200,
        value_step = 10,
        value_hold_step = 25,
        ok_text = _("Apply"),
        callback = function(spin)
            self.settings.rate_percent = spin.value
            self:_saveSettings()
            if self.playing then
                android.tts.setSpeechRate(spin.value)
            end
            if menu then menu:updateItems() end
        end,
    }
    UIManager:show(dialog)
end

function ReadAloud:_showPitchDialog(menu)
    local dialog = SpinWidget:new{
        title_text = _("Speech pitch"),
        value = self.settings.pitch_percent,
        value_min = 50,
        value_max = 200,
        value_step = 10,
        value_hold_step = 25,
        ok_text = _("Apply"),
        callback = function(spin)
            self.settings.pitch_percent = spin.value
            self:_saveSettings()
            if self.playing then
                android.tts.setPitch(spin.value)
            end
            if menu then menu:updateItems() end
        end,
    }
    UIManager:show(dialog)
end

function ReadAloud:_showPauseDialog(menu)
    local dialog = SpinWidget:new{
        title_text = _("Pause between pages"),
        value = math.floor((self.settings.pause_seconds or DEFAULT_SETTINGS.pause_seconds) * 1000),
        value_min = 0,
        value_max = 5000,
        value_step = 100,
        value_hold_step = 500,
        unit = _("ms"),
        ok_text = _("Apply"),
        callback = function(spin)
            self.settings.pause_seconds = spin.value / 1000
            self:_saveSettings()
            if menu then menu:updateItems() end
        end,
    }
    UIManager:show(dialog)
end

function ReadAloud:_toggleAutoAdvance(menu)
    self.settings.auto_advance = not self.settings.auto_advance
    self:_saveSettings()
    if menu then menu:updateItems() end
end

function ReadAloud:_showControlDialog(menu)
    local dialog
    local startStopText = self.playing and _("Stop") or _("Start")
    local autoAdvanceText = self.settings.auto_advance and _("Auto-advance: on") or _("Auto-advance: off")

    dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = startStopText,
                    callback = function()
                        UIManager:close(dialog)
                        if self.playing then
                            self:stop()
                        else
                            self:start()
                        end
                        if menu then menu:updateItems() end
                    end,
                    align = "left",
                },
            },
            {
                {
                    text = _("Speech rate"),
                    callback = function()
                        UIManager:close(dialog)
                        self:_showRateDialog(menu)
                    end,
                    align = "left",
                },
                {
                    text = _("Speech pitch"),
                    callback = function()
                        UIManager:close(dialog)
                        self:_showPitchDialog(menu)
                    end,
                    align = "left",
                },
            },
            {
                {
                    text = _("Pause between pages"),
                    callback = function()
                        UIManager:close(dialog)
                        self:_showPauseDialog(menu)
                    end,
                    align = "left",
                },
                {
                    text = autoAdvanceText,
                    callback = function()
                        UIManager:close(dialog)
                        self:_toggleAutoAdvance(menu)
                    end,
                    align = "left",
                },
            },
            {
                {
                    text = _("Install voice data"),
                    callback = function()
                        UIManager:close(dialog)
                        android.tts.installData()
                    end,
                    align = "left",
                },
                {
                    text = _("Text-to-speech settings"),
                    callback = function()
                        UIManager:close(dialog)
                        android.tts.openSettings()
                    end,
                    align = "left",
                },
            },
        },
        shrink_unneeded_width = true,
    }
    UIManager:show(dialog)
end

function ReadAloud:addToMainMenu(menu_items)
    menu_items.text_to_speech = {
        sorting_hint = "navi",
        text_func = function()
            local rate = tonumber(self.settings.rate_percent) or DEFAULT_SETTINGS.rate_percent
            local suffix = string.format("%.2fx", rate / 100)
            if self.playing then
                return T(_("Text-to-speech: %1"), suffix)
            end
            return _("Text-to-speech")
        end,
        checked_func = function() return self.playing end,
        callback = function(menu)
            self:_showControlDialog(menu)
        end,
    }
end

function ReadAloud:onCloseWidget()
    self:stop()
end

function ReadAloud:onCloseDocument()
    self:stop()
end

function ReadAloud:onSuspend()
    self:stop()
end

function ReadAloud:onPageUpdate()
    if not self.playing then return end
    -- Debounce restarts on manual page turns.
    UIManager:unschedule(self._pageupdate_func)
    UIManager:scheduleIn(0.05, self._pageupdate_func)
end

return ReadAloud
