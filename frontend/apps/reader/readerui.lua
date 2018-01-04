--[[
ReaderUI is an abstraction for a reader interface.

It works using data gathered from a document interface.
]]--

local Cache = require("cache")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local PluginLoader = require("pluginloader")
local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
local ReaderCropping = require("apps/reader/modules/readercropping")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderFont = require("apps/reader/modules/readerfont")
local ReaderFrontLight = require("apps/reader/modules/readerfrontlight")
local ReaderGoto = require("apps/reader/modules/readergoto")
local ReaderHinting = require("apps/reader/modules/readerhinting")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderHyphenation = require("apps/reader/modules/readerhyphenation")
local ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local ReaderRotation = require("apps/reader/modules/readerrotation")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderStatus = require("apps/reader/modules/readerstatus")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local Screenshoter = require("ui/widget/screenshoter")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local ReaderUI = InputContainer:new{
    name = "ReaderUI",

    key_events = {
        Close = { { "Home" },
            doc = "close document", event = "Close" },
    },
    active_widgets = {},

    -- if we have a parent container, it must be referenced for now
    dialog = nil,

    -- the document interface
    document = nil,

    -- password for document unlock
    password = nil,

    postInitCallback = nil,
    postReaderCallback = nil,
}

function ReaderUI:registerModule(name, ui_module, always_active)
    if name then self[name] = ui_module end
    ui_module.name = "reader" .. name
    table.insert(always_active and self.active_widgets or self, ui_module)
end

function ReaderUI:registerPostInitCallback(callback)
    table.insert(self.postInitCallback, callback)
end

function ReaderUI:registerPostReadyCallback(callback)
    table.insert(self.postReaderCallback, callback)
end

function ReaderUI:init()
    -- cap screen refresh on pan to 2 refreshes per second
    local pan_rate = Screen.eink and 2.0 or 30.0

    self.postInitCallback = {}
    self.postReaderCallback = {}
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
            pan_rate = pan_rate,
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
            if not self.document:loadDocument() then
                self:dealWithLoadDocumentFailure()
            end

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
            pan_rate = pan_rate,
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
    -- book info
    self:registerModule("bookinfo", FileManagerBookInfo:new{
        dialog = self.dialog,
        document = self.document,
        ui = self,
    })
    -- koreader plugins
    for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
        local ok, plugin_or_err = PluginLoader:createPluginInstance(
            plugin_module,
            {
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        if ok then
            self:registerModule(plugin_module.name, plugin_or_err)
            logger.info("RD loaded plugin", plugin_module.name,
                        "at", plugin_module.path)
        end
    end

    -- we only read settings after all the widgets are initialized
    self:handleEvent(Event:new("ReadSettings", self.doc_settings))

    for _,v in ipairs(self.postInitCallback) do
        v()
    end
    self.postInitCallback = nil

    -- Now that document is loaded, store book metadata in settings
    -- (so that filemanager can use it from sideCar file to display
    -- Book information).
    self.doc_settings:saveSetting("doc_props", self.document:getProps())

    -- After initialisation notify that document is loaded and rendered
    -- CREngine only reports correct page count after rendering is done
    -- Need the same event for PDF document
    self:handleEvent(Event:new("ReaderReady", self.doc_settings))

    for _,v in ipairs(self.postReaderCallback) do
        v()
    end
    self.postReaderCallback = nil
end

function ReaderUI:showFileManager()
    local FileManager = require("apps/filemanager/filemanager")
    local QuickStart = require("ui/quickstart")
    local last_dir
    local last_file = G_reader_settings:readSetting("lastfile")
    -- ignore quickstart guide as last_file so we can go back to home dir
    if last_file and last_file ~= QuickStart.quickstart_filename then
        last_dir = last_file:match("(.*)/")
    end
    if FileManager.instance then
        FileManager.instance:reinit(last_dir, last_file)
    else
        FileManager:showFiles(last_dir, last_file)
    end
end

function ReaderUI:showReader(file)
    logger.dbg("show reader ui")
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
        logger.dbg("creating coroutine for showing reader")
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
    logger.info("opening file", file)
    -- keep only one instance running
    if _running_instance then
        _running_instance:onClose()
    end
    local document = DocumentRegistry:openDocument(file)
    if not document then
        UIManager:show(InfoMessage:new{
            text = _("No reader engine for this file or invalid file.")
        })
        self:showFileManager()
        return
    end
    if document.is_locked then
        logger.info("document is locked")
        self._coroutine = coroutine.running() or self._coroutine
        self:unlockDocumentWithPassword(document)
        if coroutine.running() then
            local unlock_success = coroutine.yield()
            if not unlock_success then
                self:showFileManager()
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
    logger.dbg("show input password dialog")
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
                ok_text = _("Save"),
                cancel_text = _("Don't save"),
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
    logger.dbg("closing reader")
    -- if self.dialog is us, we'll have our onFlushSettings() called
    -- by UIManager:close() below, so avoid double save
    if self.dialog ~= self then
        self:saveSettings()
    end
    if self.document ~= nil then
        logger.dbg("closing document")
        self:notifyCloseDocument()
    end
    UIManager:close(self.dialog, "full")
    -- serialize last used items for later launch
    Cache:serialize()
    if _running_instance == self then
        _running_instance = nil
    end
end

function ReaderUI:dealWithLoadDocumentFailure()
    -- Sadly, we had to delay loadDocument() to about now, so we only
    -- know now this document is not valid or recognized.
    -- We can't do much more than crash properly here (still better than
    -- going on and segfaulting when calling other methods on unitiliazed
    -- _document)
    -- We must still remove it from lastfile and history (as it has
    -- already been added there) so that koreader don't crash again
    -- at next launch...
    local readhistory = require("readhistory")
    readhistory:removeItemByPath(self.document.file)
    if G_reader_settings:readSetting("lastfile") == self.document.file then
        G_reader_settings:saveSetting("lastfile", #readhistory.hist > 0 and readhistory.hist[1].file or nil)
    end
    -- As we are in a coroutine, we can pause and show an InfoMessage before exiting
    local _coroutine = coroutine.running()
    if coroutine then
        logger.warn("crengine failed recognizing or parsing this file: unsupported or invalid document")
        UIManager:show(InfoMessage:new{
            text = _("Failed recognizing or parsing this file: unsupported or invalid document.\nKOReader will exit now."),
            dismiss_callback = function()
                coroutine.resume(_coroutine, false)
            end,
        })
        coroutine.yield() -- pause till InfoMessage is dismissed
    end
    -- We have to error and exit the coroutine anyway to avoid any segfault
    error("crengine failed recognizing or parsing this file: unsupported or invalid document")
end

return ReaderUI
