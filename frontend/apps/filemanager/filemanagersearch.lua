local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("ui/screen")
local Menu = require("ui/widget/menu")

local Search = InputContainer:new{
    calibrefile=nil,
    search_dialog=nil,
    authors = 1,
    title = 2,
    path = 3,
    tags = 4,
    series = 5,
    count = 0,
    data = {},
    results = {},
}

function Search:init()
    self.data = {}
    self.results = {}

    -- check if we find the calibre file
    if LIBRARY_PATH == nil then 
		    UIManager:show(InfoMessage:new{text = _("LIBRARY_PATH in DEFAULTS.LUA is not set!"),})
    else
        if string.sub(LIBRARY_PATH,string.len(LIBRARY_PATH)) ~= "/" then
            LIBRARY_PATH = LIBRARY_PATH .. "/"
        end
        if io.open(LIBRARY_PATH .. "metadata.calibre","r") == nil then
            if io.open(LIBRARY_PATH .. ".metadata.calibre","r") == nil then
		            UIManager:show(InfoMessage:new{text = _(LIBRARY_PATH .. "metadata.calibre not found!")})
		        else
                self.calibrefile = LIBRARY_PATH .. ".metadata.calibre"
            end
        else
            self.calibrefile = LIBRARY_PATH .. "metadata.calibre"
        end

        if not (SEARCH_AUTHORS or SEARCH_TITLE or SEARCH_PATH or SEARCH_SERIES or SEARCH_TAGS) then
            self.calibrefile = nil
            UIManager:show(InfoMessage:new{text = _("You must specify at least one field to search at! (SEARCH_XXX = true in defaults.lua)")})
        end
    end
    
    if self.calibrefile ~= nil then
        local dummy = ""
        if SEARCH_CASESENSITIVE then
            dummy = "case sensitive)"
        else
            dummy = "case insensitive)"
        end
        self.search_dialog = InputDialog:new{
            title = _("Search Books (" .. dummy),
            buttons = {
                {
                    {
                        text = _("Find"),
                        enabled = true,
                        callback = function()
                            self.search_value=self.search_dialog:getInputText()
                            self:close()
                        end,
                    },
                },
            },
            width = Screen:getWidth() * 0.8,
            height = Screen:getHeight() * 0.2,
        }
        self.search_dialog:onShowKeyboard()
        UIManager:show(self.search_dialog)
    end
end

function Search:close()
    self.search_dialog:onClose()
    UIManager:close(self.search_dialog)
    if string.len(self.search_value) > 0 then
        self:find()
    end
end

function Search:find()
    local f = io.open(self.calibrefile)
    local line = f:read()
    local i = 1
    local upsearch
    local dummy

    -- removes leading and closing characters and converts hex-unicodes
    local ReplaceHexChars = function(s,n)
        local l=string.len(s)

        if string.sub(s,l,l) == "\"" then
            s=string.sub(s,n,string.len(s)-1)
        else
            s=string.sub(s,n,string.len(s)-3)
        end

-- todo: identify \uXXXX values and enter. Better solution: Find a better way how to replace hex-unicodes with \XXX\XXX constructs
--        s=string.gsub(s,"\\","\195\160") -- à
--        s=string.gsub(s,"\\","\195\178") -- ò
--        s=string.gsub(s,"\\","\195\168") -- è
--        s=string.gsub(s,"\\","\195\172") -- ì
--        s=string.gsub(s,"\\","\195\185") -- ù
--        s=string.gsub(s,"\\","\195\161") -- á
--        s=string.gsub(s,"\\","\195\179") -- ó
--        s=string.gsub(s,"\\","\195\169") -- é
--        s=string.gsub(s,"\\","\195\173") -- í
--        s=string.gsub(s,"\\","\195\186") -- ú
--        s=string.gsub(s,"\\","\195\162") -- â
--        s=string.gsub(s,"\\","\195\180") -- ô
--        s=string.gsub(s,"\\","\195\170") -- ê
--        s=string.gsub(s,"\\","\195\174") -- î
--        s=string.gsub(s,"\\","\195\187") -- û
--        s=string.gsub(s,"\\","\195\163") -- ã
--        s=string.gsub(s,"\\","\195\181") -- õ
--        s=string.gsub(s,"\\","\195\171") -- ë
--        s=string.gsub(s,"\\","\195\175") -- ï
--        s=string.gsub(s,"\\","\195\166") -- æ
--        s=string.gsub(s,"\\","\195\184 ") -- ø
--        s=string.gsub(s,"\\","\195\167") -- ç
--        s=string.gsub(s,"\\","\195\177") -- ñ
        
        s=string.gsub(s,"\\u00c4","\195\132") -- Ä
        s=string.gsub(s,"\\u00d6","\195\150") -- Ö
        s=string.gsub(s,"\\u00dc","\195\156") -- Ü

        s=string.gsub(s,"\\u00e4","\195\164") -- ä
        s=string.gsub(s,"\\u00fc","\195\188") -- ü
        s=string.gsub(s,"\\u00f6","\195\182") -- ö

        s=string.gsub(s,"\\u00df","\195\159") -- ß
        s=string.gsub(s,"\\u2019","'") -- '

        return s
    end

    -- ready entries with multiple lines from calibre
    local ReadMultipleLines = function(s)
        self.data[i][s]=""
        while line ~= "    ], " do
            line = f:read()
            if line ~= "    ], " then
                self.data[i][s]=self.data[i][s] .. "," .. ReplaceHexChars(line,8)
            end
        end
        self.data[i][s] = string.sub(self.data[i][s],2)
    end


    if SEARCH_CASESENSITIVE then
        upsearch = self.search_value
    else
        upsearch = string.upper(self.search_value)
    end
    
    self.data[i] = {"","","","",""}
    while line do
        if line == "  }, " or line == "  }" then
            -- new calibre data set

            dummy = ""
            if SEARCH_AUTHORS then dummy = dummy .. self.data[i][self.authors] end
            if SEARCH_TITLE then dummy = dummy .. self.data[i][self.title] end
            if SEARCH_PATH then dummy = dummy .. self.data[i][self.path] end
            if SEARCH_SERIES then dummy = dummy .. self.data[i][self.series] end
            if SEARCH_TAGS then dummy = dummy .. self.data[i][self.tags] end
            if not SEARCH_CASESENSITIVE then dummy = string.upper(dummy) end

            if string.find(dummy,upsearch) then
                i = i + 1
                self.data[i] = {"","","","",""}
            end

        elseif line == "    \"authors\": [" then -- AUTHORS
            ReadMultipleLines(self.authors)
        elseif line == "    \"tags\": [" then -- TAGS
            ReadMultipleLines(self.tags)
		    elseif string.sub(line,1,11) == "    \"title\"" then -- TITLE
    				self.data[i][self.title] = ReplaceHexChars(line,15)
		    elseif string.sub(line,1,11) == "    \"lpath\"" then -- LPATH
    				self.data[i][self.path] = string.sub(line,15,string.len(line)-3)
		    elseif string.sub(line,1,12) == "    \"series\"" and line ~= "    \"series\": null, " then -- SERIES
    				self.data[i][self.series] = ReplaceHexChars(line,16)
	      end
	      line = f:read()
    end
    i = i - 1
    if i > 0 then
        self.count = i
        self:showresults()
    else
        UIManager:show(InfoMessage:new{text = _("No match for " .. self.search_value)})
    end
end

function Search:showresults()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth()-50,
        height = Screen:getHeight()-50,
        show_parent = menu_container,
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    local i = 1
    while i <= self.count do
        local book = LIBRARY_PATH .. self.data[i][self.path]

        table.insert(self.results, {
           text = self.data[i][self.authors] .. ": " .. self.data[i][self.title],
           callback = function()
              if book then
                  showReaderUI(book)
              end
           end
        })
        i = i + 1
    end
    self.search_menu:swithItemTable("Search Results", self.results)
    UIManager:show(menu_container)
end

return Search
