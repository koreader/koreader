local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local ReadHistory = require("readhistory")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local joinPath = require("ffi/util").joinPath
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local menuItem = {
    text = _("Retrieve reading records")
}

local history_file = joinPath(DataStorage:getDataDir(), "history.lua")
local history_backup_file = joinPath(DataStorage:getDataDir(), "history.lua.backup")

local function getFilePathFromMetadata(file)
    local noSuffix, suffix = file:match("(.*)%.sdr/metadata%.(.+)%.lua")
    return noSuffix .. "." .. suffix
end

local function doBuildHistory()
    --- home_dir should be returned by some shared logic.
    local dir = G_reader_settings:readSetting("home_dir")
                or require("apps/filemanager/filemanagerutil").getDefaultDir()
                or "."
    local file = io.popen("find '" .. dir .. "' -name 'metadata.*.lua' -exec stat -c '%N %Y' {} \\;")
    local records = {}
    for line in file:lines() do
        local f, t = line:match("(.+) (%d+)")
        table.insert(records, {
            time = tonumber(t),
            file = getFilePathFromMetadata(f),
        })
    end
    file:close()

    ReadHistory.hist = records
    ReadHistory:_flush()
    ReadHistory:reload()

    --- TODO(hzj-jie): Consider to open the history view directly.
    UIManager:show(InfoMessage:new{
        text = _("History view has been updated, use main menu to access it."),
        timeout = 2,
    })
end

local function backupAndBuildHistory()
    if os.execute("mv '" .. history_file .. "' '" .. history_backup_file .. "'") == 0 then
        doBuildHistory()
    else
        UIManager:show(ConfirmBox:new{
            text = T(_("Failed to backup current history view from %1 to %2, still want to proceed?", history_file, history_backup_file)),
            ok_text = _("Proceed"),
            ok_callback = doBuildHistory,
        })
    end
end

local function buildHistory()
    if not lfs.attributes(history_backup_file) then
        -- backup file does not exist, go ahead.
        backupAndBuildHistory()
    else
        UIManager:show(ConfirmBox:new{
            text = _("Found an existing history backup file; it will be overwritten. Still want to proceed?"),
            ok_text = _("Proceed"),
            ok_callback = backupAndBuildHistory,
        })
    end
end

local function restoreHistory()
    if os.execute("mv '" .. history_backup_file .. "' '" .. history_file .. "'") == 0 then
        ReadHistory.last_read_time = 0
        ReadHistory:reload()
        --- TODO(hzj-jie): Consider to open the history view directly.
        UIManager:show(InfoMessage:new{
            text = _("Last history view has been restored, use main menu to access it."),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Failed to restore the last history view from %1."), history_backup_file),
        })
    end
end

menuItem.callback = function()
    UIManager:show(MultiConfirmBox:new{
        text = _("This function searches and retrieves all the reading records in the home directory and build the history view.\nThe last history view will be preserved and can be restored."),
        choice1_text = _("Retrieve"),
        choice1_callback = buildHistory,
        choice2_text = _("Restore"),
        choice2_callback = restoreHistory,
    })
end

local FindHistory = WidgetContainer:new{
    name = "findhistory",
}

function FindHistory:init()
    self.ui.menu:registerToMainMenu(self)
end

function FindHistory:addToMainMenu(menu_items)
    menu_items.findhistory = menuItem
end

return FindHistory
