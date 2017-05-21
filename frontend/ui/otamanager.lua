local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
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
        "http://koreader-eu.ak-team.com:80/",
        "http://koreader-af.ak-team.com:80/",
        "http://koreader-na.ak-team.com:80/",
        "http://koreader.ak-team.com:80/",
        "http://hal9k.ifsc.usp.br:80/koreader/",
    },
    ota_channels = {
        "stable",
        "nightly",
    },
    zsync_template = "koreader-%s-latest-%s.zsync",
    installed_package = ota_dir .. "koreader.installed.tar",
    package_indexfile = "ota/package.index",
    updated_package = ota_dir .. "koreader.updated.tar",
}

local ota_channels = {
    stable = _("Stable"),
    nightly = _("Development"),
}

function OTAManager:getOTAModel()
    if Device:isKindle() then
        if Device:isTouchDevice() then
            return "kindle"
        else
            return "kindle-legacy"
        end
    elseif Device:isKobo() then
        return "kobo"
    elseif Device:isPocketBook() then
        return "pocketbook"
    elseif Device:isAndroid() then
        return "android"
    else
        return ""
    end
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

function OTAManager:getZsyncFilename()
    return self.zsync_template:format(self:getOTAModel(), self:getOTAChannel())
end

function OTAManager:checkUpdate()
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local zsync_file = self:getZsyncFilename()
    local ota_zsync_file = self:getOTAServer() .. zsync_file
    local local_zsync_file = ota_dir .. zsync_file
    -- download zsync file from OTA server
    logger.dbg("downloading zsync file", ota_zsync_file)
    local _, c, _ = http.request{
        url = ota_zsync_file,
        sink = ltn12.sink.file(io.open(local_zsync_file, "w"))}
    if c ~= 200 then
        logger.warn("cannot find zsync file", c)
        return
    end
    -- parse OTA package version
    local ota_package = nil
    local zsync = io.open(local_zsync_file, "r")
    if zsync then
        for line in zsync:lines() do
            ota_package = line:match("^Filename:%s*(.-)%s*$")
            if ota_package then break end
        end
        zsync:close()
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
        return ota_version, local_version
    elseif ota_version and ota_version == local_version then
        return 0
    end
end

function OTAManager:fetchAndProcessUpdate()
    local ota_version, local_version = OTAManager:checkUpdate()
    if ota_version == 0 then
        UIManager:show(InfoMessage:new{
            text = _("KOReader is up to date."),
        })
    elseif ota_version == nil then
        local channel = ota_channels[OTAManager:getOTAChannel()]
        UIManager:show(InfoMessage:new{
            text = T(_("OTA package is not available on %1 channel."), channel),
        })
    elseif ota_version then
        UIManager:show(ConfirmBox:new{
            text = T(
                _("Do you want to update?\nInstalled version: %1\nAvailable version: %2"),
                local_version,
                ota_version
            ),
            ok_text = _("Update"),
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
                    else
                        UIManager:show(ConfirmBox:new{
                            text = _("Error updating KOReader. Would you like to delete temporary files?"),
                            ok_callback = function()
                                os.execute("rm " .. ota_dir .. "ko*")
                            end,
                        })
                    end
                end)
            end
        })
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
    if Device:isAndroid() then
        return os.execute(string.format(
            "./tar cvf %s -T %s --no-recursion",
            self.installed_package, self.package_indexfile))
    else
        return os.execute(string.format(
            "./tar cvf %s -C .. -T %s --no-recursion",
            self.installed_package, self.package_indexfile))
    end
end

function OTAManager:zsync()
    if self:_buildLocalPackage() == 0 then
        return os.execute(
            ("./zsync -i %s -o %s -u %s %s%s"):format(
                self.installed_package,
                self.updated_package,
                self:getOTAServer(),
                ota_dir,
                self:getZsyncFilename())
        )
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
        text = _("OTA update"),
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
                        text = _("OTA server"),
                        sub_item_table = self:genServerList()
                    },
                    {
                        text = _("OTA channel"),
                        sub_item_table = self:genChannelList()
                    },
                }
            },
        }
    }
end

return OTAManager
