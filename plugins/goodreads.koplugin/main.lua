local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local DoubleKeyValuePage = require("doublekeyvaluepage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")

local GoodReads = InputContainer:new {
    goodreaders_key = "",
    goodreaders_secret = "",
}

function GoodReads:init()
    local gr_sett = DoubleKeyValuePage:readGRSettings().data
    if gr_sett.goodreads then
        self.goodreaders_key = gr_sett.goodreads.key
        self.goodreaders_secret = gr_sett.goodreads.secret
    end
    self.ui.menu:registerToMainMenu(self)
end

function GoodReads:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("GoodReads"),
        sub_item_table = {
            {
                text = _("Settings"),
                callback = function() self:updateSettings() end,
            },
            {
                text = _("Search book all"),
                callback = function()
                    if self.goodreaders_key ~= ""  then
                        self:search("all")
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up GoodReads key in settings"),
                        })
                    end
                end,
            },
            {
                text = _("Search book by title"),
                callback = function()
                    if self.goodreaders_key ~= ""  then
                        self:search("title")
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up GoodReads key in settings"),
                        })
                    end
                end,
            },
            {
                text = _("Search book by author"),
                callback = function()
                    if self.goodreaders_key ~= ""  then
                        self:search("author")

                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up GoodReads key in settings"),
                        })
                    end
                end,
            },
        },
    })
end

function GoodReads:updateSettings()
    local hint_top
    local text_top
    local hint_bottom
    local text_bottom
    local text_info = "How to generate key and secret key:\n"..
    "1. Go to https://www.goodreads.com/user/sign_up and create account\n" ..
    "2. Register development key on page: https://www.goodreads.com/user/sign_in?rd=true\n" ..
    "3. Your key and secret key are on https://www.goodreads.com/api/keys\n" ..
    "4. Enter your generated key and secret key in settings (Login to GoodReads window)"
    if self.goodreaders_key == "" then
        hint_top = _("GoodReaders Key Not Set")
        text_top = ""
    else
        hint_top = ""
        text_top = self.goodreaders_key
    end

    if self.goodreaders_secret == "" then
        hint_bottom = _("GoodReaders Secret Key Not Set (optional)")
        text_bottom = ""
    else
        hint_bottom = ""
        text_bottom = self.goodreaders_key
    end
    self.settings_dialog = MultiInputDialog:new {
        title = _("Login to GoodReads"),
        fields = {
            {
                text = text_top,
                input_type = "string",
                hint = hint_top ,
            },
            {
                text = text_bottom,
                input_type = "string",
                hint = hint_bottom,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings(MultiInputDialog:getFields())
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
        input_type = "text",
    }
    self.settings_dialog:onShowKeyboard()
    UIManager:show(self.settings_dialog)
end

function GoodReads:saveSettings(fields)
    if fields then
        self.goodreaders_key = fields[1]
        self.goodreaders_secret = fields[2]
    end
    local settings = {
        key = self.goodreaders_key,
        secret = self.goodreaders_secret,
    }
    DoubleKeyValuePage:saveGRSettings(settings)
end

-- search_type = all - search all
-- search_type = author - serch book by author
-- search_type = title - search book by title
function GoodReads:search(search_type)
    local title_header
    local hint
    local search_input
    local text_input
    local info
    local result
    if search_type == "all" then
        title_header = _("Search book all in GoodReads")
        hint = _("Title, author or ISBN")
    elseif search_type == "author" then
        title_header = _("Search book by author in GoodReads")
        hint = _("Author")
    elseif search_type == "title" then
        title_header = _("Search book by title in GoodReads")
        hint = _("Title")
    end

    search_input = InputDialog:new{
        title = title_header,
        input = "",
        input_hint = hint,
        input_type = "string",
        buttons = {
            {
                {
                 text = _("Cancel"),
                    callback = function()
                        UIManager:close(search_input)
                    end,
                },
                {
                    text = _("Find"),
                    is_enter_default = true,
                    callback = function()
                        text_input = search_input:getInputText()
                        if text_input ~= nil and text_input ~= "" then
                            info = InfoMessage:new{text = _("Please wait..."), timeout = 0.0}
                            UIManager:show(info)
                            UIManager:nextTick(function()
                                result = DoubleKeyValuePage:new{
                                    title = _("Select book"),
                                    text_input = text_input,
                                    search_type = search_type,
                                }
                                if #result.kv_pairs > 0 then
                                    UIManager:show(result)
                                end
                            end)
                            UIManager:close(search_input)
                        else
                            UIManager:show(InfoMessage:new{
                                text =_("Please input text"),
                            })
                        end
                    end,
                },
            }
        },
    }
    search_input:onShowKeyboard()
    UIManager:show(search_input)
end

return GoodReads
