local FFIUtil = require("ffi/util")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = FFIUtil.template

local PageOverlap = {
    text = _("Page overlap"),
    sub_item_table = {
        {
            text_func = function()
                local text = _("Page overlap")
                if G_reader_settings:isTrue("page_overlap_enable") then
                    text = text .. "   ★"
                end
                return text
            end,
            checked_func = function()
                return ReaderUI.instance.view:isOverlapAllowed() and ReaderUI.instance.view.page_overlap_enable
            end,
            callback = function()
                local view = ReaderUI.instance.view
                if view:isOverlapAllowed() then
                    if view.page_overlap_enable then
                        view.dim_area:clear()
                    end
                    view.page_overlap_enable = not view.page_overlap_enable
                else
                    UIManager:show(require("ui/widget/infomessage"):new{
                        text = _("Page overlap cannot be enabled in the current view mode."),
                        timeout = 2,
                    })
                end
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:flipNilOrFalse("page_overlap_enable")
                touchmenu_instance:updateItems()
            end,
        },
    }
}

table.insert(PageOverlap.sub_item_table, {
    keep_menu_open = true,
    text_func = function()
        return T(_("Number of lines: %1"), G_reader_settings:readSetting("copt_overlap_lines") or 1)
    end,
    enabled_func = function()
        return not ReaderUI.instance.document.info.has_pages and
            ReaderUI.instance.view:isOverlapAllowed() and ReaderUI.instance.view.page_overlap_enable
    end,
    callback = function(touchmenu_instance)
        local SpinWidget = require("ui/widget/spinwidget")
        UIManager:show(SpinWidget:new{
            title_text =  _("Number of overlapped lines"),
            info_text = _([[
When page overlap is enabled, some lines from the previous page will be displayed on the next page.
You can set how many lines are shown.]]),
            value = G_reader_settings:readSetting("copt_overlap_lines") or 1,
            value_min = 1,
            value_max = 10,
            default_value = 1,
            precision = "%d",
            callback = function(spin)
                G_reader_settings:saveSetting("copt_overlap_lines", spin.value)
                touchmenu_instance:updateItems()
            end,
        })
    end,
    separator = true,
})

local page_overlap_styles = {
    {_("Arrow"), "arrow"},
    {_("Gray out"), "dim"},
    {_("Solid line"), "line"},
    {_("Dashed line"), "dashed_line"},
}
for _, v in ipairs(page_overlap_styles) do
    local style_text, style = unpack(v)
    table.insert(PageOverlap.sub_item_table, {
        text_func = function()
            local text = style_text
            if G_reader_settings:readSetting("page_overlap_style") == style then
                text = text .. "   ★"
            end
            return text
        end,
        enabled_func = function()
            return ReaderUI.instance.view:isOverlapAllowed() and ReaderUI.instance.view.page_overlap_enable
        end,
        checked_func = function()
            return ReaderUI.instance.view.page_overlap_style == style
        end,
        radio = true,
        callback = function()
            ReaderUI.instance.view.page_overlap_style = style
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("page_overlap_style", style)
            touchmenu_instance:updateItems()
        end,
    })
end

return PageOverlap
