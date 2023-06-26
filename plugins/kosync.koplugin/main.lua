local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Math = require("optmath")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local random = require("random")
local util = require("util")
local T = require("ffi/util").template
local _ = require("gettext")

if G_reader_settings:hasNot("device_id") then
    G_reader_settings:saveSetting("device_id", random.uuid())
end

local KOSync = WidgetContainer:extend{
    name = "kosync",
    is_doc_only = true,
    title = _("Register/login to KOReader server"),

    page_update_counter = nil,
    last_page = nil,
    last_page_turn_timestamp = nil,
    periodic_push_scheduled = nil,
    _menu_to_update = nil,
}

local SYNC_STRATEGY = {
    -- Forward and backward whisper sync settings are using different
    -- default value, so none of following opinions should be zero.
    PROMPT = 1,
    WHISPER = 2,
    DISABLE = 3,

    DEFAULT_FORWARD = 1,
    DEFAULT_BACKWARD = 3,
}

local CHECKSUM_METHOD = {
    BINARY = 0,
    FILENAME = 1
}

function KOSync:init()
    self.page_update_counter = 0
    self.last_page = -1
    self.last_page_turn_timestamp = 0
    self.periodic_push_scheduled = false
    self._menu_to_update = nil

    --- @todo: Viable candidate for a port to the new readSetting API
    local settings = G_reader_settings:readSetting("kosync") or {}
    self.kosync_custom_server = settings.custom_server
    self.kosync_username = settings.username
    self.kosync_userkey = settings.userkey
    -- Do *not* default to auto-sync on devices w/ NetworkManager support, as wifi is unlikely to be on at all times there, and the nagging enabling this may cause requires careful consideration.
    self.kosync_auto_sync = settings.auto_sync or not Device:hasWifiManager()
    self.kosync_pages_before_update = settings.pages_before_update
    self.kosync_whisper_forward = settings.whisper_forward or SYNC_STRATEGY.DEFAULT_FORWARD
    self.kosync_whisper_backward = settings.whisper_backward or SYNC_STRATEGY.DEFAULT_BACKWARD
    self.kosync_checksum_method = settings.checksum_method or CHECKSUM_METHOD.BINARY
    self.kosync_device_id = G_reader_settings:readSetting("device_id")

    self.ui.menu:registerToMainMenu(self)
end

function KOSync:getSyncPeriod()
    if not self.kosync_auto_sync then
        return _("Unavailable")
    end

    local period = self.kosync_pages_before_update
    if period and period > 0 then
        return period
    else
        return _("Never")
    end
end

local function getNameStrategy(type)
    if type == 1 then
        return _("Prompt")
    elseif type == 2 then
        return _("Auto")
    else
        return _("Disable")
    end
end

local function showSyncedMessage()
    UIManager:show(InfoMessage:new{
        text = _("Progress has been synchronized."),
        timeout = 3,
    })
end

local function promptLogin()
    UIManager:show(InfoMessage:new{
        text = _("Please register or login before using the progress synchronization feature."),
        timeout = 3,
    })
end

local function showSyncError()
    UIManager:show(InfoMessage:new{
        text = _("Something went wrong when syncing progress, please check your network connection and try again later."),
        timeout = 3,
    })
end

local function validate(entry)
    if not entry then return false end
    if type(entry) == "string" then
        if entry == "" or not entry:match("%S") then return false end
    end
    return true
end

local function validateUser(user, pass)
    local error_message = nil
    local user_ok = validate(user)
    local pass_ok = validate(pass)
    if not user_ok and not pass_ok then
        error_message = _("invalid username and password")
    elseif not user_ok then
        error_message = _("invalid username")
    elseif not pass_ok then
        error_message = _("invalid password")
    end

    if not error_message then
        return user_ok and pass_ok
    else
        return user_ok and pass_ok, error_message
    end
end

function KOSync:onDispatcherRegisterActions()
    Dispatcher:registerAction("kosync_push_progress", { category="none", event="KOSyncPushProgress", title=_("Push progress from this device"), reader=true,})
    Dispatcher:registerAction("kosync_pull_progress", { category="none", event="KOSyncPullProgress", title=_("Pull progress from other devices"), reader=true, separator=true,})
end

function KOSync:onReaderReady()
    --assert(self.kosync_device_id)
    if self.kosync_auto_sync then
        self:_onResume()
    end
    self:registerEvents()
    self:onDispatcherRegisterActions()

    self.last_page = self.ui:getCurrentPage()

    -- Make sure checksum has been calculated at the very first time a document has been opened, to
    -- avoid document saving feature to impact the checksum, and eventually impact the document
    -- identity in the progress sync feature.
    self.view.document:fastDigest(self.ui.doc_settings)
end

function KOSync:addToMainMenu(menu_items)
    menu_items.progress_sync = {
        text = _("Progress sync"),
        sub_item_table = {
            {
                text = _("Custom sync server"),
                keep_menu_open = true,
                tap_input_func = function()
                    return {
                        -- @translators Server address defined by user for progress sync.
                        title = _("Custom progress sync server address"),
                        input = self.kosync_custom_server or "https://",
                        type = "text",
                        callback = function(input)
                            self:setCustomServer(input)
                        end,
                    }
                end,
            },
            {
                text_func = function()
                    return self.kosync_userkey and (_("Logout"))
                        or _("Register") .. " / " .. _("Login")
                end,
                keep_menu_open = true,
                callback_func = function()
                    if self.kosync_userkey then
                        return function(menu)
                            self._menu_to_update = menu
                            self:logout()
                        end
                    else
                        return function(menu)
                            self._menu_to_update = menu
                            self:login()
                        end
                    end
                end,
                separator = true,
            },
            {
                text = _("Automatically keep documents in sync"),
                checked_func = function() return self.kosync_auto_sync end,
                help_text = _([[This may lead to nagging about toggling WiFi on document close and suspend/resume, depending on how you've setup your network toggles.]]),
                callback = function()
                    self.kosync_auto_sync = not self.kosync_auto_sync
                    self:registerEvents()
                    if self.kosync_auto_sync then
                        -- since we will update the progress when closing document, we should pull
                        -- current progress now to avoid to overwrite it silently.
                        self:getProgress(true, true)
                    else
                        -- since we won't update the progress when closing document, we should push
                        -- current progress now to avoid to lose it silently.
                        self:updateProgress(true, true)
                    end
                    self:saveSettings()
                end,
            },
            {
                text_func = function()
                    return T(_("Periodically sync every # pages (%1)"), self:getSyncPeriod())
                end,
                enabled_func = function() return self.kosync_auto_sync end,
                -- This is the condition that allows enabling auto_disable_wifi in NetworkManager ;).
                help_text = NetworkMgr:getNetworkInterfaceName() and _([[This may be enough network activity to passively keep WiFi enabled!]]),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items = SpinWidget:new{
                        text = _([[This value determines how many page turns it takes to update book progress.
If set to 0, updating progress based on page turns will be disabled.]]),
                        value = self.kosync_pages_before_update or 0,
                        value_min = 0,
                        value_max = 999,
                        value_step = 1,
                        value_hold_step = 10,
                        ok_text = _("Set"),
                        title_text = _("Number of pages before update"),
                        default_value = 0,
                        callback = function(spin)
                            self:setPagesBeforeUpdate(spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items)
                end,
                separator = true,
            },
            {
                text = _("Sync behavior"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Sync forward (%1)"), getNameStrategy(self.kosync_whisper_forward))
                        end,
                        sub_item_table = {
                            {
                                text = _("Silently"),
                                checked_func = function()
                                    return self.kosync_whisper_forward == SYNC_STRATEGY.WHISPER
                                end,
                                callback = function()
                                    self:setWhisperForward(SYNC_STRATEGY.WHISPER)
                                end,
                            },
                            {
                                text = _("Prompt"),
                                checked_func = function()
                                    return self.kosync_whisper_forward == SYNC_STRATEGY.PROMPT
                                end,
                                callback = function()
                                    self:setWhisperForward(SYNC_STRATEGY.PROMPT)
                                end,
                            },
                            {
                                text = _("Never"),
                                checked_func = function()
                                    return self.kosync_whisper_forward == SYNC_STRATEGY.DISABLE
                                end,
                                callback = function()
                                    self:setWhisperForward(SYNC_STRATEGY.DISABLE)
                                end,
                            },
                        }
                    },
                    {
                        text_func = function()
                            return T(_("Sync backward (%1)"), getNameStrategy(self.kosync_whisper_backward))
                        end,
                        sub_item_table = {
                            {
                                text = _("Silently"),
                                checked_func = function()
                                    return self.kosync_whisper_backward == SYNC_STRATEGY.WHISPER
                                end,
                                callback = function()
                                    self:setWhisperBackward(SYNC_STRATEGY.WHISPER)
                                end,
                            },
                            {
                                text = _("Prompt"),
                                checked_func = function()
                                    return self.kosync_whisper_backward == SYNC_STRATEGY.PROMPT
                                end,
                                callback = function()
                                    self:setWhisperBackward(SYNC_STRATEGY.PROMPT)
                                end,
                            },
                            {
                                text = _("Never"),
                                checked_func = function()
                                    return self.kosync_whisper_backward == SYNC_STRATEGY.DISABLE
                                end,
                                callback = function()
                                    self:setWhisperBackward(SYNC_STRATEGY.DISABLE)
                                end,
                            },
                        }
                    },
                },
                separator = true,
            },
            {
                text = _("Push progress from this device now"),
                enabled_func = function()
                    return self.kosync_userkey ~= nil
                end,
                callback = function()
                    self:updateProgress(true, true)
                end,
            },
            {
                text = _("Pull progress from other devices now"),
                enabled_func = function()
                    return self.kosync_userkey ~= nil
                end,
                callback = function()
                    self:getProgress(true, true)
                end,
                separator = true,
            },
            {
                text = _("Document matching method"),
                sub_item_table = {
                    {
                        text = _("Binary. Only identical files will sync progress."),
                        checked_func = function()
                            return self.kosync_checksum_method == CHECKSUM_METHOD.BINARY
                        end,
                        callback = function()
                            self:setChecksumMethod(CHECKSUM_METHOD.BINARY)
                        end,
                    },
                    {
                        text = _("Filename. Files with the same name will sync progress."),
                        checked_func = function()
                            return self.kosync_checksum_method == CHECKSUM_METHOD.FILENAME
                        end,
                        callback = function()
                            self:setChecksumMethod(CHECKSUM_METHOD.FILENAME)
                        end,
                    },
                }
            },
        }
    }
end

function KOSync:setPagesBeforeUpdate(pages_before_update)
    self.kosync_pages_before_update = pages_before_update > 0 and pages_before_update or nil
    self:saveSettings()
end

function KOSync:setCustomServer(server)
    logger.dbg("KOSync: Setting custom server to:", server)
    self.kosync_custom_server = server ~= "" and server or nil
    self:saveSettings()
end

function KOSync:setWhisperForward(strategy)
    self.kosync_whisper_forward = strategy
    self:saveSettings()
end

function KOSync:setWhisperBackward(strategy)
    self.kosync_whisper_backward = strategy
    self:saveSettings()
end

function KOSync:setChecksumMethod(method)
    self.kosync_checksum_method = method
    self:saveSettings()
end

function KOSync:login()
    if NetworkMgr:willRerunWhenOnline(function() self:login() end) then
        return
    end

    local dialog
    dialog = MultiInputDialog:new{
        title = self.title,
        fields = {
            {
                text = self.kosync_username,
                hint = "username",
            },
            {
                hint = "password",
                text_type = "password",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self._menu_to_update = nil
                    end,
                },
                {
                    text = _("Login"),
                    callback = function()
                        local username, password = unpack(dialog:getFields())
                        local ok, err = validateUser(username, password)
                        if not ok then
                            UIManager:show(InfoMessage:new{
                                text = T(_("Cannot login: %1"), err),
                                timeout = 2,
                            })
                        else
                            UIManager:close(dialog)
                            UIManager:scheduleIn(0.5, function()
                                self:doLogin(username, password)
                            end)
                            UIManager:show(InfoMessage:new{
                                text = _("Logging in. Please wait…"),
                                timeout = 1,
                            })
                        end
                    end,
                },
                {
                    text = _("Register"),
                    callback = function()
                        local username, password = unpack(dialog:getFields())
                        local ok, err = validateUser(username, password)
                        if not ok then
                            UIManager:show(InfoMessage:new{
                                text = T(_("Cannot register: %1"), err),
                                timeout = 2,
                            })
                        else
                            UIManager:close(dialog)
                            UIManager:scheduleIn(0.5, function()
                                self:doRegister(username, password)
                            end)
                            UIManager:show(InfoMessage:new{
                                text = _("Registering. Please wait…"),
                                timeout = 1,
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KOSync:doRegister(username, password)
    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    -- on Android to avoid ANR (no-op on other platforms)
    Device:setIgnoreInput(true)
    local userkey = md5(password)
    local ok, status, body = pcall(client.register, client, username, userkey)
    if not ok then
        if status then
            UIManager:show(InfoMessage:new{
                text = _("An error occurred while registering:") ..
                    "\n" .. status,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("An unknown error occurred while registering."),
            })
        end
    elseif status then
        self.kosync_username = username
        self.kosync_userkey = userkey
        self._menu_to_update:updateItems()
        UIManager:show(InfoMessage:new{
            text = _("Registered to KOReader server."),
        })
    else
        UIManager:show(InfoMessage:new{
            text = body and body.message or _("Unknown server error"),
        })
    end
    Device:setIgnoreInput(false)
    self:saveSettings()
    self._menu_to_update = nil
end

function KOSync:doLogin(username, password)
    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    Device:setIgnoreInput(true)
    local userkey = md5(password)
    local ok, status, body = pcall(client.authorize, client, username, userkey)
    if not ok then
        if status then
            UIManager:show(InfoMessage:new{
                text = _("An error occurred while logging in:") ..
                    "\n" .. status,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("An unknown error occurred while logging in."),
            })
        end
        Device:setIgnoreInput(false)
        return
    elseif status then
        self.kosync_username = username
        self.kosync_userkey = userkey
        self._menu_to_update:updateItems()
        UIManager:show(InfoMessage:new{
            text = _("Logged in to KOReader server."),
        })
    else
        UIManager:show(InfoMessage:new{
            text = body and body.message or _("Unknown server error"),
        })
    end
    Device:setIgnoreInput(false)
    self:saveSettings()
    self._menu_to_update = nil
end

function KOSync:logout()
    self.kosync_userkey = nil
    self.kosync_auto_sync = true
    self._menu_to_update:updateItems()
    self:saveSettings()
    self._menu_to_update = nil
end

function KOSync:getLastPercent()
    if self.ui.document.info.has_pages then
        return Math.roundPercent(self.ui.paging:getLastPercent())
    else
        return Math.roundPercent(self.ui.rolling:getLastPercent())
    end
end

function KOSync:getLastProgress()
    if self.ui.document.info.has_pages then
        return self.ui.paging:getLastProgress()
    else
        return self.ui.rolling:getLastProgress()
    end
end

function KOSync:getDocumentDigest()
    if self.kosync_checksum_method == CHECKSUM_METHOD.FILENAME then
        return self:getFileNameDigest()
    else
        return self:getFileDigest()
    end
end

function KOSync:getFileDigest()
    return self.view.document:fastDigest()
end

function KOSync:getFileNameDigest()
    local file = self.ui.document.file
    if not file then return end

    local file_path, file_name = util.splitFilePathName(file) -- luacheck: no unused
    if not file_name then return end

    return md5(file_name)
end

function KOSync:syncToProgress(progress)
    logger.dbg("KOSync: [Sync] progress to", progress)
    if self.ui.document.info.has_pages then
        self.ui:handleEvent(Event:new("GotoPage", tonumber(progress)))
    else
        self.ui:handleEvent(Event:new("GotoXPointer", progress))
    end
end

function KOSync:updateProgress(ensure_networking, interactive)
    if not self.kosync_username or not self.kosync_userkey then
        if interactive then
            promptLogin()
        end
        return
    end

    if ensure_networking and NetworkMgr:willRerunWhenOnline(function() self:updateProgress(ensure_networking, interactive) end) then
        return
    end

    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    local doc_digest = self:getDocumentDigest()
    local progress = self:getLastProgress()
    local percentage = self:getLastPercent()
    local ok, err = pcall(client.update_progress,
        client,
        self.kosync_username,
        self.kosync_userkey,
        doc_digest,
        progress,
        percentage,
        Device.model,
        self.kosync_device_id,
        function(ok, body)
            logger.dbg("KOSync: [Push] progress to", percentage * 100, "% =>", progress, "for", self.view.document.file)
            logger.dbg("KOSync: ok:", ok, "body:", body)
            if interactive then
                if ok then
                    UIManager:show(InfoMessage:new{
                        text = _("Progress has been pushed."),
                        timeout = 3,
                    })
                else
                    showSyncError()
                end
            end
        end)
    if not ok then
        if interactive then showSyncError() end
        if err then logger.dbg("err:", err) end
    end
end

function KOSync:getProgress(ensure_networking, interactive)
    if not self.kosync_username or not self.kosync_userkey then
        if interactive then
            promptLogin()
        end
        return
    end

    if ensure_networking and NetworkMgr:willRerunWhenOnline(function() self:getProgress(ensure_networking, interactive) end) then
        return
    end

    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    local doc_digest = self:getDocumentDigest()
    local ok, err = pcall(client.get_progress,
        client,
        self.kosync_username,
        self.kosync_userkey,
        doc_digest,
        function(ok, body)
            logger.dbg("KOSync: [Get] progress for", self.view.document.file)
            logger.dbg("KOSync: ok:", ok, "body:", body)
            if not ok or not body then
                if interactive then
                    showSyncError()
                end
                return
            end

            if not body.percentage then
                if interactive then
                    UIManager:show(InfoMessage:new{
                        text = _("No progress found for this document."),
                        timeout = 3,
                    })
                end
                return
            end

            if body.device == Device.model
            and body.device_id == self.kosync_device_id then
                if interactive then
                    UIManager:show(InfoMessage:new{
                        text = _("Latest progress is coming from this device."),
                        timeout = 3,
                    })
                end
                return
            end

            body.percentage = Math.roundPercent(body.percentage)
            local progress = self:getLastProgress()
            local percentage = self:getLastPercent()
            logger.dbg("KOSync: Current progress:", percentage * 100, "% =>", progress)

            if percentage == body.percentage
            or body.progress == progress then
                if interactive then
                    UIManager:show(InfoMessage:new{
                        text = _("The progress has already been synchronized."),
                        timeout = 3,
                    })
                end
                return
            end

            -- The progress needs to be updated.
            if interactive then
                -- If user actively pulls progress from other devices, we always update the
                -- progress without further confirmation.
                self:syncToProgress(body.progress)
                showSyncedMessage()
                return
            end

            local self_older
            if body.timestamp ~= nil then
                self_older = (body.timestamp > self.last_page_turn_timestamp)
            else
                -- If we are working with old sync server, we can only use
                -- percentage field.
                self_older = (body.percentage > percentage)
            end
            if self_older then
                if self.kosync_whisper_forward == SYNC_STRATEGY.WHISPER then
                    self:syncToProgress(body.progress)
                    showSyncedMessage()
                elseif self.kosync_whisper_forward == SYNC_STRATEGY.PROMPT then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Sync to latest location %1% from device '%2'?"),
                                 Math.round(body.percentage * 100),
                                 body.device),
                        ok_callback = function()
                            self:syncToProgress(body.progress)
                        end,
                    })
                end
            else -- if not self_older then
                if self.kosync_whisper_backward == SYNC_STRATEGY.WHISPER then
                    self:syncToProgress(body.progress)
                    showSyncedMessage()
                elseif self.kosync_whisper_backward == SYNC_STRATEGY.PROMPT then
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Sync to previous location %1% from device '%2'?"),
                                 Math.round(body.percentage * 100),
                                 body.device),
                        ok_callback = function()
                            self:syncToProgress(body.progress)
                        end,
                    })
                end
            end
        end)
    if not ok then
        if interactive then showSyncError() end
        if err then logger.dbg("err:", err) end
    end
end

function KOSync:saveSettings()
    local settings = {
        custom_server = self.kosync_custom_server,
        username = self.kosync_username,
        userkey = self.kosync_userkey,
        auto_sync = self.kosync_auto_sync,
        pages_before_update = self.kosync_pages_before_update,
        whisper_forward =
              (self.kosync_whisper_forward ~= SYNC_STRATEGY.DEFAULT_FORWARD
               and self.kosync_whisper_forward
               or nil),
        whisper_backward =
              (self.kosync_whisper_backward ~= SYNC_STRATEGY.DEFAULT_BACKWARD
               and self.kosync_whisper_backward
               or nil),
        checksum_method = self.kosync_checksum_method,
    }
    G_reader_settings:saveSetting("kosync", settings)
end

function KOSync:_onCloseDocument()
    logger.dbg("KOSync: onCloseDocument")
    self:updateProgress(true, false)
end

function KOSync:periodicPushSchedule()
    self.periodic_push_scheduled = false
    -- We do *NOT* want to make sure networking is up here, as the nagging would be extremely annoying; we're leaving that to the network activity check...
    self:updateProgress(false, false)
end

function KOSync:schedulePeriodicPush()
    UIManager:unschedule(self.periodicPushSchedule)
    -- Use a sizable delay to make debouncing this on skim feasible...
    UIManager:scheduleIn(5, self.periodicPushSchedule, self)
    self.periodic_push_scheduled = true
end

function KOSync:_onPageUpdate(page)
    if page == nil then
        return
    end

    if self.last_page ~= page then
        self.last_page = page
        self.last_page_turn_timestamp = os.time()
        self.page_update_counter = self.page_update_counter + 1
        -- If we've already scheduled a push, regardless of the counter's state, delay it until we're *actually* idle
        if self.periodic_push_scheduled then
            self:schedulePeriodicPush()
        elseif self.kosync_pages_before_update and self.page_update_counter >= self.kosync_pages_before_update then
            self.page_update_counter = 0
            self:schedulePeriodicPush()
        end
    end
end

function KOSync:_onResume()
    logger.dbg("KOSync: onResume")
    UIManager:scheduleIn(1, function() self:getProgress(true, false) end)
end

function KOSync:_onFlushSettings()
    logger.dbg("KOSync: onFlushSettings")
    if self.ui == nil or self.ui.document == nil then return end
    -- Requiring networking here may not be entirely sound, so, don't do it.
    self:updateProgress(false, false)
end

function KOSync:_onNetworkConnected()
    logger.dbg("KOSync: onNetworkConnected")
    UIManager:scheduleIn(0.5, function() self:getProgress(true, false) end)
end

function KOSync:_onNetworkDisconnecting()
    logger.dbg("KOSync: onNetworkDisconnecting")
    self:updateProgress(true, false)
end

function KOSync:onKOSyncPushProgress()
    if not self.kosync_userkey then return end
    self:updateProgress(true, true)
end

function KOSync:onKOSyncPullProgress()
    if not self.kosync_userkey then return end
    self:getProgress(true, true)
end

function KOSync:registerEvents()
    if self.kosync_auto_sync then
        self.onCloseDocument = self._onCloseDocument
        self.onPageUpdate = self._onPageUpdate
        self.onResume = self._onResume
        self.onFlushSettings = self._onFlushSettings
        self.onNetworkConnected = self._onNetworkConnected
        self.onNetworkDisconnecting = self._onNetworkDisconnecting
    else
        self.onCloseDocument = nil
        self.onPageUpdate = nil
        self.onResume = nil
        self.onFlushSettings = nil
        self.onNetworkConnected = nil
        self.onNetworkDisconnecting = nil
    end
end

return KOSync
