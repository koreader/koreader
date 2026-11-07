local PageTurnEffect = require("ui/pageturneffect")
local _ = require("gettext")

local function currentUI(menu)
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok and ReaderUI and ReaderUI.instance then
        return ReaderUI.instance
    end
    return menu and menu.ui
end

return function(menu)
    if not PageTurnEffect.enabled() then
        return nil
    end

    local sub_item_table = {}
    for _, opt in ipairs(PageTurnEffect.OPTIONS) do
        table.insert(sub_item_table, {
            text = opt.text,
            checked_func = function()
                return PageTurnEffect.resolve(currentUI(menu)) == opt.id
            end,
            radio = true,
            callback = function()
                PageTurnEffect.set(currentUI(menu), opt.id)
            end,
        })
    end

    return {
        text = _("Page-turn animation"),
        help_text = _("Page-turn animation for this document. Use “Save document settings as default” to apply the current choice to new documents."),
        sub_item_table = sub_item_table,
    }
end
