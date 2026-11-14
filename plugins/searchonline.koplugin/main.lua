--[[--
This plugin allows the user to search selected text online.

@module koplugin.SearchOnline
--]]

local Device = require("device")
local HandleUrlString = require("handleurlstring")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local UIManager = require("ui/uimanager")
local url = require("socket.url")
local util = require("util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

if not Device:canOpenLink() then
    return { disabled = true, }
end

local SearchOnline = WidgetContainer:extend{
    default_search_engines = {
        "https://html.duckduckgo.com/html?q={q}",
        "https://google.com/search?q={q}",
        "https://en.m.wiktionary.org/wiki/{q}",
        "https://www.vocabulary.com/dictionary/{q}",
        "https://www.merriam-webster.com/dictionary/{q}",
        "https://www.dictionary.com/browse/{q}"
    },
    user_search_engines = G_reader_settings:readSetting("searchonline_user_search_engines", {}),
    disabled_default_engines = G_reader_settings:readSetting("searchonline_disabled_default_engines", {}),
}

function SearchOnline:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    self.ui.highlight:addToHighlightDialog("12_onlinesearch", function(reader_highlight_instance)
        return self:createHighlightMenuItem(reader_highlight_instance)
    end)

    -- Combine defaults with the user search engines
    self:rebuildSearchEngines()
end

function SearchOnline:rebuildSearchEngines()
    -- Build the local search_engines list from defaults
    self.search_engines = {}
    for _, engine in ipairs(self.default_search_engines) do
        if not self.disabled_default_engines[engine] then
            table.insert(self.search_engines, engine)
        end
    end
    -- Add user search engines
    for _, engine in ipairs(self.user_search_engines) do
        table.insert(self.search_engines, engine)
    end
end


function SearchOnline:getHighlight(reader_highlight_instance)
    if not reader_highlight_instance.selected_text or not reader_highlight_instance.selected_text.text then
        return
    end

    local query = util.cleanupSelectedText(reader_highlight_instance.selected_text.text)
    return query
end

function SearchOnline:createHighlightMenuItem(reader_highlight_instance)
    return {
        text = _("Search online"),
        enabled = Device:canOpenLink(),
        callback = function()
            NetworkMgr:runWhenOnline(function()
                self:chooseSearch(self:getHighlight(reader_highlight_instance))
            end)
        end
    }
end

-- combines the query string with the URL string of the chosen
-- search engine and passes it to `Device:openLink()`
function SearchOnline:searchOnline(query, search_engine)
    
    local chosen_engine = nil
    for _, engine in ipairs(self.search_engines) do
        if engine == search_engine then
            chosen_engine = engine
            break
        end
    end
    if not chosen_engine then
        HandleUrlString:urlError(search_engine .. " not found")
        return
    end

    if not chosen_engine:find("{q}") then
        HandleUrlString:urlError("The URL is misformatted, put {q} where the search term should go: " .. chosen_engine)
        return
    end

    local sanitised_query = url.escape(query)
    local build_url = chosen_engine:gsub("{q}", sanitised_query)

    if HandleUrlString:isValidUrl(build_url) then
        Device:openLink(build_url)
    end
end


function SearchOnline:chooseSearch(query)
    local radio_buttons = {}
    for index, engine_url in ipairs(self.search_engines) do
        table.insert(radio_buttons, { -- build a button for each
            {                         -- saved search engine
                text = HandleUrlString:getDomainName(engine_url),
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

function SearchOnline:addUserSearchEngine()
    self.user_input = InputDialog:new{
        title = _("Add a search engine"),
        input = "",
        input_hint = _"https://google.com/search?q={q}",
        description = _("Please add the URL for a search engine in the following format,\n"
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
                        self.user_input:onCloseKeyboard()
                        UIManager:close(self.user_input)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local input_text = self.user_input:getInputText()

                        -- Check if input is valid
                        if not input_text or input_text == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a valid URL"),
                            })
                            return
                        end

                        if true then
                            -- Check for duplicates
                            for _, existing_url in ipairs(self.user_search_engines) do
                                if existing_url == input_text then
                                    UIManager:show(InfoMessage:new{
                                        text = _("This URL already exists"),
                                    })
                                    return
                                end
                            end

                            -- Add the new URL
                            table.insert(self.user_search_engines, input_text)
                            table.insert(self.search_engines, input_text)
                            G_reader_settings:saveSetting("searchonline_user_search_engines", self.user_search_engines)

                            UIManager:show(InfoMessage:new{
                                text = _("Search engine added successfully: " .. input_text),
                            })
                        end

                        self.user_input:onCloseKeyboard()
                        UIManager:close(self.user_input)
                    end,
                },
            }
        },
    }
    UIManager:show(self.user_input)
    self.user_input:onShowKeyboard()
end

-- Look up words from the menu instead
function SearchOnline:lookupInput()
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
                        NetworkMgr:runWhenOnline(function()
                            local query = util.cleanupSelectedText(self.input_dialog:getInputText())
                            UIManager:close(self.input_dialog)
                            self:chooseSearch(query)
                        end)
                    end,
                },
            }
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function SearchOnline:addToMainMenu(menu_items)
    menu_items.searchonline_lookup = {
        text = _("Search online"),
        sorting_hint = "search",
        callback = function() self:lookupInput() end,
    }
    menu_items.searchonline_restore_default_search_engines = {
        text = _("Restore default search engines"),
        sorting_hint = "search",
        enabled_func = function ()
            return #self.user_search_engines > 0 or next(self.disabled_default_engines) ~= nil
        end,
        callback = function()
            G_reader_settings:saveSetting("searchonline_user_search_engines", {})
            self.user_search_engines = {}
            G_reader_settings:saveSetting("searchonline_disabled_default_engines", {})
            self.disabled_default_engines = {}
            self:rebuildSearchEngines()
        end,
    }
    menu_items.searchonline_add_custom_search_engines = {
        text = _("Add custom search engines"),
        sorting_hint = "search",
        callback = function() self:addUserSearchEngine() end
    }
end

function SearchOnline:removeUserSearchEngine(engine_url)
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
        G_reader_settings:saveSetting("searchonline_disabled_default_engines", self.disabled_default_engines)
    else
        -- If it's a user engine, remove it from user_search_engines
        for k, v in ipairs(self.user_search_engines) do
            if v == engine_url then
                table.remove(self.user_search_engines, k)
                break
            end
        end
        G_reader_settings:saveSetting("searchonline_user_search_engines", self.user_search_engines)
    end

    -- Remove from combined search_engines
    for k, v in ipairs(self.search_engines) do
        if v == engine_url then
            table.remove(self.search_engines, k)
            break
        end
    end
end

return SearchOnline
