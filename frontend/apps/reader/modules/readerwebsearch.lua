local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Trapper = require("ui/trapper")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local Wikipedia = require("ui/wikipedia")
local lfs = require("libs/libkoreader-lfs")
local MenuSorter = require("ui/menusorter")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

--[[--

local websearchsitesdata = {
  google_fr = {
    title  = "Google (FR)",
    prefix = "'https://www.google.com/search?q='",
    suffix = ""
  },
  google_en = {
    title  = "Google (EN)",
    prefix = "'https://www.google.com/search?q='",
    suffix = ""
  },
  duckduckgo_en = {
    title  = "DuckduckGo",
    prefix = "https://duckduckgo.com/?q=",
    suffix = ""
  },
  zlibrary = {
    title  = "ZLibrary",
    prefix = "https://book4you.org/s/",
    suffix = ""
  },
  linkedin = {
    title  = "LinkedIn",
    prefix = "https://www.linkedin.com/search/results/all/?keywords=",
    suffix = ""
  }
}     

]]

-- WebSearch as a special dictionary
local ReaderWebSearch = ReaderDictionary:extend{
    -- identify itself
    is_websearch = true,
}
  
function ReaderWebSearch:getWebSearchSiteTitle(websearchsite)
    return websearchsites[websearchsite].title
end

function ReaderWebSearch:getWebSearchPrefixAddress(websearchsite)
    return websearchsites[websearchsite].prefix
end

function ReaderWebSearch:getWebSearchSuffixAddress(websearchsite)
    return websearchsites[websearchsite].suffix
end

function ReaderWebSearch:getWebSearchFormat(websearchsite)
    return websearchsites[websearchsite].format
end

function ReaderWebSearch:isWebSearchSiteActive(websearchsite)
    return active_websearchsites[websearchsite]
end

function ReaderWebSearch:toggleWebSearchSiteActive(websearchsite)
    active_websearchsites[websearchsite] = not(active_websearchsites[websearchsite])
    websearchsites[websearchsite].active = not (websearchsites[websearchsite].active)
    G_reader_settings:saveSetting("websearchsites", websearchsites)
end

function ReaderWebSearch:isWebSearchSiteDefault(websearchsite)
    return (default_websearchsite == websearchsite)
end

function ReaderWebSearch:setWebSearchSiteDefault(websearchsite)
    default_websearchsite = websearchsite
    G_reader_settings:saveSetting("default_websearchsite", default_websearchsite)
    logger.info("... to:", default_websearchsite )
end

function ReaderWebSearch:getWebSearchSiteDefault()
    return default_websearchsite
end

function ReaderWebSearch:init()
    -- Initialize list of search sites
    
    saved_websearchsites = G_reader_settings:readSetting("websearchsites")
    
    if (not saved_websearchsites) then
      saved_websearchsites = {
        [1] = {
            ["active"] = true,
            ["prefix"] = "https://duckduckgo.com/?q=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "DuckduckGo",
        },
        [2] = {
            ["active"] = true,
            ["prefix"] = "'https://www.google.com/search?q='",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "Google (EN)",
        },
        [3] = {
            ["active"] = false,
            ["prefix"] = "'https://www.google.com/search?q='",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "Google (FR)",
        },
        [4] = {
            ["active"] = true,
            ["prefix"] = "https://www.linkedin.com/search/results/all/?keywords=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "LinkedIn",
        },
        [5] = {
            ["active"] = false,
            ["prefix"] = "https://archive.org/search.php?query=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "Internet Archive",
        },
        [6] = {
            ["active"] = true,
            ["prefix"] = "https://www.qwant.com/?q=",
            ["suffix"] = "&t=web",
            ["format"] = "UrlEncode",
            ["title"] = "Qwant",
        },
        [7] = {
            ["active"] = true,
            ["prefix"] = "https://medium.com/search?q=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "Medium",
        },
        [8] = {
            ["active"] = true,
            ["prefix"] = "https://monoskop.org/index.php?search=",
            ["suffix"] = "&title=Special%3ASearch&go=⏎",
            ["format"] = "CleanSelection",
            ["title"] = "Monoskop",
        },
        [9] = {
            ["active"] = true,
            ["prefix"] = "https://openlibrary.org/search?q=",
            ["suffix"] = "&mode=ebooks&has_fulltext=true",
            ["format"] = "UrlEncode",
            ["title"] = "Open Library",
        },
        [10] = {
            ["active"] = true,
            ["prefix"] = "https://www.researchgate.net/search.Search.html?type=researcher&query=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "ResearchGate",
        },
        [11] = {
            ["active"] = true,
            ["prefix"] = "https://fr.wikisource.org/w/index.php?search=",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "Wikisource",
        },
        [12] = {
            ["active"] = true,
            ["prefix"] = "https://book4you.org/s/",
            ["suffix"] = "",
            ["format"] = "UrlEncode",
            ["title"] = "ZLibrary",
        }
      }
      G_reader_settings:saveSetting("websearchsites", websearchsites)
    end
        
    title_table = {}
    for websearchsite, websitedetails in pairs (saved_websearchsites) do
        table.insert(title_table, websitedetails.title)
    end
    table.sort(title_table)

    websearchsites= {}
    for _, atitle in pairs(title_table) do
      for _, websearchsite in pairs(saved_websearchsites) do
        if (atitle == websearchsite.title) then
          table.insert(websearchsites, websearchsite)
        end
      end
    end

    logger.info("Ordered Web Search Sites:", websearchsites)
    
    active_websearchsites = {}
    for website, data in pairs (websearchsites) do
    --  table.insert(self.websearchsitetitles, data.title)
      active_websearchsites[website] = data.active
    end
    
    default_websearchsite = G_reader_settings:readSetting("default_websearchsite")
    
    if not default_websearchsite then 
        default_websearchsite = 1
        G_reader_settings:saveSetting("default_websearchsite", default_websearchsite)
    end
    
    self.ui.menu:registerToMainMenu(self)
end

function ReaderWebSearch:genActiveWebSearchSubItem(websearchsite)
    return {
        text = self:getWebSearchSiteTitle(websearchsite), 
        checked_func = function()
            return ReaderWebSearch:isWebSearchSiteActive(websearchsite)
        end,
        callback = function()
            ReaderWebSearch:toggleWebSearchSiteActive(websearchsite)
        end
    }
end

function ReaderWebSearch:genDefaultWebSearchSubItem(websearchsite)
    return {
        text = self:getWebSearchSiteTitle(websearchsite), 
        checked_func = function()
            return (self:isWebSearchSiteDefault(websearchsite))
        end,
        callback = function()
            self:setWebSearchSiteDefault(websearchsite)
        end
    }
end

function ReaderWebSearch:addToMainMenu(menu_items)
    sub_item_table_websearch = {}
    sub_item_table_defaultwebsearch = {}
    
    for websearchsite, websitedetails in pairs (websearchsites) do
      table.insert(sub_item_table_websearch, self:genActiveWebSearchSubItem(websearchsite))
      table.insert(sub_item_table_defaultwebsearch, self:genDefaultWebSearchSubItem(websearchsite))
    end
    
    menu_items.websearch = {
      text = _("Select active web search sites"),
      sub_item_table = sub_item_table_websearch
    }
    
    menu_items.defaultwebsearch = {
        text = _("Select default Web Search Site"),
        sub_item_table = sub_item_table_defaultwebsearch
    }
 end

function ReaderWebSearch:selectWebSearchSite(text)
    websearchsite_buttons ={}

    for websearchsite, websitedetails in pairs (websearchsites) do
        if (active_websearchsites[websearchsite] == true) then
            button =  { {
                      text = self:getWebSearchSiteTitle(websearchsite),
                      callback = function()
                          ReaderWebSearch = require("apps/reader/modules/readerwebsearch")
                          if (ReaderWebSearch:getWebSearchFormat(websearchsite)=="UrlEncode")
                            then text = util.urlEncode(text)
                          elseif (ReaderWebSearch:getWebSearchFormat(websearchsite)=="CleanSlection")
                            then text = ReaderDictionary:cleanSelection(text, false)
                          end
                          search_link = ReaderWebSearch:getWebSearchPrefixAddress(websearchsite)..text
                          if (ReaderWebSearch:getWebSearchSuffixAddress(websearchsite)~='')
                            then search_link = search_link..ReaderWebSearch:getWebSearchSuffixAddress(websearchsite)
                          end
                          Device = require("device")
                          Device:openLink(search_link)
                          UIManager:close(self.selectWebSearchSite_input)
                          return
                      end,
                } }
            table.insert(websearchsite_buttons, button)
        end
    end
              
    local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
    self.selectWebSearchSite_input = ButtonDialogTitle:new{
        title = "Select Web Search Site:",
        title_align = "center",
        buttons = websearchsite_buttons ,
    }
    UIManager:show(self.selectWebSearchSite_input)
end

return ReaderWebSearch


