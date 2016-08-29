local InputContainer = require("ui/widget/container/inputcontainer")
local LoginDialog = require("ui/widget/logindialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local DeviceModel = require("device").model
local Event = require("ui/event")
local Math = require("optmath")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")
local md5 = require("ffi/MD5")
local random = require("random")

if not G_reader_settings:readSetting("device_id") then
    G_reader_settings:saveSetting("device_id", random.uuid())
end

local KOSync = InputContainer:new{
    name = "kosync",
    title = _("Register/login to KOReader server"),
}

function KOSync:init()
    local settings = G_reader_settings:readSetting("kosync") or {}
    self.kosync_custom_server = settings.custom_server
    self.kosync_username = settings.username
    self.kosync_userkey = settings.userkey
    self.kosync_auto_sync = not (settings.auto_sync == false)
    self.kosync_device_id = G_reader_settings:readSetting("device_id")
    --assert(self.kosync_device_id)
    self.ui:registerPostInitCallback(function()
        if self.kosync_auto_sync then
            UIManager:scheduleIn(1, function() self:getProgress() end)
        end
    end)
    self.ui.menu:registerToMainMenu(self)
    -- Make sure checksum has been calculated at the very first time a document has been opened, to
    -- avoid document saving feature to impact the checksum, and eventually impact the document
    -- identity in the progress sync feature.
    self.view.document:fastDigest()
end

function KOSync:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Progress sync"),
        sub_item_table = {
            {
                text_func = function()
                    return self.kosync_userkey and (_("Logout"))
                        or _("Register") .. " / " .. _("Login")
                end,
                callback_func = function()
                    return self.kosync_userkey and
                        function() self:logout() end or
                        function() self:login() end
                end,
            },
            {
                text = _("Auto sync now and future"),
                checked_func = function() return self.kosync_auto_sync end,
                callback = function()
                    self.kosync_auto_sync = not self.kosync_auto_sync
                    if self.kosync_auto_sync then
                        -- since we will update the progress when closing document, we should pull
                        -- current progress now to avoid to overwrite it silently.
                        self:getProgress(true)
                    else
                        -- since we won't update the progress when closing document, we should push
                        -- current progress now to avoid to lose it silently.
                        self:updateProgress(true)
                    end
                end,
            },
            {
                text = _("Push progress from this device"),
                enabled_func = function()
                    return self.kosync_userkey ~= nil
                end,
                callback = function()
                    self:updateProgress(true)
                end,
            },
            {
                text = _("Pull progress from other devices"),
                enabled_func = function()
                    return self.kosync_userkey ~= nil
                end,
                callback = function()
                    self:getProgress(true)
                end,
            },
            {
                text = _("Custom sync server"),
                tap_input = {
                    title = _("Custom progress sync server address"),
                    input = self.kosync_custom_server or "https://",
                    type = "text",
                    callback = function(input)
                        self:setCustomServer(input)
                    end,
                },
            },
        }
    })
end

function KOSync:setCustomServer(server)
    DEBUG("set custom server", server)
    self.kosync_custom_server = server ~= "" and server or nil
    self:onSaveSettings()
end

function KOSync:login()
    if NetworkMgr:getWifiStatus() == false then
        NetworkMgr:promptWifiOn()
    end
    self.login_dialog = LoginDialog:new{
        title = self.title,
        username = self.kosync_username or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:closeDialog()
                    end,
                },
                {
                    text = _("Login"),
                    enabled = true,
                    callback = function()
                        local username, password = self:getCredential()
                        self:closeDialog()
                        UIManager:scheduleIn(0.5, function()
                            self:doLogin(username, password)
                        end)

                        UIManager:show(InfoMessage:new{
                            text = _("Logging in. Please wait…"),
                            timeout = 1,
                        })
                    end,
                },
                {
                    text = _("Register"),
                    enabled = true,
                    callback = function()
                        local username, password = self:getCredential()
                        self:closeDialog()
                        UIManager:scheduleIn(0.5, function()
                            self:doRegister(username, password)
                        end)

                        UIManager:show(InfoMessage:new{
                            text = _("Registering. Please wait…"),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.4,
    }

    self.login_dialog:onShowKeyboard()
    UIManager:show(self.login_dialog)
end

function KOSync:closeDialog()
    self.login_dialog:onClose()
    UIManager:close(self.login_dialog)
end

function KOSync:getCredential()
    return self.login_dialog:getCredential()
end

function KOSync:doRegister(username, password)
    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    local userkey = md5.sum(password)
    local ok, status, body = pcall(client.register, client, username, userkey)
    if not ok and status then
        UIManager:show(InfoMessage:new{
            text = _("An error occurred while registering:") ..
                "\n" .. status,
        })
    elseif ok then
        if status then
            self.kosync_username = username
            self.kosync_userkey = userkey
            UIManager:show(InfoMessage:new{
                text = _("Registered to KOReader server."),
            })
        else
            UIManager:show(InfoMessage:new{
                text = _(body and body.message or "Unknown server error"),
            })
        end
    end

    self:onSaveSettings()
end

function KOSync:doLogin(username, password)
    local KOSyncClient = require("KOSyncClient")
    local client = KOSyncClient:new{
        custom_url = self.kosync_custom_server,
        service_spec = self.path .. "/api.json"
    }
    local userkey = md5.sum(password)
    local ok, status, body = pcall(client.authorize, client, username, userkey)
    if not ok and status then
        UIManager:show(InfoMessage:new{
            text = _("An error occurred while logging in:") ..
                "\n" .. status,
        })
    elseif ok then
        if status then
            self.kosync_username = username
            self.kosync_userkey = userkey
            UIManager:show(InfoMessage:new{
                text = _("Logged in to KOReader server."),
            })
        else
            UIManager:show(InfoMessage:new{
                text = _(body and body.message or "Unknown server error"),
            })
        end
    end

    self:onSaveSettings()
end

function KOSync:logout()
    self.kosync_userkey = nil
    self.kosync_auto_sync = true
    self:onSaveSettings()
end

local function roundPercent(percent)
    return math.floor(percent * 10000) / 10000
end

function KOSync:getLastPercent()
    if self.ui.document.info.has_pages then
        return roundPercent(self.ui.paging:getLastPercent())
    else
        return roundPercent(self.ui.rolling:getLastPercent())
    end
end

function KOSync:getLastProgress()
    if self.ui.document.info.has_pages then
        return self.ui.paging:getLastProgress()
    else
        return self.ui.rolling:getLastProgress()
    end
end

function KOSync:syncToProgress(progress)
    DEBUG("sync to", progress)
    if self.ui.document.info.has_pages then
        self.ui:handleEvent(Event:new("GotoPage", tonumber(progress)))
    else
        self.ui:handleEvent(Event:new("GotoXPointer", progress))
    end
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

function KOSync:updateProgress(manual)
    if self.kosync_username and self.kosync_userkey then
        local KOSyncClient = require("KOSyncClient")
        local client = KOSyncClient:new{
            custom_url = self.kosync_custom_server,
            service_spec = self.path .. "/api.json"
        }
        local doc_digest = self.view.document:fastDigest()
        local progress = self:getLastProgress()
        local percentage = self:getLastPercent()
        local ok, err = pcall(client.update_progress,
            client,
            self.kosync_username,
            self.kosync_userkey,
            doc_digest,
            progress,
            percentage,
            DeviceModel,
            self.kosync_device_id,
            function(ok, body)
                DEBUG("update progress for", self.view.document.file, ok)
                if manual then
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
            if manual then showSyncError() end
            if err then DEBUG("err:", err) end
        end
    elseif manual then
        promptLogin()
    end
end

function KOSync:getProgress(manual)
    if self.kosync_username and self.kosync_userkey then
        local KOSyncClient = require("KOSyncClient")
        local client = KOSyncClient:new{
            custom_url = self.kosync_custom_server,
            service_spec = self.path .. "/api.json"
        }
        local doc_digest = self.view.document:fastDigest()
        local ok, err = pcall(client.get_progress,
            client,
            self.kosync_username,
            self.kosync_userkey,
            doc_digest,
            function(ok, body)
                DEBUG("get progress for", self.view.document.file, ok, body)
                if body then
                    if body.percentage then
                        if body.device ~= DeviceModel
                        or body.device_id ~= self.kosync_device_id then
                            body.percentage = roundPercent(body.percentage)
                            local progress = self:getLastProgress()
                            local percentage = self:getLastPercent()
                            DEBUG("current progress", percentage)
                            if body.percentage > percentage and body.progress ~= progress then
                                UIManager:show(ConfirmBox:new{
                                    text = T(_("Sync to furthest location read (%1%) from device '%2'?"),
                                        Math.round(body.percentage*100), body.device),
                                    ok_callback = function()
                                        self:syncToProgress(body.progress)
                                    end,
                                })
                            elseif manual then
                                UIManager:show(InfoMessage:new{
                                    text = _("Already synchronized."),
                                    timeout = 3,
                                })
                            end
                        elseif manual then
                            UIManager:show(InfoMessage:new{
                                text = _("Latest progress is coming from this device."),
                                timeout = 3,
                            })
                        end
                    elseif manual then
                        UIManager:show(InfoMessage:new{
                            text = _("No progress found for this document."),
                            timeout = 3,
                        })
                    end
                elseif manual then
                    showSyncError()
                end
            end)
        if not ok then
            if manual then showSyncError() end
            if err then DEBUG("err:", err) end
        end
    elseif manual then
        promptLogin()
    end
end

function KOSync:onSaveSettings()
    local settings = {
        custom_server = self.kosync_custom_server,
        username = self.kosync_username,
        userkey = self.kosync_userkey,
        auto_sync = self.kosync_auto_sync,
    }
    G_reader_settings:saveSetting("kosync", settings)
end

function KOSync:onCloseDocument()
    DEBUG("on close document")
    if self.kosync_auto_sync then
        self:updateProgress()
    end
end

return KOSync
