local InputContainer = require("ui/widget/container/inputcontainer")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("ui/device")
local Screen = require("ui/screen")
local Event = require("ui/event")
local Cache = require("cache")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderView = require("apps/reader/modules/readerview")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local ReaderRotation = require("apps/reader/modules/readerrotation")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderFont = require("apps/reader/modules/readerfont")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderGoto = require("apps/reader/modules/readergoto")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderCropping = require("apps/reader/modules/readercropping")
local ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
local ReaderHinting = require("apps/reader/modules/readerhinting")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderScreenshot = require("apps/reader/modules/readerscreenshot")
local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderHyphenation = require("apps/reader/modules/readerhyphenation")
local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")
local ReaderLink = require("apps/reader/modules/readerlink")
local PluginLoader = require("apps/reader/pluginloader")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")

--[[
This is an abstraction for a reader interface

it works using data gathered from a document interface
]]--

local ReaderUI = InputContainer:new{
    key_events = {
        Close = { { "Home" },
            doc = "close document", event = "Close" },
    },
    active_widgets = {},

    -- our own size
    dimen = Geom:new{ w = 400, h = 600 },
    -- if we have a parent container, it must be referenced for now
    dialog = nil,

    -- the document interface
    document = nil,

    -- password for document unlock
    password = nil,

    postInitCallback = nil,
}

function ReaderUI:registerModule(name, module, always_active)
    if name then self[name] = module end
    table.insert(always_active and self.active_widgets or self, module)
end

function ReaderUI:registerPostInitCallback(callback)
    table.insert(self.postInitCallback, callback)
end

function ReaderUI:init()
    self.postInitCallback = {}
    -- if we are not the top level dialog ourselves, it must be given in the table
    if not self.dialog then
        self.dialog = self
    end

    if Device:hasKeys() then
        self.key_events.Back = {
            { "Back" }, doc = "close document",
            event = "Close" }
    end

    self.doc_settings = DocSettings:open(self.document.file)

    -- a view container (so it must be child #1!)
    self:registerModule("view", ReaderView:new{
        dialog = self.dialog,
        dimen = self.dimen,
        ui = self,
        document = self.document,
    })
    -- goto link controller
    self:registerModule("link", ReaderLink:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- text highlight
    self:registerModule("highlight", ReaderHighlight:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- menu widget should be registered after link widget and highlight widget
    -- so that taps on link and highlight areas won't popup reader menu
    -- reader menu controller
    self:registerModule("menu", ReaderMenu:new{
        view = self.view,
        ui = self
    })
    -- rotation controller
    self:registerModule("rotation", ReaderRotation:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- Table of content controller
    self:registerModule("toc", ReaderToc:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- bookmark controller
    self:registerModule("bookmark", ReaderBookmark:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- reader goto controller
    -- "goto" being a dirty keyword in Lua?
    self:registerModule("gotopage", ReaderGoto:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- dictionary
    self:registerModule("dictionary", ReaderDictionary:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- wikipedia
    self:registerModule("wikipedia", ReaderWikipedia:new{
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
    })
    -- screenshot controller
    self:registerModule("screenshot", ReaderScreenshot:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    }, true)
    -- history view
    self:registerModule("history", FileManagerHistory:new{
        dialog = self.dialog,
        menu = self.menu,
        ui = self,
    })
    -- frontlight controller
    if Device:hasFrontlight() then
        self:registerModule("frontlight", ReaderFrontLight:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
    end
    -- configuable controller
    if self.document.info.configurable then
        -- config panel controller
        self:registerModule("config", ReaderConfig:new{
            configurable = self.document.configurable,
            options = self.document.options,
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        if self.document.info.has_pages then
            -- kopt option controller
            self:registerModule("koptlistener", ReaderKoptListener:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        else
            -- cre option controller
            self:registerModule("crelistener", ReaderCoptListener:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        end
        -- activity indicator when some configurations take long take to affect
        self:registerModule("activityindicator", ReaderActivityIndicator:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
    end
    -- for page specific controller
    if self.document.info.has_pages then
        -- cropping controller
        self:registerModule("cropping", ReaderCropping:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
        -- paging controller
        self:registerModule("paging", ReaderPaging:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- zooming controller
        self:registerModule("zooming", ReaderZooming:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- panning controller
        self:registerModule("panning", ReaderPanning:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- hinting controller
        self:registerModule("hinting", ReaderHinting:new{
            dialog = self.dialog,
            zoom = self.zooming,
            view = self.view,
            ui = self,
            document = self.document,
        })
    else
        -- make sure we render document first before calling any callback
        self:registerPostInitCallback(function()
            self.document:render()
        end)
        -- typeset controller
        self:registerModule("typeset", ReaderTypeset:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- font menu
        self:registerModule("font", ReaderFont:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- hyphenation menu
        self:registerModule("hyphenation", ReaderHyphenation:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- rolling controller
        self:registerModule("rolling", ReaderRolling:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
    end

    -- koreader plugins
    for _,module in ipairs(PluginLoader:loadPlugins()) do
        DEBUG("Loaded plugin", module.name, "at", module.path)
        self:registerModule(module.name, module:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
    end

    --DEBUG(self.doc_settings)
    -- we only read settings after all the widgets are initialized
    self:handleEvent(Event:new("ReadSettings", self.doc_settings))

    for _,v in ipairs(self.postInitCallback) do
        v()
    end
end

function ReaderUI:showReader(file)
    DEBUG("show reader ui")
    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
             text = _("File ") .. file .. _(" does not exist")
        })
        return
    end
    UIManager:show(InfoMessage:new{
        text = _("Opening file ") .. file,
        timeout = 1,
    })
    UIManager:scheduleIn(0.1, function() self:doShowReader(file) end)
end

function ReaderUI:doShowReader(file)
    DEBUG("opening file", file)
    local document = DocumentRegistry:openDocument(file)
    if not document then
        UIManager:show(InfoMessage:new{
            text = _("No reader engine for this file")
        })
        return
    end

    G_reader_settings:saveSetting("lastfile", file)
    local reader = ReaderUI:new{
        dimen = Screen:getSize(),
        document = document,
    }
    UIManager:show(reader)
end

function ReaderUI:onSetDimensions(dimen)
    self.dimen = dimen
end

function ReaderUI:saveSettings()
    self:handleEvent(Event:new("SaveSettings"))
    self.doc_settings:flush()
    G_reader_settings:flush()
end

function ReaderUI:onFlushSettings()
    self:saveSettings()
    return true
end

function ReaderUI:closeDocument()
    self.document:close()
    self.document = nil
end

function ReaderUI:onCloseDocument()
    if self.document:isEdited() then
        UIManager:show(ConfirmBox:new{
            text = _("Do you want to save this document?"),
            ok_text = _("Yes"),
            cancel_text = _("No"),
            ok_callback = function()
                self:closeDocument()
            end,
            cancel_callback = function()
                self.document:discardChange()
                self:closeDocument()
            end,
        })
    else
        self:closeDocument()
    end
end

function ReaderUI:onClose()
    DEBUG("closing reader")
    self:saveSettings()
    if self.document ~= nil then
        DEBUG("closing document")
        self:onCloseDocument()
    end
    UIManager:close(self.dialog)
    -- serialize last used items for later launch
    Cache:serialize()
    return true
end

return ReaderUI
