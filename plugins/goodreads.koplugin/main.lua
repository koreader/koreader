local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local DoubleKeyValuePage = require("doublekeyvaluepage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")

local Goodreads = InputContainer:new {
    name = "goodreads",
    goodreads_key = "",
    goodreads_secret = "",
}

function Goodreads:init()
    local gr_sett = DoubleKeyValuePage:readGRSettings().data
    if gr_sett.goodreads then
        self.goodreads_key = gr_sett.goodreads.key
        self.goodreads_secret = gr_sett.goodreads.secret
    end
    self.ui.menu:registerToMainMenu(self)
end

function Goodreads:addToMainMenu(menu_items)
    menu_items.goodreads = {
        text = _("Goodreads"),
        sub_item_table = {
            {
                text = _("Settings"),
                keep_menu_open = true,
                callback = function() self:updateSettings() end,
            },
            {
                text = _("Search all books"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self.goodreads_key ~= ""  then
                        touchmenu_instance:closeMenu()
                        self:search("all")
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up your Goodreads key in the settings dialog"),
                        })
                    end
                end,
            },
            {
                text = _("Search for book by title"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self.goodreads_key ~= ""  then
                        touchmenu_instance:closeMenu()
                        self:search("title")
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up your Goodreads key in the settings dialog"),
                        })
                    end
                end,
            },
            {
                text = _("Search for book by author"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self.goodreads_key ~= ""  then
                        touchmenu_instance:closeMenu()
                        self:search("author")
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up your Goodreads key in the settings dialog"),
                        })
                    end
                end,
            },
        },
    }
end

function Goodreads:updateSettings()
    local hint_top
    local text_top
    local hint_bottom
    local text_bottom
    local text_info = _([[
How to generate a key and a secret key:

1. Go to https://www.goodreads.com/user/sign_up and create an account
2. Register for a development key on the following page: https://www.goodreads.com/user/sign_in?rd=true
3. Your key and secret key will now be available on https://www.goodreads.com/api/key
4. Enter your generated key and your secret key in the settings dialog (Login to Goodreads window)
]])

    if self.goodreads_key == "" then
        hint_top = _("Goodreads key left empty")
        text_top = ""
    else
        hint_top = ""
        text_top = self.goodreads_key
    end

    if self.goodreads_secret == "" then
        hint_bottom = _("Goodreads secret left empty (optional)")
        text_bottom = ""
    else
        hint_bottom = ""
        text_bottom = self.goodreads_key
    end
    self.settings_dialog = MultiInputDialog:new {
        title = _("Login to Goodreads"),
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
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
        input_type = "text",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Goodreads:saveSettings(fields)
    if fields then
        self.goodreads_key = fields[1]
        self.goodreads_secret = fields[2]
    end
    local settings = {
        key = self.goodreads_key,
        secret = self.goodreads_secret,
    }
    DoubleKeyValuePage:saveGRSettings(settings)
end

-- search_type = all - search all
-- search_type = author - serch book by author
-- search_type = title - search book by title
function Goodreads:search(search_type)
    if NetworkMgr:willRerunWhenOnline(function() self:search(search_type) end) then
       return
    end

    local title_header
    local hint
    local search_input
    local text_input
    local info
    local result
    if search_type == "all" then
        title_header = _("Search all books in Goodreads")
        hint = _("Title, author or ISBN")
    elseif search_type == "author" then
        title_header = _("Search for book by author in Goodreads")
        hint = _("Author")
    elseif search_type == "title" then
        title_header = _("Search for book by title in Goodreads")
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
                            info = InfoMessage:new{text = _("Please wait…")}
                            UIManager:close(search_input)
                            UIManager:show(info)
                            UIManager:forceRePaint()
                            result = DoubleKeyValuePage:new{
                                title = _("Select book"),
                                text_input = text_input,
                                search_type = search_type,
                            }
                            if #result.kv_pairs > 0 then
                                UIManager:show(result)
                            end
                            UIManager:close(info)

                        else
                            UIManager:show(InfoMessage:new{
                                text =_("Please enter text"),
                            })
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(search_input)
    search_input:onShowKeyboard()
end

return Goodreads
