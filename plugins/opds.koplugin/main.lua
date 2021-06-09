local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local OPDS = WidgetContainer:new{
    name = "opds",
    is_doc_only = false,
}

function OPDS:onDispatcherRegisterActions()
    Dispatcher:registerAction("opds_show_catalog",
        {category="none", event="ShowOPDSCatalog", title=_("OPDS Catalog"), filemanager=true,}
    )
end

function OPDS:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function OPDS:showCatalog()
    local OPDSCatalog = require("opdscatalog")
    local filemanagerRefresh = function() self.ui:onRefresh() end
    function OPDSCatalog:onClose()
        UIManager:close(self)
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then
            filemanagerRefresh()
        else
            FileManager:showFiles(G_reader_settings:readSetting("download_dir"))
        end
    end
    OPDSCatalog:showCatalog()
end

function OPDS:onShowOPDSCatalog()
    self:showCatalog()
    return true
end

function OPDS:addToMainMenu(menu_items)
    if not self.ui.view then
        menu_items.opds = {
            text = _("OPDS catalog"),
            sorting_hint = "search",
            callback = function() self:showCatalog() end
        }
    end
end

return OPDS
