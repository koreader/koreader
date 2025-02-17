--[[--
This module is used by ReaderHighlight to search selected text online.
--]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")

local ReaderSearchOnline = InputContainer:extend{
    default_search_engines = {
        "https://duckduckgo.com/{q}",
        "https://google.com/search?q={q}",
        "https://en.m.wiktionary.org/wiki/{q}",
        "https://www.vocabulary.com/dictionary/{q}",
        "https://www.merriam-webster.com/dictionary/{q}",
        "https://www.dictionary.com/browse/{q}"
    },
    user_search_engines = G_reader_settings:readSetting("user_search_engines", {}),
    disabled_default_engines = G_reader_settings:readSetting("disabled_default_engines", {}),
}

function ReaderSearchOnline:urlError(text)
    UIManager:show(InfoMessage:new{
        text = _(text),
        timeout = 3
    })
end


function ReaderSearchOnline:init()
    if Device:hasKeyboard() then
        self:registerKeyEvents()
    end

    -- Ensure self.ui exists before using it
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    else
        self:urlError("Warning: self.ui is nil, skipping menu registration.")
    end

    -- Combine the two tables
    self.search_engines = {}
    for _, value in ipairs(self.default_search_engines) do
        if not self.disabled_default_engines[value] then
            table.insert(self.search_engines, value)
        end
    end

    for _, value in ipairs(self.user_search_engines) do
        if not self.disabled_default_engines[value] then
            table.insert(self.search_engines, value)
        end
    end
end

function ReaderSearchOnline:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.online_search_shortcut = {} -- Keyboard shortcut here
    end
end

function ReaderSearchOnline:isValidUrl(url_string)
    local parsed_url = url.parse(url_string)

    if not parsed_url then
        self.urlError("Could not parse URL. It may be misformatted: " .. url_string)
        return false
    end

    if not parsed_url.scheme then
        self.urlError("The URL is missing http:/https: " .. url_string)
        return false
    end

    if not parsed_url.host then
        self.urlError("Missing or invalid host: " .. url_string)
        return false
    end

    return true
end

function ReaderSearchOnline:getDomainName(engine_url)
    local parsed = url.parse(engine_url)
    if parsed and parsed.host then
        -- Remove 'www.' if present
        local domain = parsed.host:gsub("^www%.", "")

        -- Split the domain by dots
        local parts = {}
        for part in util.gsplit(domain, "%.") do
            table.insert(parts, part)
        end

        -- Keep all parts except the last one (com/org/net etc)
        local result = {}
        for i = 1, #parts - 1 do
            table.insert(result, parts[i])
        end

        -- Join the parts back together with dots
        local name = table.concat(result, ".")

        -- Capitalize the first letter of each part
        name = name:gsub("(%w)([%w]*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)

        return name
    end
    return engine_url -- return raw URL if we can't parse it
end

function ReaderSearchOnline:searchOnline(query, search_engine)
    if not Device:canOpenLink() then return end

    local chosen_engine = nil
    for _, engine in ipairs(self.search_engines) do
        if engine == search_engine then
            chosen_engine = engine
            break
        end
    end
    if not chosen_engine then
        self.urlError(search_engine .. " not found")
        return
    end

    if not chosen_engine:find("{q}") then
        self.urlError("The URL is misformatted, put {q} where the search term should go: " .. chosen_engine)
        return
    end

    local sanitised_query = url.escape(query)
    local build_url = chosen_engine:gsub("{q}", sanitised_query)

    if self:isValidUrl(build_url) then
        Device:openLink(build_url)
    end
end

function ReaderSearchOnline:chooseSearch(query)
    local radio_buttons = {}
    -- The structure should be: { {button1}, {button2}, ... }
    -- where each button is a single table with properties
    for index, engine_url in ipairs(self.search_engines) do
        table.insert(radio_buttons, {
            {  -- Single level of nesting for each button
                text = self:getDomainName(engine_url),
                provider = engine_url,
                checked = index == 1
            }
        })
    end

    self.choose_search = RadioButtonWidget:new{
        title_text = _("Choose search engine"),
        width_factor = 0.8,
        radio_buttons = radio_buttons,
        cancel_text = _("Cancel"),
        extra_text = _("Remove"),
        ok_text = _("Search"),
        callback = function(radio)
            if radio.provider then
                self:searchOnline(query, radio.provider)
            end
        end,
        extra_callback = function(radio)
            if radio.provider then
                self:removeUserSearchEngine(radio.provider)
                UIManager:close(self.choose_search)
                self:chooseSearch(query)
            end
        end,
        cancel_callback = function()
            UIManager:close(self.choose_search)
        end
    }
    UIManager:show(self.choose_search)
end

function ReaderSearchOnline:addUserSearchEngine()
    self.user_input = InputDialog:new{
        title = _("Add a search engine"),
        input = "",
        input_hint = _("Please add the URL for a search engine in the following format,\n"
        .. "{q} represents the word you want to search for.\n"
        .. "https://google.com/search?q={q}\n"
        .. "https://en.m.wiktionary.org/wiki/{q}"
        ),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close()
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        self.user_input:onCloseKeyboard()
                        UIManager:close(self.input_dialog)
                        local new_url = util.cleanupSelectedText(self.user_input:getInputValue())
                        if self:isValidUrl(self.user_input:getInputValue()) then
                            for _, existing_url in ipairs(self.user_search_engines) do
                                if existing_url == new_url then
                                    print("Search engine already exists: " .. new_url)
                                    return
                                end
                            end
                            table.insert(self.user_search_engines, new_url)
                            table.insert(self.search_engines, new_url)
                            G_reader_settings:saveSetting("user_search_engines", self.user_search_engines)
                        end
                    end,
                },
            }
        },
    }
    self.user_input:onShowKeyboard()
end

function ReaderSearchOnline:lookupInput()
    self.input_dialog = InputDialog:new{
        title = _("Enter a word or phrase to search online"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("Search Online"),
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        UIManager:close(self.input_dialog)
                        self:chooseSearch(self.user_input:getInputValue())
                    end,
                },
            }
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function ReaderSearchOnline:addToMainMenu(menu_items)
    menu_items.search_online = {
        text = _("Search online"),
        callback = function() self:lookupInput() end,
    }
    menu_items.restore_default_search_engines = {
        text = _("Restore default search engines"),
        callback = function()
            G_reader_settings:saveSetting("user_search_engines", {})
            G_reader_settings:saveSetting("disabled_default_engines", {})
            ReaderSearchOnline:init()
            UIManager.close()
        end,
    }
end

function ReaderSearchOnline:removeUserSearchEngine(engine_url)
    -- Check if it's a default engine
    local is_default = false
    for _, v in ipairs(self.default_search_engines) do
        if v == engine_url then
            is_default = true
            break
        end
    end

    if is_default then
        -- If it's a default engine, mark it as disabled
        self.disabled_default_engines[engine_url] = true
        G_reader_settings:saveSetting("disabled_default_engines", self.disabled_default_engines)
    else
        -- If it's a user engine, remove it from user_search_engines
        for k, v in ipairs(self.user_search_engines) do
            if v == engine_url then
                table.remove(self.user_search_engines, k)
                break
            end
        end
        G_reader_settings:saveSetting("user_search_engines", self.user_search_engines)
    end

    -- Remove from combined search_engines
    for k, v in ipairs(self.search_engines) do
        if v == engine_url then
            table.remove(self.search_engines, k)
            break
        end
    end
end

return ReaderSearchOnline
