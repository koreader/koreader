local BaseUtil = require("ffi/util")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local util = require("util")

local CrashlogViewer = WidgetContainer:new{
    name = "logviewer",
    -- for the errors only view:
    error_strings = {
        "attempt",
        "bad argument",
        "error",
        "ERROR",
        "initial value",
        "invalid",
        "WARN",
    },
    -- for both the errors only and the errors with context view:
    skip_strings = {
        " fb ",
        "CRE WARNING",
        "Current rotation",
        "ICC",
        "FB:",
        "FM loaded plugin",
        "KOReader",
        "Loading",
        "Migrating",
        "PING",
        "RD loaded plugin",
        "Upgrading",
        "Wi%-Fi",
        "bitdepth",
        "block_rendering",
        "bytes from",
        "cre_dom",
        "ctrl%_ifname",
        "dom version",
        "ffi%.load",
        "fixed",
        "framebuffer",
        "grayscale",
        "has been disabled",
        "ignoring cache",
        "INFO",
        "initializing",
        "interface",
        "launching",
        "library",
        "no dialog left",
        "opening file",
        "orientation",
        "quitting uimanager",
        "resume",
        "round%-trip",
        "rotate",
        "setting",
        "statistics",
        "suspend",
        "transmitted",
        "validateWakeupAlarm",
        "wakeup",
        "xpointers",
        "[@%*%]]",
    },
    log_tail = DataStorage:getDataDir() .. "/scripts/tail-crashlog.txt",
    show_errors_only = true,
}
function CrashlogViewer:onShowCrashlog()
    self:runShellScript(DataStorage:getDataDir() .. "/scripts/tail-crashlog.sh", true, true)

    local file = io.open(self.log_tail, "r")
    local info = file:read("*all")
    file:close()
    file = nil
    if not info then
        UIManager:show(InfoMessage:new {
            text = _("No crash.log dump found"),
            icon_file = "resources/info-error.png",
            timeout = 2
        })
        return
    end
    if not self:hasErrorString(info) then
        UIManager:show(InfoMessage:new {
            text = _("No error messages found"),
            timeout = 1
        })
        self.show_errors_only = false
    end
    if self.show_errors_only then
        info = self:showErrorsOnly(info)
    else
        info = self:showErrorsAndContext(info)
    end
    local viewer
    local more_less_label = self.show_errors_only and _("More info") or _("Less info")
    local buttons_table = {{
        -- this is some kind of a toggle button, switching between more and less info:
        {
            text = more_less_label,
            callback = function()
                UIManager:close(viewer)
                -- toggle the display mode:
                self.show_errors_only = not self.show_errors_only
                self:onShowCrashlog()
            end,
        },
        {
            text = _("Close"),
            callback = function()
                UIManager:close(viewer)
            end,
        }}
    }
    local textviewer
    textviewer = TextViewer:new {
        title = _("Crash.log (filtered)"),
        text = require("util").htmlToPlainTextIfHtml(info),
        justified = false,
        buttons_table = buttons_table,
    }
    UIManager:show(textviewer)
end

function CrashlogViewer:hasErrorString(line)
    for _, string in ipairs(self.error_strings) do
        if line:match(string) then
            return true
        end
    end
    return false
end

function CrashlogViewer:hasSkipString(line)
    for _, string in ipairs(self.skip_strings) do
        if line:match(string) then
            return true
        end
    end
    return false
end

function CrashlogViewer:showErrorsOnly(info)
    local errors = ""
    for line in util:gsplit(info, "\n", true, true) do
        if self:hasErrorString(line)
            and not self:hasSkipString(line) then
            errors = errors .. line .. "\n"
        end
    end
    return errors
end

function CrashlogViewer:showErrorsAndContext(info)
    local errors = ""
    for line in util:gsplit(info, "\n", true, true) do
        if line:match("[a-z]")
            and not self:hasSkipString(line)
        then
            errors = errors .. line .. "\n"
        end
    end
    return errors
end

function CrashlogViewer:runShellScript(file, show_message, no_run_message)
    local BD = require("ui/bidi")
    local T = require("ffi/util").template
    local alert_duration = 2
    local script_is_running_msg
    if not no_run_message then
        script_is_running_msg = InfoMessage:new {
            -- @translators %1 is the script's programming language (e.g., shell or python), %2 is the filename
            text = T(_("Running %1 script %2…"), util.getScriptType(file), BD.filename(BaseUtil.basename(file))),
        }
        UIManager:show(script_is_running_msg)
    end

    UIManager:scheduleIn(0.5, function()
        local rv = os.execute(BaseUtil.realpath(file))
        UIManager:close(script_is_running_msg)
        if rv == 0 then
            if not show_message or type(show_message) == "string" then
                local message = _("The script exited successfully")
                if type(show_message) == "string" then
                    message = show_message
                end
                UIManager:show(InfoMessage:new {
                    text = message,
                    timeout = alert_duration
                })
            end
        else
            if not show_message or type(show_message) == "string" then
                local message = "Script klaar!"
                if type(show_message) == "string" then
                    message = show_message
                end
                UIManager:show(InfoMessage:new {
                    text = message,
                    timeout = alert_duration
                })
            end
        end
    end)
end

return CrashlogViewer
