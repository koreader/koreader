local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local ui = require("apps/reader/readerui").instance

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
                return ui.view:isOverlapAllowed() and ui.view.page_overlap_enable
            end,
            callback = function()
                if ui.view:isOverlapAllowed() then
                    if ui.view.page_overlap_enable then
                        ui.view.dim_area:clear()
                    end
                    ui.view.page_overlap_enable = not ui.view.page_overlap_enable
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
        {
            text_func = function()
                return T(_("Number of overlapped lines: %1"), G_reader_settings:readSetting("copt_overlap_lines") or 1)
            end,
            enabled_func = function()
                return not ui.document.info.has_pages -- ReaderMenu is registered before paging/rolling
                    and ui.view:isOverlapAllowed() and ui.view.page_overlap_enable
            end,
            keep_menu_open = true,
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
        },
        -- styles
    },
}

local styles, style_texts = ui.view.getOverlapStyles()
for i, style in ipairs(styles) do
    table.insert(PageOverlap.sub_item_table, {
        text_func = function()
            local text = style_texts[i]
            if G_reader_settings:readSetting("page_overlap_style") == style then
                text = text .. "   ★"
            end
            return text
        end,
        enabled_func = function()
            return ui.view:isOverlapAllowed() and ui.view.page_overlap_enable
        end,
        checked_func = function()
            return ui.view.page_overlap_style == style
        end,
        radio = true,
        callback = function()
            ui.view:onSetOverlapStyle(style, true) -- no notification
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("page_overlap_style", style)
            touchmenu_instance:updateItems()
        end,
    })
end

return PageOverlap
