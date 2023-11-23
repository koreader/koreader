local datetime = require("datetime")
local DocSettings = require("docsettings")
local ffiUtil = require("ffi/util")
local sort = require("sort")
local util = require("util")
local _ = require("gettext")

local FileManagerCollate = {
    collate_by_id = nil
}

function FileManagerCollate.getCollates()
    return {
        {
            id = "strcoll",
            text = _("name"),
            can_collate_mixed = true,
            init_sort_func = function(cache)
                return function(a, b)
                    return ffiUtil.strcoll(a.text, b.text)
                end, cache
            end,
        },
        {
            id = "natural",
            text = _("name (natural sorting)"),
            can_collate_mixed = true,
            init_sort_func = function(cache)
                local natsort
                natsort, cache = sort.natsort_cmp(cache)
                return function(a, b)
                    return natsort(a.text, b.text)
                end, cache
            end
        },
        {
            id = "access",
            text = _("last read date"),
            can_collate_mixed = true,
            init_sort_func = function(cache)
                return function(a, b)
                    return a.attr.access > b.attr.access
                end, cache
            end,
            mandatory_func = function(item)
                return datetime.secondsToDateTime(item.attr.access)
            end,
        },
        {
            id = "date",
            text = _("date modified"),
            can_collate_mixed = true,
            init_sort_func = function(cache)
                return function(a, b)
                    return a.attr.modification > b.attr.modification
                end, cache
            end,
            mandatory_func = function(item)
                return datetime.secondsToDateTime(item.attr.modification)
            end,
        },
        {
            id = "size",
            text = _("size"),
            can_collate_mixed = false,
            init_sort_func = function(cache)
                return function(a, b)
                    return a.attr.size < b.attr.size
                end, cache
            end,
        },
        {
            id = "type",
            text = _("type"),
            can_collate_mixed = false,
            init_sort_func = function(cache)
                return function(a, b)
                    if (a.suffix or b.suffix) and a.suffix ~= b.suffix then
                        return ffiUtil.strcoll(a.suffix, b.suffix)
                    end
                    return ffiUtil.strcoll(a.text, b.text)
                end, cache
            end,
            item_func = function(item)
                item.suffix = util.getFileNameSuffix(item.text)
                return item
            end,
        },
        {
            id = "percent_unopened_first",
            text = _("percent - unopened first"),
            can_collate_mixed = false,
            init_sort_func = function(cache)
                return function(a, b)
                    if a.opened == b.opened then
                        if a.opened then
                            return a.percent_finished < b.percent_finished
                        end
                        return ffiUtil.strcoll(a.text, b.text)
                    end
                    return b.opened
                end, cache
            end,
            item_func = function(item)
                local percent_finished
                item.opened = DocSettings:hasSidecarFile(item.fullpath)
                if item.opened then
                    local doc_settings = DocSettings:open(item.fullpath)
                    percent_finished = doc_settings:readSetting("percent_finished")
                end
                item.percent_finished = percent_finished or 0
                return item
            end,
            mandatory_func = function(item)
                return item.opened and string.format("%d %%", 100 * item.percent_finished) or "–"
            end,
        },
        {
            id = "percent_unopened_last",
            text = _("percent - unopened last"),
            can_collate_mixed = false,
            init_sort_func = function(cache)
                return function(a, b)
                    if a.opened == b.opened then
                        if a.opened then
                            return a.percent_finished < b.percent_finished
                        end
                        return ffiUtil.strcoll(a.text, b.text)
                    end
                    return a.opened
                end, cache
            end,
            item_func = function(item)
                local percent_finished
                item.opened = DocSettings:hasSidecarFile(item.fullpath)
                if item.opened then
                    local doc_settings = DocSettings:open(item.fullpath)
                    percent_finished = doc_settings:readSetting("percent_finished")
                end
                item.percent_finished = percent_finished or 0
                return item
            end,
            mandatory_func = function(item)
                return item.opened and string.format("%d %%", 100 * item.percent_finished) or "–"
            end,
        },
    }
end

function FileManagerCollate:getCollateById(id)
    if self.collate_by_id == nil then
        self.collate_by_id = {}
        for i, c in ipairs(self.getCollates()) do
            self.collate_by_id[c.id] = c
        end
    end
    return self.collate_by_id[id]
end

function FileManagerCollate:getCurrentCollate()
    local collate_id = G_reader_settings:readSetting("collate", "strcoll")
    local collate = self:getCollateById(collate_id)
    if collate ~= nil then
        return collate, collate_id
    else
        G_reader_settings:saveSetting("collate", "strcoll")
        return self:getCollateById("strcoll"), "strcoll"
    end
end

return FileManagerCollate
