--[[--
    A module to evaluate the --crash-count parameter.

    This is a helper for detecting the need for --safe-mode
--]]

local safemode = {
    crash_count = 0,
    disable_patches_count = 2,
    disable_plugins_count = 3,
    disable_all_count = 4,
}

-- Matches "--crash-count=" followed by one or more digits
for i = #arg, 1, -1 do
    local crash_count = arg[i]:match("^%-%-crash%-count=(%d+)$")
    if crash_count then
        safemode.crash_count = tonumber(crash_count)
        break
    end
end

function safemode.disable_userpatches()
    local count = safemode.crash_count
    return count == safemode.disable_patches_count or count >= safemode.disable_all_count
end

function safemode.disable_plugins()
    local count = safemode.crash_count
    return count == safemode.disable_plugins_count or count >= safemode.disable_all_count
end

function safemode.check()
    if safemode.crash_count < safemode.disable_patches_count then
        return
    end

    local TextViewer = require("ui/widget/textviewer")
    local UIManager = require("ui/uimanager")
    local T = require("ffi/util").template
    local _ = require("gettext")

    local text = T(_("Number of crashes: %1\n"), tostring(safemode.crash_count))
    if safemode.crash_count ==  safemode.disable_patches_count then
        text = text .. _("User-patches are temporarily disabled.")
    elseif safemode.crash_count ==  safemode.disable_plugins_count then
        text = text .. _("Plugins are temporarily disabled.")
    else
        text = text .. _("Plugins and user-patches are temporarily disabled.")
    end

    text = text .. "\n\n" .. _("You may wish to deactivate the relevant plugin/patch in the corresponding menu item of the 'More tools' menu.")

    local handle = io.popen("grep -i -B 40 -A 10 \"Crash\" crash.log | tail -n 51")
    if handle then
        local tail = handle:read("*a")
        handle:close()
        text = text .. "\n\n" .. tail
    end

    local textviewer = TextViewer:new{
        title = _("Safe mode enabled"),
        text = text,
        text_type = "code",
    }
    UIManager:tickAfterNext(function () UIManager:show(textviewer) end)
end

return safemode
