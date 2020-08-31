local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local CrashlogViewer = WidgetContainer:new{
    name = "crashlogviewer",
    log = DataStorage:getDataDir() .. "/scripts/tail-crashlog.txt",
    show_less_info = true,
}

function CrashlogViewer:onShowCrashlog()
    self:runShellScript(DataStorage:getDataDir() .. "/scripts/tail-crashlog.sh", true, true)
    local info = self:file_get_contents(self.log)
    if info == false then
        self:alertError(_("No crashlog dump found!"), 2)
        return
    end
    if info == "" then
        self:alertInfo(_("No errors found!"), 1)
        return
    end
    if self.show_less_info then
        info = self:filterCrashlog(info)
    else
        info = self:shortenCrashlog(info)
    end
    local viewer
    local more_less_label = self.show_less_info and "Meer info" or "Minder info"
    viewer = self:textBox("Crash.log", info, "en", {
        {
            {
                text = _("Empty crashlog"),
                callback = function()
                    UIManager:close(viewer)
                    self:onEmptyLog()
                end,
            },
            -- this is some kind of a toggle button, switching between more and less info:
            {
                text = more_less_label,
                callback = function()
                    UIManager:close(viewer)
                    -- toggle the display mode:
                    self.show_less_info = not self.show_less_info
                    self:onShowCrashlog()
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(viewer)
                end,
            },
        },
    })
end

function CrashlogViewer:alertError(message, timeout, dismiss_callback)
    if not dismiss_callback then
        UIManager:show(InfoMessage:new { text = message, icon_file = "resources/info-error.png", timeout = timeout })
    else
        UIManager:show(InfoMessage:new { text = message, icon_file = "resources/info-error.png", timeout = timeout, dismiss_callback = dismiss_callback })
    end
end

function CrashlogViewer:alertInfo(message, timeout, dismiss_callback)
    if not dismiss_callback then
        UIManager:show(InfoMessage:new { text = message, timeout = timeout })
    else
        UIManager:show(InfoMessage:new { text = message, timeout = timeout, dismiss_callback = dismiss_callback })
    end
end

function CrashlogViewer:textBox(title, info, lang, buttons_table)
    -- you can optionally add a buttons_table setting:
    local textviewer
    if not lang then
        lang = "en"
    end
    info = require("util").htmlToPlainTextIfHtml(info)
    textviewer = TextViewer:new {
        title = title,
        text = info,
        justified = false,
        lang = lang,
        buttons_table = buttons_table,
    }
    UIManager:show(textviewer)
    -- return the instance, so we can close it from a custom button table:
    return textviewer
end

function CrashlogViewer:exists(path)
    return lfs.attributes(path) or false
end

function CrashlogViewer:file_get_contents(path)
    if (not self:exists(path)) then
        self:alertError(string.format(_("File %s doesn't exist!"), path), 3)
        return false
    end

    local file = io.open(path, "r")
    local content = file:read("*all")
    file:close()
    file = nil
    return content
end

function CrashlogViewer:file_put_contents(path, content)
    local target = io.open(path, "w")
    if target then
        target:write(content)
        target:close()
    else
        self:alertError(string.format(_("File %s doesn't exist!"), path), 3)
    end
    target = nil
end

function CrashlogViewer:runShellScript(file)
    local BaseUtil = require("ffi/util")
    UIManager:scheduleIn(0.5, function()
        -- we ignore raw return values:
        os.execute(BaseUtil.realpath(file))
    end)
end

function CrashlogViewer:onEmptyLog()
    -- DOES NOT WORK (why not?), even when using a commandline shellscript:
    self:runShellScript(DataStorage:getSettingsDir() .. "/scripts/empty-crashlog.sh", true, true)
    self:file_put_contents(self.log, "")
    self:alertInfo(_("Crashlog emptied!"), 2)
end

function CrashlogViewer:split(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end
        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

function CrashlogViewer:filterCrashlog(info)
    local lines = self:split(info,"\n")
    local errors = ""
    for _, line in ipairs(lines) do
        if line:match("ERROR") or line:match("WARN") then
            errors = errors .. line .. "\n"
        end
    end
    return errors
end

function CrashlogViewer:shortenCrashlog(info)
    local lines = self:split(info,"\n")
    local errors = ""
    for _, line in ipairs(lines) do
        if line:match("[a-z]") and not line:match("RD loaded plugin") and not line:match("ffi%.load") and not line:match("FB:") and not line:match("has been disabled") and not line:match("bitdepth") and not line:match("rotate") and not line:match("setting") and not line:match("fixed") and not line:match("[@%*%]]") and not line:match("KOReader") and not line:match("library") and not line:match("orientation") and not line:match("framebuffer") and not line:match("Loading") and not line:match("initializing") and not line:match("launching") and not line:match("opening file") and not line:match("grayscale") and not line:match(" fb ") then
            errors = errors .. line .. "\n"
        end
    end
    return errors
end

return CrashlogViewer
