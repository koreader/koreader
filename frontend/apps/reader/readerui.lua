--[[
ReaderUI is an abstraction for a reader interface.

It works using data gathered from a document interface.
]]--

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DeviceListener = require("device/devicelistener")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local PluginLoader = require("pluginloader")
local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")
local ReaderBack = require("apps/reader/modules/readerback")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
local ReaderCropping = require("apps/reader/modules/readercropping")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderFont = require("apps/reader/modules/readerfont")
local ReaderGoto = require("apps/reader/modules/readergoto")
local ReaderHinting = require("apps/reader/modules/readerhinting")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderScrolling = require("apps/reader/modules/readerscrolling")
local ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderPageMap = require("apps/reader/modules/readerpagemap")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local ReaderRotation = require("apps/reader/modules/readerrotation")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderStatus = require("apps/reader/modules/readerstatus")
local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderTypography = require("apps/reader/modules/readertypography")
local ReaderUserHyph = require("apps/reader/modules/readeruserhyph")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local Screenshoter = require("ui/widget/screenshoter")
local SettingsMigration = require("ui/data/settings_migration")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local ffiUtil  = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = ffiUtil.template

local ReaderUI = InputContainer:new{
    name = "ReaderUI",
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
    table.insert(self, ui_module)
    if always_active then
        -- to get events even when hidden
        table.insert(self.active_widgets, ui_module)
    end
end

function ReaderUI:registerPostInitCallback(callback)
    table.insert(self.postInitCallback, callback)
end

function ReaderUI:registerPostReadyCallback(callback)
    table.insert(self.postReaderCallback, callback)
end

function ReaderUI:init()
    -- cap screen refresh on pan to 2 refreshes per second
    local pan_rate = Screen.low_pan_rate and 2.0 or 30.0

    self.postInitCallback = {}
    self.postReaderCallback = {}
    -- if we are not the top level dialog ourselves, it must be given in the table
    if not self.dialog then
        self.dialog = self
    end

    self.doc_settings = DocSettings:open(self.document.file)
    -- Handle local settings migration
    SettingsMigration:migrateSettings(self.doc_settings)

    if Device:hasKeys() then
        self.key_events.Home = { {"Home"}, doc = "open file browser" }
    end

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
    -- device status controller
    self:registerModule("devicestatus", ReaderDeviceStatus:new{
        ui = self,
    })
    -- configurable controller
    if self.document.info.configurable then
        -- config panel controller
        self:registerModule("config", ReaderConfig:new{
            configurable = self.document.configurable,
            dialog = self.dialog,
            view = self.view,
            ui = self,
            document = self.document,
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
        -- activity indicator for when some settings take time to take effect (Kindle under KPV)
        if not ReaderActivityIndicator:isStub() then
            self:registerModule("activityindicator", ReaderActivityIndicator:new{
                dialog = self.dialog,
                view = self.view,
                ui = self,
                document = self.document,
            })
        end
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
            document = self.document,
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
        -- load crengine default settings (from cr3.ini, some of these
        -- will be overriden by our settings by some reader modules below)
        if self.document.setupDefaultView then
            self.document:setupDefaultView()
        end
        -- make sure we render document first before calling any callback
        self:registerPostInitCallback(function()
            local start_tv = TimeVal:now()
            if not self.document:loadDocument() then
                self:dealWithLoadDocumentFailure()
            end
            logger.dbg(string.format("  loading took %.3f seconds", TimeVal:getDuration(start_tv)))

            -- used to read additional settings after the document has been
            -- loaded (but not rendered yet)
            self:handleEvent(Event:new("PreRenderDocument", self.doc_settings))

            start_tv = TimeVal:now()
            self.document:render()
            logger.dbg(string.format("  rendering took %.3f seconds", TimeVal:getDuration(start_tv)))

            -- Uncomment to output the built DOM (for debugging)
            -- logger.dbg(self.document:getHTMLFromXPointer(".0", 0x6830))
        end)
        -- styletweak controller (must be before typeset controller)
        self:registerModule("styletweak", ReaderStyleTweak:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
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
        -- user hyphenation (must be registered before typography)
        self:registerModule("userhyph", ReaderUserHyph:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
        -- typography menu (replaces previous hyphenation menu / ReaderHyphenation)
        self:registerModule("typography", ReaderTypography:new{
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
        -- pagemap controller
        self:registerModule("pagemap", ReaderPageMap:new{
            dialog = self.dialog,
            view = self.view,
            ui = self
        })
    end
    self.disable_double_tap = G_reader_settings:nilOrTrue("disable_double_tap")
    -- scrolling (scroll settings + inertial scrolling)
    self:registerModule("scrolling", ReaderScrolling:new{
        pan_rate = pan_rate,
        dialog = self.dialog,
        ui = self,
        view = self.view,
    })
    -- back location stack
    self:registerModule("back", ReaderBack:new{
        ui = self,
        view = self.view,
    })
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
    -- file searcher
    self:registerModule("filesearcher", FileManagerFileSearcher:new{
        dialog = self.dialog,
        ui = self,
    })
    -- folder shortcuts
    self:registerModule("folder_shortcuts", FileManagerShortcuts:new{
        dialog = self.dialog,
        ui = self,
    })
    -- history view
    self:registerModule("history", FileManagerHistory:new{
        dialog = self.dialog,
        ui = self,
    })
    -- collections/favorites view
    self:registerModule("collections", FileManagerCollection:new{
        dialog = self.dialog,
        ui = self,
    })
    -- book info
    self:registerModule("bookinfo", FileManagerBookInfo:new{
        dialog = self.dialog,
        document = self.document,
        ui = self,
    })
    -- event listener to change device settings
    self:registerModule("devicelistener", DeviceListener:new {
        document = self.document,
        view = self.view,
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

    if Device:hasWifiToggle() then
        local NetworkListener = require("ui/network/networklistener")
        self:registerModule("networklistener", NetworkListener:new {
            document = self.document,
            view = self.view,
            ui = self,
        })
    end

    -- Allow others to change settings based on external factors
    -- Must be called after plugins are loaded & before setting are read.
    self:handleEvent(Event:new("DocSettingsLoad", self.doc_settings, self.document))
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

    -- print("Ordered registered gestures:")
    -- for _, tzone in ipairs(self._ordered_touch_zones) do
    --     print("  "..tzone.def.id)
    -- end

    if ReaderUI.instance == nil then
        logger.dbg("Spinning up new ReaderUI instance", tostring(self))
    else
        -- Should never happen, given what we did in (do)showReader...
        logger.err("ReaderUI instance mismatch! Opened", tostring(self), "while we still have an existing instance:", tostring(ReaderUI.instance), debug.traceback())
    end
    ReaderUI.instance = self
end

function ReaderUI:setLastDirForFileBrowser(dir)
    if dir and #dir > 1 and dir:sub(-1) == "/" then
        dir = dir:sub(1, -2)
    end
    self.last_dir_for_file_browser = dir
end

function ReaderUI:getLastDirFile(to_file_browser)
    if to_file_browser and self.last_dir_for_file_browser then
        local dir = self.last_dir_for_file_browser
        self.last_dir_for_file_browser = nil
        return dir
    end
    local QuickStart = require("ui/quickstart")
    local last_dir
    local last_file = G_reader_settings:readSetting("lastfile")
    -- ignore quickstart guide as last_file so we can go back to home dir
    if last_file and last_file ~= QuickStart.quickstart_filename then
        last_dir = last_file:match("(.*)/")
    end
    return last_dir, last_file
end

function ReaderUI:showFileManager(file)
    local FileManager = require("apps/filemanager/filemanager")

    local last_dir, last_file
    if file then
        last_dir, last_file = util.splitFilePathName(file)
        last_dir = last_dir:match("(.*)/")
    else
        last_dir, last_file = self:getLastDirFile(true)
    end
    if FileManager.instance then
        FileManager.instance:reinit(last_dir, last_file)
    else
        FileManager:showFiles(last_dir, last_file)
    end
end

function ReaderUI:onShowingReader()
    -- Allows us to optimize out a few useless refreshes in various CloseWidgets handlers...
    self.tearing_down = true
    self.dithered = nil

    -- Don't enforce a "full" refresh, leave that decision to the next widget we'll *show*.
    self:onClose(false)
end

-- Same as above, except we don't close it yet. Useful for plugins that need to close custom Menus before calling showReader.
function ReaderUI:onSetupShowReader()
    self.tearing_down = true
    self.dithered = nil
end

--- @note: Will sanely close existing FileManager/ReaderUI instance for you!
---        This is the *only* safe way to instantiate a new ReaderUI instance!
---        (i.e., don't look at the testsuite, which resorts to all kinds of nasty hacks).
function ReaderUI:showReader(file, provider)
    logger.dbg("show reader ui")

    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
             text = T(_("File '%1' does not exist."), BD.filepath(file))
        })
        return
    end

    if not DocumentRegistry:hasProvider(file) and provider == nil then
        UIManager:show(InfoMessage:new{
            text = T(_("File '%1' is not supported."), BD.filepath(file))
        })
        self:showFileManager(file)
        return
    end

    -- We can now signal the existing ReaderUI/FileManager instances that it's time to go bye-bye...
    UIManager:broadcastEvent(Event:new("ShowingReader"))

    -- prevent crash due to incompatible bookmarks
    --- @todo Split bookmarks from metadata and do per-engine in conversion.
    provider = provider or DocumentRegistry:getProvider(file)
    if provider.provider then
        local doc_settings = DocSettings:open(file)
        local bookmarks = doc_settings:readSetting("bookmarks") or {}
        if #bookmarks >= 1 and
           ((provider.provider == "crengine" and type(bookmarks[1].page) == "number") or
            (provider.provider == "mupdf" and type(bookmarks[1].page) == "string")) then
                UIManager:show(ConfirmBox:new{
                    text = T(_("The document '%1' with bookmarks or highlights was previously opened with a different engine. To prevent issues, bookmarks need to be deleted before continuing."),
                        BD.filepath(file)),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        doc_settings:delSetting("bookmarks")
                        doc_settings:close()
                        self:showReaderCoroutine(file, provider)
                    end,
                    cancel_callback = function() self:showFileManager() end,
                })
        else
            self:showReaderCoroutine(file, provider)
        end
    end
end

function ReaderUI:showReaderCoroutine(file, provider)
    UIManager:show(InfoMessage:new{
        text = T(_("Opening file '%1'."), BD.filepath(file)),
        timeout = 0.0,
    })
    -- doShowReader might block for a long time, so force repaint here
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        logger.dbg("creating coroutine for showing reader")
        local co = coroutine.create(function()
            self:doShowReader(file, provider)
        end)
        local ok, err = coroutine.resume(co)
        if err ~= nil or ok == false then
            io.stderr:write('[!] doShowReader coroutine crashed:\n')
            io.stderr:write(debug.traceback(co, err, 1))
            UIManager:show(InfoMessage:new{
                text = _("No reader engine for this file or invalid file.")
            })
            self:showFileManager()
        end
    end)
end

function ReaderUI:doShowReader(file, provider)
    logger.info("opening file", file)
    -- Only keep a single instance running
    if ReaderUI.instance then
        logger.warn("ReaderUI instance mismatch! Tried to spin up a new instance, while we still have an existing one:", tostring(ReaderUI.instance))
        ReaderUI.instance:onClose()
    end
    local document = DocumentRegistry:openDocument(file, provider)
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
    require("readhistory"):addItem(file) -- (will update "lastfile")
    local reader = ReaderUI:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        document = document,
    }

    local title = reader.document:getProps().title

    if title ~= "" then
        Screen:setWindowTitle(title)
    else
        local _, filename = util.splitFilePathName(file)
        Screen:setWindowTitle(filename)
    end
    Device:notifyBookState(title, document)

    -- This is mostly for the few callers that bypass the coroutine shenanigans and call doShowReader directly,
    -- instead of showReader...
    -- Otherwise, showReader will have taken care of that *before* instantiating a new RD,
    -- in order to ensure a sane ordering of plugins teardown -> instantiation.
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        FileManager.instance:onClose()
    end

    UIManager:show(reader, "full")
end

-- NOTE: The instance reference used to be stored in a private module variable, hence the getter method.
--       We've since aligned behavior with FileManager, which uses a class member instead,
--       but kept the function to avoid changing existing code.
function ReaderUI:_getRunningInstance()
    return ReaderUI.instance
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
    UIManager:show(self.password_dialog)
    self.password_dialog:onShowKeyboard()
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

function ReaderUI:onClose(full_refresh)
    logger.dbg("closing reader")
    PluginLoader:finalize()
    Device:notifyBookState(nil, nil)
    if full_refresh == nil then
        full_refresh = true
    end
    -- if self.dialog is us, we'll have our onFlushSettings() called
    -- by UIManager:close() below, so avoid double save
    if self.dialog ~= self then
        self:saveSettings()
    end
    -- Serialize the most recently displayed page for later launch
    DocCache:serialize()
    if self.document ~= nil then
        logger.dbg("closing document")
        self:notifyCloseDocument()
    end
    UIManager:close(self.dialog, full_refresh and "full")
end

function ReaderUI:onCloseWidget()
    if ReaderUI.instance == self then
        logger.dbg("Tearing down ReaderUI", tostring(self))
    else
        logger.warn("ReaderUI instance mismatch! Closed", tostring(self), "while the active one is supposed to be", tostring(ReaderUI.instance))
    end
    ReaderUI.instance = nil
    self._coroutine = nil
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
    require("readhistory"):removeItemByPath(self.document.file) -- (will update "lastfile")
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

function ReaderUI:onHome()
    self:onClose()
    self:showFileManager()
    return true
end

function ReaderUI:reloadDocument(after_close_callback)
    local file = self.document.file
    local provider = getmetatable(self.document).__index

    -- Mimic onShowingReader's refresh optimizations
    self.tearing_down = true
    self.dithered = nil

    self:handleEvent(Event:new("CloseReaderMenu"))
    self:handleEvent(Event:new("CloseConfigMenu"))
    self.highlight:onClose() -- close highlight dialog if any
    self:onClose(false)
    if after_close_callback then
        -- allow caller to do stuff between close an re-open
        after_close_callback(file, provider)
    end

    self:showReader(file, provider)
end

function ReaderUI:switchDocument(new_file)
    if not new_file then return end

    -- Mimic onShowingReader's refresh optimizations
    self.tearing_down = true
    self.dithered = nil

    self:handleEvent(Event:new("CloseReaderMenu"))
    self:handleEvent(Event:new("CloseConfigMenu"))
    self.highlight:onClose() -- close highlight dialog if any
    self:onClose(false)

    self:showReader(new_file)
end

function ReaderUI:onOpenLastDoc()
    self:switchDocument(self.menu:getPreviousFile())
end

function ReaderUI:getCurrentPage()
    if self.document.info.has_pages then
        return self.paging.current_page
    else
        return self.document:getCurrentPage()
    end
end

return ReaderUI
