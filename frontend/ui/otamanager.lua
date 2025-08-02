--[[--
Checks for updates on the specified nightly build server.
]]

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local NetworkMgr = require("ui/network/manager")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local Version = require("version")
local kotasync = require("ffi/kotasync")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local ffiUtil = require("ffi/util")
local T = ffiUtil.template

local ota_dir = DataStorage:getDataDir() .. "/ota/"

local OTAManager = {
    -- NOTE: Each URL *MUST* end with a /
    ota_servers = {
        "http://ota.koreader.rocks/",
        --[[
        -- NOTE: Seems down? Ping @chrox ;).
        "http://vislab.bjmu.edu.cn/apps/koreader/ota/",
        --]]
        "http://koreader-fr.ak-team.com/",
        "http://koreader-pl.ak-team.com/",
        "http://koreader-na.ak-team.com/",
        "http://koreader.ak-team.com/",
    },
    ota_channels = {
        "stable",
        "nightly",
    },
    link_template = "koreader-%s-latest-%s",
    sync_template = "koreader-%s-latest-%s.kotasync",
    update_package = ota_dir .. "update.zip",
}

local ota_channels = {
    stable = _("Stable"),
    nightly = _("Development"),
}

function OTAManager:getOTAType()
    local platform, kind = Device:otaModel()
    if not platform then return "none" end
    return kind
end

function OTAManager:getOTAServer()
    return G_reader_settings:readSetting("ota_server") or self.ota_servers[1]
end

function OTAManager:setOTAServer(server)
    logger.dbg("Set OTA server:", server)
    G_reader_settings:saveSetting("ota_server", server)
end

function OTAManager:getOTAChannel()
    return G_reader_settings:readSetting("ota_channel") or self.ota_channels[1]
end

function OTAManager:setOTAChannel(channel)
    logger.dbg("Set OTA channel:", channel)
    G_reader_settings:saveSetting("ota_channel", channel)
end

function OTAManager:getFilename(kind)
    if type(kind) ~= "string" then return end
    local model = Device:otaModel()
    local channel = self:getOTAChannel()
    if kind == "ota" then
        return self.sync_template:format(model, channel)
    elseif kind == "link" then
        return self.link_template:format(model, channel)
    end
end

function OTAManager:checkUpdate()
    if Device:isDeprecated() then return -1 end

    local update_kind = self:getOTAType()
    if not update_kind then return -1 end

    local update_file = self:getFilename(update_kind)
    if not update_file then return -2 end

    local ota_update_file = self:getOTAServer() .. update_file
    local link, ota_package

    logger.dbg("downloading update file", ota_update_file)

    if OTAManager:getOTAType() == "link" then
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")

        local local_update_file = ota_dir .. update_file

        socketutil:set_timeout()
        local code, headers, status = socket.skip(1, http.request{
            url     = ota_update_file,
            sink    = ltn12.sink.file(io.open(local_update_file, "w")),
        })
        socketutil:reset_timeout()
        if code ~= 200 then
            logger.warn("cannot find update file:", status or code or "network unreachable")
            logger.dbg("Response headers:", headers)
            return
        end
        -- parse OTA package version
        local update_info = io.open(local_update_file, "r")
        if update_info then
            local i = 0
            for line in update_info:lines() do
                i = i + 1
                if i == 1 then
                    ota_package = line
                    link = self:getOTAServer() .. ota_package
                end
            end
            update_info:close()
        end
    else
        self.updater = kotasync.Updater:new(ota_dir)
        local ok, err = pcall(self.updater.fetch_manifest, self.updater, ota_update_file)
        if not ok then
            return
        end
        ota_package = err
    end
    local local_ok, local_version = pcall(function()
        local rev = Version:getCurrentRevision()
        if rev then return Version:getNormalizedVersion(rev) end
    end)
    local ota_ok, ota_version = pcall(function()
        return Version:getNormalizedVersion(ota_package)
    end)
    -- return ota package version if package on OTA server has version
    -- larger than the local package version
    if local_ok and ota_ok and ota_version and local_version and
        ota_version ~= local_version then
        return ota_version, local_version, link, ota_package
    elseif ota_version and ota_version == local_version then
        return 0
    end
end

local co_confirm = function(text, ok_text, cancel_text)
    local co = coroutine.running()
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text, ok_callback = function() coroutine.resume(co, true) end,
        cancel_text = cancel_text, cancel_callback = function() coroutine.resume(co, false) end,
    })
    return coroutine.yield()
end

local co_choose = function(text, choice1_text, choice2_text, cancel_text)
    local co = coroutine.running()
    UIManager:show(MultiConfirmBox:new{
        text = text,
        choice1_text = choice1_text, choice1_callback = function() coroutine.resume(co, 1) end,
        choice2_text = choice2_text, choice2_callback = function() coroutine.resume(co, 2) end,
        cancel_text = cancel_text, cancel_callback = function() coroutine.resume(co, false) end,
    })
    return coroutine.yield()
end

function OTAManager:fetchAndProcessUpdate()
    if Device:hasOTARunning() then
        UIManager:show(InfoMessage:new{
            text = _("Download already scheduled. You'll be notified when it's ready."),
        })
        return
    end

    -- Ensure we're running in a coroutine.
    local co = coroutine.running()
    if not co then
        Trapper:wrap(function()
            self:fetchAndProcessUpdate()
            -- Cleanup…
            if self.updater then
                self.updater:free()
                self.updater = nil
            end
        end)
        return
    end
    local re = function(res) coroutine.resume(co, res) end

    -- Ensure network is online.
    if NetworkMgr:willRerunWhenConnected(re) then
        coroutine.yield()
        if not NetworkMgr:isConnected() then
            return
        end
    end

    local ota_version, local_version, link, ota_package = self:checkUpdate()

    if ota_version == 0 then
        UIManager:show(InfoMessage:new{
            text = _("KOReader is up to date."),
        })
        return
    elseif ota_version == -1 then
        UIManager:show(InfoMessage:new{
            text = T(_("Device no longer supported.\n\nPlease check %1"), "https://github.com/koreader/koreader/wiki/deprecated-devices")
        })
        return
    elseif ota_version == -2 then
        UIManager:show(InfoMessage:new{
            text = _("Unable to determine OTA model.")
        })
        return
    elseif ota_version == nil then
        UIManager:show(InfoMessage:new{
            text = _("Unable to contact OTA server. Try again later, or try another mirror."),
        })
        return
    elseif not ota_version then
        return
    end

    local update_message = T(_("Do you want to update?\nInstalled version: %1\nAvailable version: %2"),
                             BD.ltr(local_version),
                             BD.ltr(ota_version))
    local update_ok_text = C_("Application update | Button", "Update")
    if ota_version < local_version then
        -- Android cannot downgrade APKs. The user needs to uninstall current app first.
        -- Instead of doing the auto-update when ready we just download the APK using the browser.
        if Device:isAndroid() then
            UIManager:show(ConfirmBox:new{
                text = T(_("The currently installed version is newer than the available version.\nYou'll need to uninstall the app before installing a previous version.\nDownload anyway?\n\nInstalled version: %1\nAvailable version: %2"),
                    BD.ltr(local_version),
                    BD.ltr(ota_version)),
                ok_text = _("Download"),
                ok_callback = function()
                    Device:openLink(link)
                end,
            })
            return
        end
        update_message =  T(_("The currently installed version is newer than the available version.\nWould you still like to continue and downgrade?\nInstalled version: %1\nAvailable version: %2"),
                            BD.ltr(local_version),
                            BD.ltr(ota_version))
        update_ok_text = _("Downgrade")
    end

    if self:getOTAType() == "link" then
        UIManager:show(ConfirmBox:new{
            text = update_message,
            ok_text = update_ok_text,
            ok_callback = function()
                if Device:isAndroid() then
                    Device:download(link, ota_package, _("Downloading may take several minutes…"))
                elseif Device:isSDL() then
                    Device:openLink(link)
                end
            end
        })
        return
    end

    if not co_confirm(update_message, update_ok_text) then
        return
    end

    local stats = self:_prepareUpdate()
    if not stats then
        -- Canceled.
        return
    end

    if not co_confirm(T(_("Need to fetch %1 out of %2 files (%3), proceed?"), stats.missing_files, stats.total_files, util.getFriendlySize(stats.download_size))) then
        return
    end

    while true do

        local ok, err

        ok, err = self:_fetchUpdate(stats.download_size)
        if ok then
            Device:install()
            return
        end

        local choice = err == "aborted" and 2 or co_choose(
            T(_("Downloading update failed: %1.\n\nYou can:\nCancel, keeping temporary files.\nRetry the update process.\nAbort and cleanup all temporary files."), err),
            _("Retry"), _("Abort")
        )
        if choice == 1 then -- luacheck: ignore 542
            -- Retry.
        elseif choice == 2 then
            -- Abort.
            local ota_file = ota_dir..self:getFilename("ota")
            os.remove(ota_file)
            os.remove(ota_file..".etag")
            os.remove(self.update_package..".part")
            break
        else
            -- Cancel.
            break
        end

    end
end

local function progress_dialog(title, max, dismiss_text)
    local co = coroutine.running()
    local dialog = ProgressbarDialog:new {
        title = title,
        progress_max = max,
        refresh_time_seconds = Device:hasEinkScreen() and 0.5 or 0.1,
        cancel = function() coroutine.resume(co, true) end,
        resume = function() coroutine.resume(co) end,
        dismiss_text = dismiss_text,
    }
    dialog.dismiss_callback = dialog.cancel
    local refresh = function(delay)
        if delay then
            UIManager:scheduleIn(delay, dialog.resume)
        else
            UIManager:nextTick(dialog.resume)
        end
        return coroutine.yield()
    end
    function dialog:update(n, delay)
        if self:reportProgress(n) then
            return refresh(delay)
        end
    end
    UIManager:show(dialog)
    UIManager:forceRePaint()
    refresh()
    return dialog
end

function OTAManager:_prepareUpdate()
    local progress = progress_dialog(
        _("Analyzing local install…"),
        #self.updater.manifest.files,
        _("Abort?")
    )
    local aborted = false
    local stats = self.updater:prepare_update("..", function(count)
        if progress:update(count, 0.05) then
            aborted = true
            return false
        end
        return true
    end)
    progress:close()
    return not aborted and stats or nil
end

function OTAManager:_fetchUpdate(download_size)
    local progress = progress_dialog(
        _("Downloading update…"),
        download_size,
        _("Abort?")
    )
    local aborted = false
    local ok, err = self.updater:download_update_in_subprocess(function(size, count, path)
        if progress:update(size, 0.05) then
            aborted = true
            return false
        end
        return true
    end, 0.1)
    progress:close()
    if aborted then
        return false, "aborted"
    end
    return ok, err
end

function OTAManager:genServerList()
    local servers = {}
    for _, server in ipairs(self.ota_servers) do
        local server_item = {
            text = server,
            checked_func = function() return self:getOTAServer() == server end,
            callback = function() self:setOTAServer(server) end
        }
        table.insert(servers, server_item)
    end
    return servers
end

function OTAManager:genChannelList()
    local channels = {}
    for _, channel in ipairs(self.ota_channels) do
        local channel_item = {
            text = ota_channels[channel],
            checked_func = function() return self:getOTAChannel() == channel end,
            callback = function() self:setOTAChannel(channel) end
        }
        table.insert(channels, channel_item)
    end
    return channels
end

function OTAManager:getOTAMenuTable()
    return {
        text = C_("Application update | Menu", "Update"),
        hold_callback = function()
            OTAManager:fetchAndProcessUpdate()
        end,
        sub_item_table = {
            {
                text = _("Check for updates"),
                callback = function()
                    OTAManager:fetchAndProcessUpdate()
                end
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Update server"),
                        sub_item_table = self:genServerList()
                    },
                    {
                        text = _("Update channel"),
                        sub_item_table = self:genChannelList()
                    },
                }
            },
        }
    }
end

return OTAManager
