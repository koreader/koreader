local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local Cloud = WidgetContainer:extend{
    name = "cloudstorageplus",
    title = _("Cloud storage+"),
    settings = nil,
    servers = nil, -- user cloud storages (array)
    providers = nil, -- cloud providers (hash table); must provide at least .config and .run
}

function Cloud:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/cloudstorage.lua")
    if next(self.settings.data) == nil then
        self.updated = true -- first run, force flush
    end
    self.servers = self.settings:readSetting("cs_servers", {})
    self:getProviders()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Cloud:getProviders()
    -- in the base class to keep across views
    if Cloud.providers == nil then
        Cloud.providers = {}
        util.findFiles(self.path .. "/providers", function(fullpath, filename)
            if filename:match("%.lua$") then
                local ok, provider = pcall(dofile, fullpath)
                if ok and next(provider) and provider.name and provider.config and provider.run then
                    Cloud.providers[filename:sub(1, -5)] = provider
                end
            end
        end, false)
    end
end

function Cloud:onDispatcherRegisterActions()
    Dispatcher:registerAction("cloudstorageplus", { category="none", event="ShowCloudStoragePlus", title=self.title, general=true })
end

function Cloud:addToMainMenu(menu_items)
    menu_items.cloud_storage_plus = {
        text = self.title,
        callback = function()
            self:onShowCloudStoragePlus()
        end,
    }
end

function Cloud:onShowCloudStoragePlus()
    local base
    local CloudStorage = require("cloudstorageplus")
    base = CloudStorage:new{
        title = self.title,
        subtitle = "",
        settings = self.settings,
        servers = self.servers,
        providers = self.providers,
        _manager = self,
        close_callback = function()
            if base.choose_folder_callback then
                base:init(true)
                UIManager:show(base)
            else
                local download_dir = self.settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
                local fc = self.ui.file_chooser
                if fc and fc.path == download_dir then
                    fc:refreshPath()
                end
            end
        end,
    }
    for _, provider in pairs(self.providers) do
        provider.base = base
    end
    UIManager:show(base)
end

function Cloud:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

function Cloud:stopPlugin()
    Cloud.providers = nil
end

return Cloud
