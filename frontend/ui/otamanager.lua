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
local UIManager = require("ui/uimanager")
local Version = require("version")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

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
    zsync_template = "koreader-%s-latest-%s.zsync",
    installed_package = ota_dir .. "koreader.installed.tar",
    package_indexfile = "ota/package.index",
    updated_package = ota_dir .. "koreader.updated.tar",
    can_pretty_print = lfs.attributes("./fbink", "mode") == "file" and true or false,
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
        return self.zsync_template:format(model, channel)
    elseif kind == "link" then
        return self.link_template:format(model, channel)
    end
end

function OTAManager:getZsyncFilename()
    return self:getFilename("ota")
end

function OTAManager:checkUpdate()
    if Device:isDeprecated() then return -1 end
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")

    local update_kind = self:getOTAType()
    if not update_kind then return -1 end

    local update_file = self:getFilename(update_kind)
    if not update_file then return -2 end

    local ota_update_file = self:getOTAServer() .. update_file
    local local_update_file = ota_dir .. update_file
    -- download zsync file from OTA server
    logger.dbg("downloading update file", ota_update_file)
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
    local link, ota_package
    local update_info = io.open(local_update_file, "r")
    if update_info then
        if OTAManager:getOTAType() == "link" then
            local i = 0
            for line in update_info:lines() do
                i = i + 1
                if i == 1 then
                    ota_package = line
                    link = self:getOTAServer() .. ota_package
                end
            end
        else
            for line in update_info:lines() do
                ota_package = line:match("^Filename:%s*(.-)%s*$")
                if ota_package then break end
            end
        end
        update_info:close()
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

function OTAManager:fetchAndProcessUpdate()
    if Device:hasOTARunning() then
        UIManager:show(InfoMessage:new{
            text = _("Download already scheduled. You'll be notified when it's ready."),
        })
        return
    end

    local ota_version, local_version, link, ota_package = OTAManager:checkUpdate()

    if ota_version == 0 then
        UIManager:show(InfoMessage:new{
            text = _("KOReader is up to date."),
        })
    elseif ota_version == -1 then
        UIManager:show(InfoMessage:new{
            text = T(_("Device no longer supported.\n\nPlease check %1"), "https://github.com/koreader/koreader/wiki/deprecated-devices")
        })
    elseif ota_version == -2 then
        UIManager:show(InfoMessage:new{
            text = _("Unable to determine OTA model.")
        })
    elseif ota_version == nil then
        UIManager:show(InfoMessage:new{
            text = _("Unable to contact OTA server. Try again later, or try another mirror."),
        })
    elseif ota_version then
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

        local wait_for_download = _("Downloading may take several minutes…")

        if OTAManager:getOTAType() == "link" then
            UIManager:show(ConfirmBox:new{
                text = update_message,
                ok_text = update_ok_text,
                ok_callback = function()
                    if Device:isAndroid() then
                        Device:download(link, ota_package, wait_for_download)
                    elseif Device:isSDL() then
                        Device:openLink(link)
                    end
                end
            })
        else
            UIManager:show(ConfirmBox:new{
                text = update_message,
                ok_text = update_ok_text,
                ok_callback = function()
                    UIManager:show(InfoMessage:new{
                        text = wait_for_download,
                        timeout = 3,
                    })
                    UIManager:scheduleIn(1, function()
                        if OTAManager:zsync() == 0 then
                            Device:install()
                            -- Make it clear that zsync is done
                            if self.can_pretty_print then
                                os.execute("./fbink -q -y -7 -pm ' '  ' '")
                            end
                        else
                            -- Make it clear that zsync is done
                            if self.can_pretty_print then
                                os.execute("./fbink -q -y -7 -pm ' '  ' '")
                            end
                            UIManager:show(MultiConfirmBox:new{
                                text = _("Failed to update KOReader.\n\nYou can:\nCancel, keeping temporary files.\nRetry the update process with a full download.\nAbort and cleanup all temporary files."),
                                choice1_text = _("Retry"),
                                choice1_callback = function()
                                    UIManager:show(InfoMessage:new{
                                        text = _("Downloading may take several minutes…"),
                                        timeout = 3,
                                    })
                                    -- Clear the installed package, as well as the complete/incomplete update download
                                    os.execute("rm -f " .. self.installed_package)
                                    os.execute("rm -f " .. self.updated_package .. "*")
                                    -- As well as temporary files, in case zsync went kablooey too early...
                                    os.execute("rm -f ./rcksum-*")
                                    -- And then relaunch zsync in full download mode...
                                    UIManager:scheduleIn(1, function()
                                        if OTAManager:zsync(true) == 0 then
                                            Device:install()
                                            -- Make it clear that zsync is done
                                            if self.can_pretty_print then
                                                os.execute("./fbink -q -y -7 -pm ' '  ' '")
                                            end
                                        else
                                            -- Make it clear that zsync is done
                                            if self.can_pretty_print then
                                                os.execute("./fbink -q -y -7 -pm ' '  ' '")
                                            end
                                            UIManager:show(ConfirmBox:new{
                                                text = _("Error updating KOReader. Would you like to delete temporary files?"),
                                                ok_callback = function()
                                                    os.execute("rm -f " .. ota_dir .. "ko*")
                                                end,
                                            })
                                        end
                                    end)
                                end,
                                choice2_text = _("Abort"),
                                choice2_callback = function()
                                    os.execute("rm -f " .. ota_dir .. "ko*")
                                    os.execute("rm -f " .. self.updated_package .. "*")
                                    os.execute("rm -f ./rcksum-*")
                                end,
                            })
                        end
                    end)
                end
            })
        end
    end
end

---- Uses zsync and tar to prepare an update package.
function OTAManager:_buildLocalPackage()
    --- @todo Validate the installed package?
    local installed_package = self.installed_package
    if lfs.attributes(installed_package, "mode") == "file" then
        return 0
    end
    if lfs.attributes(self.package_indexfile, "mode") ~= "file" then
        logger.err("Missing ota metadata:", self.package_indexfile)
        return nil
    end

    local tar_cmd = {
        './tar',
        '--create', '--file='..self.installed_package,
        '--mtime', tostring(Version:getBuildDate()),
        '--numeric-owner', '--owner=0', '--group=0',
        '--ignore-failed-read', '--no-recursion', '-C', '..',
        '--verbatim-files-from', '--files-from', self.package_indexfile,
    }

    -- With visual feedback if supported...
    if self.can_pretty_print then
        os.execute("./fbink -q -y -7 -pmh 'Preparing local OTA package'")
        -- We need a vague idea of how much space the tarball we're creating will take to compute a proper percentage...
        -- Get the size from the latest zsync package, which'll be a closer match than anything else we might come up with.
        local update_file = self:getZsyncFilename()
        local local_update_file = ota_dir .. update_file
        local tarball_size = nil
        local zsync = io.open(local_update_file, "r")
        if zsync then
            for line in zsync:lines() do
                tarball_size = line:match("^Length: (%d*)$")
                if tarball_size then break end
            end
            zsync:close()
        end
        -- Next, we need to compute the amount of tar blocks that'll take, knowing that tar's default blocksize is 20 * 512 bytes.
        -- c.f., https://superuser.com/questions/168749 & http://www.noah.org/wiki/tar_notes
        -- Defaults to a sane-ish value as-of now, in case shit happens...
        local blocks = 6405
        if tarball_size then
            blocks = tarball_size * (1/(512 * 20))
        end
        -- And since we want a percentage, devise the exact value we need for tar to spit out exactly 100 checkpoints ;).
        local cpoints = blocks * (1/100)
        table.insert(tar_cmd, string.format('--checkpoint=%d', cpoints))
        table.insert(tar_cmd, string.format('--checkpoint-action=exec=./fbink -q -y -6 -P $(($TAR_CHECKPOINT/%d))', cpoints))
    end
    return os.execute(util.shell_escape(tar_cmd))
end

function OTAManager:zsync(full_dl)
    if full_dl or self:_buildLocalPackage() == 0 then
        local zsync_wrapper = "zsync2"
        local use_pipefail = true
        -- With visual feedback if supported...
        if self.can_pretty_print then
            zsync_wrapper = "spinning_zsync"
            -- And because everything is terrible, we can't check for pipefail's usability in spinning_zsync,
            -- because older ash versions abort on set -o failures...
            -- c.f., ko/#5844
            -- So, instead, check from this side of the fence...
            -- (remember, os.execute is essentially system(), it goes through sh)
            use_pipefail = (os.execute("set -o pipefail 2>/dev/null") == 0)
        end
        -- If that's a full-download fallback, drop the input tarball
        if full_dl then
            return os.execute(
            ("env WITH_PIPEFAIL='%s' ./%s -o '%s' -u '%s' '%s%s'"):format(
                use_pipefail,
                zsync_wrapper,
                self.updated_package,
                self:getOTAServer(),
                ota_dir,
                self:getZsyncFilename())
            )
        else
            return os.execute(
            ("env WITH_PIPEFAIL='%s' ./%s -i '%s' -o '%s' -u '%s' '%s%s'"):format(
                use_pipefail,
                zsync_wrapper,
                self.installed_package,
                self.updated_package,
                self:getOTAServer(),
                ota_dir,
                self:getZsyncFilename())
            )
        end
    end
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
            local connect_callback = function()
                OTAManager:fetchAndProcessUpdate()
            end
            NetworkMgr:runWhenOnline(connect_callback)
        end,
        sub_item_table = {
            {
                text = _("Check for updates"),
                callback = function()
                    local working_im = InfoMessage:new{
                        alignment = "center",
                        show_icon = false,
                        text = "⌛",
                    }
                    UIManager:show(working_im)
                    UIManager:forceRePaint()

                    local connect_callback = function()
                        OTAManager:fetchAndProcessUpdate()
                    end

                    UIManager:close(working_im)
                    NetworkMgr:runWhenOnline(connect_callback)
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
