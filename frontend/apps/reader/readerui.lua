local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("ui/device")
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
    self[1] = ReaderView:new{
        dialog = self.dialog,
        dimen = self.dimen,
        ui = self,
        document = self.document,
    }
    -- reader menu controller
    -- hold reference to menu widget
    self.menu = ReaderMenu:new{
        view = self[1],
        ui = self
    }
    -- link
    table.insert(self, ReaderLink:new{
        dialog = self.dialog,
        view = self[1],
        ui = self,
        document = self.document,
    })
    -- text highlight
    table.insert(self, ReaderHighlight:new{
        dialog = self.dialog,
        view = self[1],
        ui = self,
        document = self.document,
    })
    -- menu widget should be registered after link widget and highlight widget
    -- so that taps on link and highlight areas won't popup reader menu
    table.insert(self, self.menu)
    -- rotation controller
    table.insert(self, ReaderRotation:new{
        dialog = self.dialog,
        view = self[1],
        ui = self
    })
    -- Table of content controller
    -- hold reference to bm widget
    self.toc = ReaderToc:new{
        dialog = self.dialog,
        view = self[1],
        ui = self
    }
    table.insert(self, self.toc)
    -- bookmark controller
    table.insert(self, ReaderBookmark:new{
        dialog = self.dialog,
        view = self[1],
        ui = self
    })
    -- reader goto controller
    table.insert(self, ReaderGoto:new{
        dialog = self.dialog,
        view = self[1],
        ui = self,
        document = self.document,
    })
    -- dictionary
    table.insert(self, ReaderDictionary:new{
        dialog = self.dialog,
        view = self[1],
        ui = self,
        document = self.document,
    })
    -- wikipedia
    table.insert(self, ReaderWikipedia:new{
        dialog = self.dialog,
        view = self[1],
        ui = self,
        document = self.document,
    })
    -- screenshot controller
    table.insert(self.active_widgets, ReaderScreenshot:new{
        dialog = self.dialog,
        view = self[1],
        ui = self
    })
    -- frontlight controller
    if Device:hasFrontlight() then
        table.insert(self, ReaderFrontLight:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
    end
    -- configuable controller
    if self.document.info.configurable then
        -- config panel controller
        table.insert(self, ReaderConfig:new{
            configurable = self.document.configurable,
            options = self.document.options,
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
        if not self.document.info.has_pages then
            -- cre option controller
            table.insert(self, ReaderCoptListener:new{
                dialog = self.dialog,
                view = self[1],
                ui = self,
                document = self.document,
            })
        end
    end
    -- for page specific controller
    if self.document.info.has_pages then
        -- cropping controller
        table.insert(self, ReaderCropping:new{
            dialog = self.dialog,
            view = self[1],
            ui = self,
            document = self.document,
        })
        -- paging controller
        table.insert(self, ReaderPaging:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
        -- zooming controller
        local zoom = ReaderZooming:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        }
        table.insert(self, zoom)
        -- panning controller
        table.insert(self, ReaderPanning:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
        -- hinting controller
        table.insert(self, ReaderHinting:new{
            dialog = self.dialog,
            zoom = zoom,
            view = self[1],
            ui = self,
            document = self.document,
        })
    else
        -- make sure we load document first before calling any callback
        table.insert(self.postInitCallback, function()
            self.document:loadDocument()
        end)
        -- typeset controller
        table.insert(self, ReaderTypeset:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
        -- font menu
        self.font = ReaderFont:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        }
        table.insert(self, self.font) -- hold reference to font menu
        -- hyphenation menu
        self.hyphenation = ReaderHyphenation:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        }
        table.insert(self, self.hyphenation) -- hold reference to hyphenation menu
        -- rolling controller
        table.insert(self, ReaderRolling:new{
            dialog = self.dialog,
            view = self[1],
            ui = self
        })
    end
    -- configuable controller
    if self.document.info.configurable then
        if self.document.info.has_pages then
            -- kopt option controller
            table.insert(self, ReaderKoptListener:new{
                dialog = self.dialog,
                view = self[1],
                ui = self,
                document = self.document,
            })
        end
        -- activity indicator
        table.insert(self, ReaderActivityIndicator:new{
            dialog = self.dialog,
            view = self[1],
            ui = self,
            document = self.document,
        })
    end

    -- koreader plugins
    for _,module in ipairs(PluginLoader:loadPlugins()) do
        DEBUG("Loaded plugin", module.path)
        table.insert(self, module:new{
            dialog = self.dialog,
            view = self[1],
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
