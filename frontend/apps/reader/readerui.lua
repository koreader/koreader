local InputContainer = require("ui/widget/container/inputcontainer")
local DocumentRegistry = require("document/documentregistry")
local Screenshoter = require("ui/widget/screenshoter")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = require("device").screen
local Event = require("ui/event")
local Cache = require("cache")
local dbg = require("dbg")
local T = require("ffi/util").template
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
local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderHyphenation = require("apps/reader/modules/readerhyphenation")
local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReaderStatus = require("apps/reader/modules/readerstatus")
local PluginLoader = require("apps/reader/pluginloader")

--[[
This is an abstraction for a reader interface

it works using data gathered from a document interface
]]--

local ReaderUI = InputContainer:new{
    name = "ReaderUI",

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

function ReaderUI:registerModule(name, ui_module, always_active)
    if name then self[name] = ui_module end
    ui_module.name = "reader" .. name
    table.insert(always_active and self.active_widgets or self, ui_module)
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
    -- all paintable widgets need to be a child of reader view
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
    self:registerModule("screenshot", Screenshoter:new{
        prefix = 'Reader',
        dialog = self.dialog,
        view = self.view,
        ui = self
    }, true)
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
            self.document:loadDocument()

            -- used to read additional settings after the document has been
            -- loaded (but not rendered yet)
            self:handleEvent(Event:new("PreRenderDocument", self.doc_settings))

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
        self.disable_double_tap = G_reader_settings:readSetting("disable_double_tap") ~= false
    end
    -- fulltext search
    self:registerModule("search", ReaderSearch:new{
        dialog = self.dialog,
        view = self.view,
        ui = self
    })
    -- book status
    self:registerModule("status", ReaderStatus:new{
        ui = self,
        document = self.document,
        view = self.view,
    })
    -- history view
    self:registerModule("history", FileManagerHistory:new{
        dialog = self.dialog,
        ui = self,
    })
    -- koreader plugins
    for _,plugin_module in ipairs(PluginLoader:loadPlugins()) do
        dbg("Loaded plugin", plugin_module.name, "at", plugin_module.path)
        self:registerModule(plugin_module.name, plugin_module:new{
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
        })
    end

    -- we only read settings after all the widgets are initialized
    self:handleEvent(Event:new("ReadSettings", self.doc_settings))

    for _,v in ipairs(self.postInitCallback) do
        v()
    end

    -- After initialisation notify that document is loaded and rendered
    -- CREngine only reports correct page count after rendering is done
    -- Need the same event for PDF document
    self:handleEvent(Event:new("ReaderReady", self.doc_settings))
end

function ReaderUI:showReader(file)
    dbg("show reader ui")
    require("readhistory"):addItem(file)
    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
             text = T(_("File '%1' does not exist."), file)
        })
        return
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Opening file '%1'."), file),
        timeout = 0.0,
    })
    -- doShowReader might block for a long time, so force repaint here
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        dbg("creating coroutine for showing reader")
        local co = coroutine.create(function()
            self:doShowReader(file)
        end)
        local ok, err = coroutine.resume(co)
        if err ~= nil or ok == false then
            io.stderr:write('[!] doShowReader coroutine crashed:\n')
            io.stderr:write(debug.traceback(co, err, 1))
            UIManager:quit()
        end
    end)
end

local _running_instance = nil
function ReaderUI:doShowReader(file)
    dbg("opening file", file)
    -- keep only one instance running
    if _running_instance then
        _running_instance:onClose()
    end
    local document = DocumentRegistry:openDocument(file)
    if not document then
        UIManager:show(InfoMessage:new{
            text = _("No reader engine for this file.")
        })
        return
    end
    if document.is_locked then
        dbg("document is locked")
        self._coroutine = coroutine.running() or self._coroutine
        self:unlockDocumentWithPassword(document)
        if coroutine.running() then
            local unlock_success = coroutine.yield()
            if not unlock_success then
                return
            end
        end
    end

    G_reader_settings:saveSetting("lastfile", file)
    local reader = ReaderUI:new{
        dimen = Screen:getSize(),
        document = document,
    }
    UIManager:show(reader)
    _running_instance = reader
end

function ReaderUI:_getRunningInstance()
    return _running_instance
end

function ReaderUI:unlockDocumentWithPassword(document, try_again)
    dbg("show input password dialog")
    self.password_dialog = InputDialog:new{
        title = try_again and _("Password is incorrect, try again?")
            or _("Input document password"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:closeDialog()
                        coroutine.resume(self._coroutine)
                    end,
                },
                {
                    text = _("OK"),
                    enabled = true,
                    callback = function()
                        local success = self:onVerifyPassword(document)
                        self:closeDialog()
                        if success then
                            coroutine.resume(self._coroutine, success)
                        else
                            self:unlockDocumentWithPassword(document, true)
                        end
                    end,
                },
            },
        },
        text_type = "password",
    }
    self.password_dialog:onShowKeyboard()
    UIManager:show(self.password_dialog)
end

function ReaderUI:onVerifyPassword(document)
    local password = self.password_dialog:getInputText()
    return document:unlock(password)
end

function ReaderUI:closeDialog()
    self.password_dialog:onClose()
    UIManager:close(self.password_dialog)
end

function ReaderUI:onScreenResize(dimen)
    self.dimen = dimen
    self:updateTouchZonesOnScreenResize(dimen)
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

function ReaderUI:notifyCloseDocument()
    self:handleEvent(Event:new("CloseDocument"))
    if self.document:isEdited() then
        local setting = G_reader_settings:readSetting("save_document")
        if setting == "always" then
            self:closeDocument()
        elseif setting == "disable" then
            self.document:discardChange()
            self:closeDocument()
        else
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
        end
    else
        self:closeDocument()
    end
end

function ReaderUI:onClose()
    dbg("closing reader")
    self:saveSettings()
    if self.document ~= nil then
        dbg("closing document")
        self:notifyCloseDocument()
    end
    UIManager:close(self.dialog, "full")
    -- serialize last used items for later launch
    Cache:serialize()
    if _running_instance == self then
        _running_instance = nil
    end
    return true
end

return ReaderUI
