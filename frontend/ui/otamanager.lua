local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local DEBUG = require("dbg")
local _ = require("gettext")

local OTAManager = {
    ota_server = "http://vislab.bjmu.edu.cn/apps/koreader/ota/",
    ota_channel = "nightly", -- or "stable"
    zsync_template = "koreader-%s-latest-%s.zsync",
    installed_package = "ota/koreader.installed.tar",
    package_indexfile = "ota/package.index",
    updated_package = "ota/koreader.updated.tar",
}

function OTAManager:getOTAModel()
    if Device:isKindle() then
        return "kindle"
    elseif Device:isKobo() then
        return "kobo"
    else
        return ""
    end
end

function OTAManager:getOTAChannel()
    return self.ota_channel
end

function OTAManager:setOTAChannel(channel)
    -- channel should be "nightly" or "stable"
    self.ota_channel = channel
end

function OTAManager:getZsyncFilename()
    return self.zsync_template:format(self:getOTAModel(), self:getOTAChannel())
end

function OTAManager:checkUpdate()
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local zsync_file = self:getZsyncFilename()
    local ota_zsync_file = self.ota_server .. zsync_file
    local local_zsync_file = "ota/" .. zsync_file
    -- download zsync file from OTA server
    local r, c, h = http.request{
        url = ota_zsync_file,
        sink = ltn12.sink.file(io.open(local_zsync_file, "w"))}
    -- parse OTA package version
    if c ~= 200 then return end
    local ota_package = nil
    local zsync = io.open(local_zsync_file, "r")
    if zsync then
        for line in zsync:lines() do
            ota_package = line:match("^Filename:%s*(.-)%s*$")
            if ota_package then break end
        end
        zsync:close()
    end
    local local_version = io.open("git-rev", "r"):read()
    local ota_version = nil
    if ota_package then
        ota_version = ota_package:match(".-(v%d.-)%.tar")
    end
    -- return ota package version if package on OTA server has version
    -- larger than the local package version
    if ota_version and ota_version > local_version then
        return ota_version
    elseif ota_version and ota_version == local_version then
        return 0
    end
end

function OTAManager:_buildLocalPackage()
    return os.execute(string.format(
        "./tar cvf %s -C .. -T %s --no-recursion",
        self.installed_package, self.package_indexfile))
end

function OTAManager:zsync()
    if self:_buildLocalPackage() == 0 then
        return os.execute(string.format(
        "./zsync -i %s -o %s -u %s %s",
        self.installed_package, self.updated_package,
        self.ota_server, "ota/" .. self:getZsyncFilename()
        ))
    end
end

function OTAManager:genMenuEntry()
    return {
        text = _("Check update"),
        callback = function()
            local ota_version = OTAManager:checkUpdate()
            if ota_version == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("Your koreader is updated."),
                })
            elseif ota_version == nil then
                UIManager:show(InfoMessage:new{
                    text = _("OTA server is not available."),
                })
            elseif ota_version then
                UIManager:show(ConfirmBox:new{
                    text = _("Do you want to update to version ")..ota_version.."?",
                    ok_callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _("Downloading may take several minutes..."),
                            timeout = 3,
                        })
                        UIManager:scheduleIn(1, function()
                            if OTAManager:zsync() == 0 then
                                UIManager:show(InfoMessage:new{
                                    text = _("Koreader will be updated on next restart."),
                                })
                            end
                        end)
                    end
                })
            end
        end
    }
end

return OTAManager
