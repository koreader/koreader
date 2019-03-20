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
local _ = require("gettext")
local T = require("ffi/util").template

local ota_dir = DataStorage:getDataDir() .. "/ota/"

local OTAManager = {
    ota_servers = {
        "http://ota.koreader.rocks:80/",
        "http://vislab.bjmu.edu.cn:80/apps/koreader/ota/",
        --[[
        -- NOTE: Because we can't have nice things,
        --       the HTTP frontend of these OpenStack storage containers doesn't actually properly support
        --       HTTP/1.1 Range requests when multiple byte ranges are requested: they return bogus data when doing so,
        --       which confuses zsync, causing it to retry indefinitely instead of aborting...
        --       c.f., https://github.com/koreader/koreader-base/pull/699
        "http://koreader-fr.ak-team.com:80/",
        "http://koreader-pl.ak-team.com:80/",
        "http://koreader-na.ak-team.com:80/",
        --]]
        "http://koreader.ak-team.com:80/",
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

-- Try to detect WARIO+ Kindle boards (i.MX6 & i.MX7)
function OTAManager:_isKindleWarioOrMore()
    local cpu_hw = nil
    -- Parse cpuinfo line by line, until we find the Hardware description
    for line in io.lines("/proc/cpuinfo") do
        if line:find("^Hardware") then
            cpu_hw = line:match("^Hardware%s*:%s([%g%s]*)$")
        end
    end
    -- NOTE: I couldn't dig up a cpuinfo dump from an Oasis 2 to check the CPU part value,
    --       but for Wario (Cortex A9), matching that to 0xc09 would work, too.
    --       On the other hand, I'm already using the Hardware match in MRPI, so, that sealed the deal ;).

    -- If we've got a Hardware string, check if it mentions an i.MX 6 or 7...
    if cpu_hw then
        if cpu_hw:find("i.MX%s?[6-7]") then
            return true
        else
            return false
        end
    else
        return false
    end
end

-- "x86", "x64", "arm", "arm64", "ppc", "mips" or "mips64".
local arch = jit.arch

function OTAManager:getOTAModel()
    if Device:isAndroid() then
        if arch == "x86" then
            return "android-x86"
        end
        return "android"
    elseif Device:isSDL() then
        return "appimage"
    elseif Device:isCervantes() then
        return "cervantes"
    elseif Device:isKindle() then
        if Device:isTouchDevice() or Device.model == "Kindle4" then
            if self:_isKindleWarioOrMore() then
                return "kindlepw2"
            else
                return "kindle"
            end
        else
            return "kindle-legacy"
        end
    elseif Device:isKobo() then
        return "kobo"
    elseif Device:isPocketBook() then
        return "pocketbook"
    elseif Device:isSonyPRSTUX() then
        return "sony-prstux"
    else
        return ""
    end
end

function OTAManager:getOTAType()
    local ota_model = self:getOTAModel()

    if ota_model == "" then return end

    if ota_model:find("android") or ota_model:find("appimage") then
        return "link"
    end

    return "ota"
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

function OTAManager:getLinkFilename()
    return self.link_template:format(self:getOTAModel(), self:getOTAChannel())
end

function OTAManager:getZsyncFilename()
    return self.zsync_template:format(self:getOTAModel(), self:getOTAChannel())
end

function OTAManager:checkUpdate()
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local update_file = (self:getOTAType() == "link") and self:getLinkFilename() or self:getZsyncFilename()

    local ota_update_file = self:getOTAServer() .. update_file
    local local_update_file = ota_dir .. update_file
    -- download zsync file from OTA server
    logger.dbg("downloading update file", ota_update_file)
    local _, c, _ = http.request{
        url = ota_update_file,
        sink = ltn12.sink.file(io.open(local_update_file, "w"))}
    if c ~= 200 then
        logger.warn("cannot find update file", c)
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
    local ota_version, local_version, link, ota_package = OTAManager:checkUpdate()

    if ota_version == 0 then
        UIManager:show(InfoMessage:new{
            text = _("KOReader is up to date."),
        })
    elseif ota_version == nil then
        local channel = ota_channels[OTAManager:getOTAChannel()]
        UIManager:show(InfoMessage:new{
            text = T(_("Update information not available on %1 channel."), channel),
        })
    elseif ota_version then
        local update_message = T(_("Do you want to update?\nInstalled version: %1\nAvailable version: %2"),
                                 local_version,
                                 ota_version)
        local update_ok_text = _("Update")
        if ota_version < local_version then
            update_message =  T(_("The currently installed version is newer than the available version.\nWould you still like to continue and downgrade?\nInstalled version: %1\nAvailable version: %2"),
                                local_version,
                                ota_version)
            update_ok_text = _("Downgrade")
        end

        if OTAManager:getOTAType() == "link" then
            UIManager:show(ConfirmBox:new{
                text = update_message,
                ok_text = update_ok_text,
                ok_callback = function()
                    local isAndroid, android = pcall(require, "android")
                    if isAndroid then
                        -- download the package if not present.
                        if android.download(link, ota_package) then
                            android.notification(T(_("The file %1 already exists."), ota_package))
                        else
                            android.notification(T(_("Downloading %1"), ota_package))
                        end
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
                        text = _("Downloading may take several minutes…"),
                        timeout = 3,
                    })
                    UIManager:scheduleIn(1, function()
                        if OTAManager:zsync() == 0 then
                            UIManager:show(InfoMessage:new{
                                text = _("KOReader will be updated on next restart."),
                            })
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
                                    os.execute("rm " .. self.installed_package)
                                    os.execute("rm " .. self.updated_package .. "*")
                                    -- And then relaunch zsync in full download mode...
                                    UIManager:scheduleIn(1, function()
                                        if OTAManager:zsync(true) == 0 then
                                            UIManager:show(InfoMessage:new{
                                                text = _("KOReader will be updated on next restart."),
                                            })
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
                                                    os.execute("rm " .. ota_dir .. "ko*")
                                                end,
                                            })
                                        end
                                    end)
                                end,
                                choice2_text = _("Abort"),
                                choice2_callback = function()
                                    os.execute("rm " .. ota_dir .. "ko*")
                                end,
                            })
                        end
                    end)
                end
            })
        end
    end
end

function OTAManager:_buildLocalPackage()
    -- TODO: validate the installed package?
    local installed_package = self.installed_package
    if lfs.attributes(installed_package, "mode") == "file" then
        return 0
    end
    if lfs.attributes(self.package_indexfile, "mode") ~= "file" then
        logger.err("Missing ota metadata:", self.package_indexfile)
        return nil
    end

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
            blocks = tarball_size / (512 * 20)
        end
        -- And since we want a percentage, devise the exact value we need for tar to spit out exactly 100 checkpoints ;).
        local cpoints = blocks / 100
        return os.execute(string.format(
            "./tar --no-recursion -cf %s -C .. -T %s --checkpoint=%d --checkpoint-action=exec='./fbink -q -y -6 -P $(($TAR_CHECKPOINT/%d))'",
            self.installed_package, self.package_indexfile, cpoints, cpoints))
    else
        return os.execute(string.format(
            "./tar --no-recursion -cf %s -C .. -T %s",
            self.installed_package, self.package_indexfile))
    end
end

function OTAManager:zsync(full_dl)
    if full_dl or self:_buildLocalPackage() == 0 then
        local zsync_wrapper = "zsync"
        -- With visual feedback if supported...
        if self.can_pretty_print then
            zsync_wrapper = "spinning_zsync"
        end
        -- If that's a full-download fallback, drop the input tarball
        if full_dl then
            return os.execute(
            ("./%s -o '%s' -u '%s' '%s%s'"):format(
                zsync_wrapper,
                self.updated_package,
                self:getOTAServer(),
                ota_dir,
                self:getZsyncFilename())
            )
        else
            return os.execute(
            ("./%s -i '%s' -o '%s' -u '%s' '%s%s'"):format(
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
        text = _("Update"),
        hold_callback = function()
            if not NetworkMgr:isOnline() then
                NetworkMgr:promptWifiOn()
            else
                OTAManager:fetchAndProcessUpdate()
            end
        end,
        sub_item_table = {
            {
                text = _("Check for update"),
                callback = function()
                    if not NetworkMgr:isOnline() then
                        NetworkMgr:promptWifiOn()
                    else
                        OTAManager:fetchAndProcessUpdate()
                    end
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
