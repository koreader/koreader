local BD = require("ui/bidi")
local Device = require ("device")
local FileManagerDocument = require("document/filemanagerdocument")
local InfoMessage = require("ui/widget/infomessage")
local UIManager =  require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BaseUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = BaseUtil.template

-- example plugin which registers a few extensions as FM documents.

-- This is the single function used by all extensions
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

-- this is the table of extensions this plugin knows how to handle
local t = {}
for __, v in ipairs({"sh", "zsh", "bash"}) do
    t[v] = {
        mimetype = "text/x-shellscript",
        open_func = runScript,
        desc = _("Run script"),
        svg = "icon.svg",
    }
end

local ShellRunner = WidgetContainer:extend{
    name = "ShellRunner",
    is_doc_only = false,
}

-- on init we register the extensions as FM documents
function ShellRunner:init()
    FileManagerDocument:addHandler("ShellRunner", t)

    -- add another handler for "sh" files, just to showcase a nice menu to choose action :)
    FileManagerDocument:addHandler("ShellDummy", {
        sh = {
            mimetype = "text/x-shellscript",
            open_func = function(file) logger.info(file) end,
            desc = _("Log file name"),
        }
    })
end

return ShellRunner
