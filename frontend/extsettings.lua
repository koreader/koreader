local util = require('util')

function initializeDefaults(setting_name, defaults, force_initialization)
    local curr = G_reader_settings:readSetting(setting_name)
    if not curr or force_initialization then
        G_reader_settings:saveSetting(setting_name, defaults)
        return true -- initialized default values
    end
    return false -- settings were already initialized
end

function getSettingForExt(setting_name, file)
    local filetype = util.getFileNameSuffix(file)
    local saved_settings = G_reader_settings:readSetting(setting_name) or {}
    return saved_settings[filetype]
end

function setSettingForExt(setting_name, value, file)
    local filetype = util.getFileNameSuffix(file)
    local saved_settings = G_reader_settings:readSetting(setting_name) or {}
    saved_settings[filetype] = value
    G_reader_settings:saveSetting(setting_name, saved_settings)
end

return {
    initializeDefaults = initializeDefaults,
    getSettingForExt = getSettingForExt,
    setSettingForExt = setSettingForExt,
}
