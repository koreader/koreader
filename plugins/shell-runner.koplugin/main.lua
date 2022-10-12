local BD = require("ui/bidi")
local Device = require ("device")
local FileManagerDocument = require("document/filemanagerdocument")
local InfoMessage = require("ui/widget/infomessage")
local UIManager =  require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BaseUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = BaseUtil.template

local function runScript(file)
     local script_is_running_msg = InfoMessage:new{
         text = T(_("Running shell script %1…"), BD.filename(BaseUtil.basename(file))),
     }
     UIManager:show(script_is_running_msg)
     UIManager:scheduleIn(0.5, function()
         local rv
         if Device:isAndroid() then
             Device:setIgnoreInput(true)
             rv = os.execute("fush " .. BaseUtil.realpath(file))
             Device:setIgnoreInput(false)
         else
             rv = os.execute(BaseUtil.realpath(file))
         end
         UIManager:close(script_is_running_msg)
         if rv == 0 then
             UIManager:show(InfoMessage:new{ text = _("The script exited successfully.") })
         else
             UIManager:show(InfoMessage:new{
                 text = T(_("The script returned a non-zero status code: %1!"), bit.rshift(rv, 8)),
                 icon = "notice-warning",
             })
         end
     end)
end

local ShellRunner = WidgetContainer:extend{
    name = "ShellRunner",
    is_doc_only = false
}

function ShellRunner:init()
    local tRun, tLog = {}, {}

    -- in this example we asign the same function and the same icon to all
    -- extensions for the same handler, but both can be different for each extension.
    for __, v in ipairs({"sh", "zsh", "bash"}) do

        tRun[v] = {
            mimetype = "text/x-shellscript",
            open_func = runScript,
            desc = _("Run script"),
            svg = self.path .. "/generic.svg",
        }

        tLog[v] = {
            mimetype = "text/x-shellscript",
            open_func = function(file) logger.info(file) end,
            desc = _("Log file name"),
        }
    end

    -- register FM handlers
    FileManagerDocument:addHandler("ShellRun", tRun)
    FileManagerDocument:addHandler("ShellLog", tLog)
end

return ShellRunner
