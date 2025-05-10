local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KoboBooks = WidgetContainer:extend{
    name = "kobobooks",
    is_doc_only = false, -- show in the menu even if no book is open in the reader
}

function KoboBooks:init()
    self.ui.menu:registerToMainMenu(self)
end

function KoboBooks:showCatalog()
    local KoboCatalog = require("kobocatalog")
    KoboCatalog:showCatalog()
end

function KoboBooks:addToMainMenu(menu_items)
	menu_items.kobobooks = {
		text = _("Kobo books"),
        sorting_hint = "main", -- in which menu this should be appended
		callback = function() self:showCatalog() end
	}
end

return KoboBooks
