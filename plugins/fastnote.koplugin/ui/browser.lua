--[[--
ui/browser.lua — notebook browser screen.

Shows a scrollable list of notebooks sorted by last_edited (default) or name.
Tap a notebook to open it; long-press for rename/delete context menu.

Usage (from main.lua):
  local Browser = require("ui/browser")
  Browser.show(lib, function(nb) ... end)
--]]--

local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local InputDialog       = require("ui/widget/inputdialog")
local Menu              = require("ui/widget/menu")
local Screen            = require("device").screen
local UIManager         = require("ui/uimanager")
local _                 = require("gettext")

-- ---------------------------------------------------------------------------
-- Module-level session state (one browser open at a time)
-- ---------------------------------------------------------------------------

local _sort_by      = "last_edited"   -- "last_edited" | "name"; session-only
local _current_menu = nil

local M = {}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function _close_menu()
    if _current_menu then
        UIManager:close(_current_menu)
        _current_menu = nil
    end
end

local function _date_str(ts)
    if not ts or ts == 0 then return "" end
    return os.date("%b %d", ts)
end

local function _sorted_nbs(lib)
    local nbs = lib:all()
    if _sort_by == "name" then
        table.sort(nbs, function(a, b) return a.name:lower() < b.name:lower() end)
    else
        table.sort(nbs, function(a, b) return (a.last_edited or 0) > (b.last_edited or 0) end)
    end
    return nbs
end

-- Forward-declare so callbacks can reference it
local _rebuild

local function _context_menu(nb, lib, on_open)
    local dlg
    dlg = ButtonDialogTitle:new{
        title   = nb.name,
        buttons = {{
            {
                text     = _("Rename"),
                callback = function()
                    UIManager:close(dlg)
                    local editor
                    editor = InputDialog:new{
                        title   = _("Rename notebook"),
                        input   = nb.name,
                        buttons = {{
                            {
                                text     = _("Cancel"),
                                callback = function() UIManager:close(editor) end,
                            },
                            {
                                text             = _("Rename"),
                                is_enter_default = true,
                                callback         = function()
                                    local name = editor:getInputText()
                                    UIManager:close(editor)
                                    if name and name ~= "" then
                                        nb:rename(name)
                                        _rebuild(lib, on_open)
                                    end
                                end,
                            },
                        }},
                    }
                    UIManager:show(editor)
                end,
            },
            {
                text     = _("Delete"),
                callback = function()
                    UIManager:close(dlg)
                    local confirm
                    confirm = ButtonDialogTitle:new{
                        title   = string.format(_("Delete \"%s\"?"), nb.name),
                        buttons = {{
                            -- Delete on the left per UX convention
                            {
                                text     = _("Delete"),
                                callback = function()
                                    UIManager:close(confirm)
                                    lib:deleteNotebook(nb.uuid)
                                    _rebuild(lib, on_open)
                                end,
                            },
                            {
                                text     = _("Cancel"),
                                callback = function() UIManager:close(confirm) end,
                            },
                        }},
                    }
                    UIManager:show(confirm)
                end,
            },
        }},
    }
    UIManager:show(dlg)
end

local function _build_items(lib, on_open)
    local items = {}

    -- "New notebook" always first
    items[#items + 1] = {
        text     = _("+ New notebook"),
        callback = function()
            local dlg
            dlg = InputDialog:new{
                title   = _("New notebook name"),
                input   = _("Untitled"),
                buttons = {{
                    {
                        text     = _("Cancel"),
                        callback = function() UIManager:close(dlg) end,
                    },
                    {
                        text             = _("Create"),
                        is_enter_default = true,
                        callback         = function()
                            local name = dlg:getInputText()
                            UIManager:close(dlg)
                            if name and name ~= "" then
                                local nb = lib:createNotebook(name)
                                _close_menu()
                                on_open(nb)
                            end
                        end,
                    },
                }},
            }
            UIManager:show(dlg)
        end,
    }

    -- Sort toggle
    local sort_lbl = (_sort_by == "name")
        and _("Sort: A\xe2\x86\x92Z  \xc2\xb7 tap to switch")
        or  _("Sort: Recent  \xc2\xb7 tap to switch")
    items[#items + 1] = {
        text     = sort_lbl,
        callback = function()
            _sort_by = (_sort_by == "name") and "last_edited" or "name"
            _rebuild(lib, on_open)
        end,
    }

    -- Notebook rows
    local nbs = _sorted_nbs(lib)
    for _, nb in ipairs(nbs) do
        local pc   = nb:pageCount()
        local pstr = pc == 1 and _("1 page") or string.format(_("%d pages"), pc)
        local dstr = _date_str(nb.last_edited)
        local text = nb.name .. "   " .. pstr
        if dstr ~= "" then text = text .. "   \xc2\xb7 " .. dstr end
        local nb_ref = nb
        items[#items + 1] = {
            text          = text,
            callback      = function()
                _close_menu()
                on_open(nb_ref)
            end,
            hold_callback = function()
                _context_menu(nb_ref, lib, on_open)
            end,
        }
    end

    return items
end

_rebuild = function(lib, on_open)
    _close_menu()
    _current_menu = Menu:new{
        title         = _("Notebooks"),
        items         = _build_items(lib, on_open),
        is_borderless = true,
        is_popout     = false,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
    }
    UIManager:show(_current_menu)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Show the notebook browser.
-- @param lib           Library instance
-- @param on_open_notebook  callback(nb) called when user selects a notebook
function M.show(lib, on_open_notebook)
    _rebuild(lib, on_open_notebook)
end

--- Close the browser (if open) without opening a notebook.
function M.close()
    _close_menu()
end

return M
