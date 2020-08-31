local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local Screen = require("device").screen

local Terminal = WidgetContainer:new {
    name = "terminal",
    dump_file = util.realpath(DataStorage:getDataDir()) .. "/terminal_output.txt",
    command = "",
    items_per_page = G_reader_settings:readSetting("items_per_page") or 16,
    source = 'terminal',
    shortcuts_dialog = nil,
    shortcuts_menu = nil,
    shortcuts_file = DataStorage:getSettingsDir() .. "/terminal_shortcuts.lua",
    shortcuts = {},
}

function Terminal:init()
    self.ui.menu:registerToMainMenu(self)
    self:createSettingsFileIfNotExists()
    local file_handle = LuaSettings:open(self.shortcuts_file)
    self.shortcuts = file_handle:readSetting("shortcuts") or {}
end

function Terminal:createSettingsFileIfNotExists()
    if not lfs.attributes(self.shortcuts_file) then
        local file = io.open(self.shortcuts_file, "w")
        local content = "-- we can read Lua syntax here!\nreturn {}\n"
        if file then
            file:write(content)
            file:close()
        end
    end
end

function Terminal:saveShortcuts()
    local file = io.open(self.shortcuts_file, "w")
    local dump = require("dump")
    local content = "-- we can read Lua syntax here!\nreturn "
    local wrapper = {
        shortcuts = self.shortcuts
    }
    content = content .. dump(wrapper) .. "\n"
    if file then
        file:write(content)
        file:close()
        UIManager:show(InfoMessage:new {
            text = _("Shortcuts saved!"),
            timeout = 3
        })
    end
end

function Terminal:manageShortcuts()
    self.shortcuts_dialog = CenterContainer:new {
        dimen = Screen:getSize(),
    }
    self.shortcuts_menu = Menu:new {
        width = Screen:getWidth() - 70,
        height = Screen:getHeight() - 120,
        show_parent = self.ui,
        is_popout = true,
        is_borderless = false,
        cface = Font:getFace("smallinfofont"),
        perpage = self.items_per_page,
        onMenuHold = self.onMenuHoldShortcuts,
        _manager = self,
    }
    table.insert(self.shortcuts_dialog, self.shortcuts_menu)
    self.shortcuts_menu.close_callback = function()
        UIManager:close(self.shortcuts_dialog)
    end

    -- sort the shortcuts:
    if #self.shortcuts > 0 then
        table.sort(self.shortcuts, function(v1, v2)
            return v1.text < v2.text
        end)
    end
    self:updateItemTable()
end

function Terminal:updateItemTable()
    local item_table = {}
    if #self.shortcuts > 0 then
        local actions_count = 3 -- separator + actions
        for nr, f in ipairs(self.shortcuts) do
            local item = {
                nr = nr,
                text = f.text,
                commands = f.commands,
                editable = true,
                deletable = true,
                callback = function()
                    -- so we know which middle button to display in the results:
                    self.source = 'shortcut'
                    -- execute immediately, skip terminal dialog:
                    self.command = f.commands
                    Trapper:wrap(function()
                        self:execute()
                    end)
                end
            }
            table.insert(item_table, item)
            -- add page actions at end of each page with shortcuts:
            local factor = self.items_per_page - actions_count
            if nr % factor == 0 or nr == #self.shortcuts then
                -- insert "separator":
                table.insert(item_table, {
                    text = ' ',
                    deletable = false,
                    editable = false,
                    callback = function()
                        self:onTerminalStart()
                    end,
                })
                -- actions:
                self:insertPageActions(item_table)
            end
        end
        -- no shortcuts defined yet:
    else
        self:insertPageActions(item_table)
    end
    self.shortcuts_menu:switchItemTable(tostring(#self.shortcuts) .. ' ' .. _("Shortcuts"), item_table)
    UIManager:show(self.shortcuts_dialog)
end

function Terminal:insertPageActions(item_table)
    table.insert(item_table, {
        text = "   " .. string.lower(_("to terminal")) .. "...",
        deletable = false,
        editable = false,
        callback = function()
            self:onTerminalStart()
        end,
    })
    table.insert(item_table, {
        text = "   " .. string.lower(_("Close")) .. "...",
        deletable = false,
        editable = false,
        callback = function()
            return false
        end,
    })
end

function Terminal:onMenuHoldShortcuts(item)
    if item.deletable or item.editable then
        local shortcut_shortcuts_dialog
        shortcut_shortcuts_dialog = ButtonDialog:new {
            buttons = { { {
                              text = _("Edit name"),
                              enabled = item.editable,
                              callback = function()
                                  UIManager:close(shortcut_shortcuts_dialog)
                                  if self._manager.shortcuts_dialog ~= nil then
                                      UIManager:close(self._manager.shortcuts_dialog)
                                      self._manager.shortcuts_dialog = nil
                                  end
                                  self._manager:editName(item)
                              end
                          },
                          {
                              text = _("Edit commands"),
                              enabled = item.editable,
                              callback = function()
                                  UIManager:close(shortcut_shortcuts_dialog)
                                  if self._manager.shortcuts_dialog ~= nil then
                                      UIManager:close(self._manager.shortcuts_dialog)
                                      self._manager.shortcuts_dialog = nil
                                  end
                                  self._manager:editCommands(item)
                              end
                          },
                          {
                              text = _("Delete"),
                              enabled = item.deletable,
                              callback = function()
                                  UIManager:close(shortcut_shortcuts_dialog)
                                  if self._manager.shortcuts_dialog ~= nil then
                                      UIManager:close(self._manager.shortcuts_dialog)
                                      self._manager.shortcuts_dialog = nil
                                  end
                                  self._manager:deleteShortcut(item)
                              end
                          } } }
        }
        UIManager:show(shortcut_shortcuts_dialog)
        return true
    end
end

function Terminal:editCommands(item)
    local edit_dialog
    edit_dialog = InputDialog:new {
        title = _("Edit commands for") .. " " .. item.text,
        input = item.commands,
        width = Screen:getWidth() * 0.9,
        para_direction_rtl = false, -- force LTR
        text_height = math.floor(Screen:getHeight() * 0.4),
        input_type = "string",
        allow_newline = true,
        cursor_at_end = true,
        buttons = { { {
                          text = _("Cancel"),
                          callback = function()
                              UIManager:close(edit_dialog)
                              edit_dialog = nil
                              self:manageShortcuts()
                          end,
                      }, {
                          text = _("Save"),
                          callback = function()
                              local input = edit_dialog:getInputText()
                              UIManager:close(edit_dialog)
                              edit_dialog = nil
                              if input:match('[A-Za-z]') then
                                  self.shortcuts[item.nr]['commands'] = input
                                  self:saveShortcuts()
                                  self:manageShortcuts()
                              end
                          end,
                      } } },
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
end

function Terminal:editName(item)
    local edit_dialog
    edit_dialog = InputDialog:new {
        title = _("Edit name"),
        input = item.text,
        width = Screen:getWidth() * 0.9,
        para_direction_rtl = false, -- force LTR
        text_height = math.floor(Screen:getHeight() * 0.4),
        input_type = "string",
        allow_newline = false,
        cursor_at_end = true,
        buttons = { { {
                          text = _("Cancel"),
                          callback = function()
                              UIManager:close(edit_dialog)
                              edit_dialog = nil
                              self:manageShortcuts()
                          end,
                      }, {
                          text = _("Save"),
                          callback = function()
                              local input = edit_dialog:getInputText()
                              UIManager:close(edit_dialog)
                              edit_dialog = nil
                              if input:match('[A-Za-z]') then
                                  self.shortcuts[item.nr]['text'] = input
                                  self:saveShortcuts()
                                  self:manageShortcuts()
                              end
                          end,
                      } } },
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
end

function Terminal:deleteShortcut(item)
    local shortcuts = {}
    for _, element in ipairs(self.shortcuts) do
        if element.text ~= item.text and element.commands ~= item.commands then
            table.insert(shortcuts, element)
        end
    end
    self.shortcuts = shortcuts
    self:saveShortcuts()
    self:manageShortcuts()
end

function Terminal:onTerminalStart()
    self.input = InputDialog:new {
        title = _("Enter a command and press \"Execute\""),
        input = self.command,
        para_direction_rtl = false, -- force LTR
        text_height = math.floor(Screen:getHeight() * 0.4),
        input_type = "string",
        allow_newline = true,
        cursor_at_end = true,
        buttons = { { {
                          text = _("Cancel"),
                          callback = function()
                              UIManager:close(self.input)
                          end,
                      }, {
                          text = _("Shortcuts"),
                          callback = function()
                              UIManager:close(self.input)
                              self:manageShortcuts()
                          end,
                      }, {
                          text = _("Save"),
                          callback = function()
                              local input = self.input:getInputText()
                              if input:match('[A-Za-z]') then

                                  local function callback(name)
                                      local new_fav = {
                                          text = name,
                                          commands = input,
                                      }
                                      table.insert(self.shortcuts, new_fav)
                                      self:saveShortcuts()
                                  end

                                  local prompt
                                  prompt = InputDialog:new {
                                      title = _("Name"),
                                      input = '',
                                      input_type = "text",
                                      description = _("Name for this (set of) command(s)"),
                                      fullscreen = true,
                                      condensed = true,
                                      allow_newline = false,
                                      cursor_at_end = false,
                                      buttons = {
                                          {
                                              {
                                                  text = _("Cancel"),
                                                  callback = function()
                                                      UIManager:close(prompt)
                                                  end,
                                              },
                                              {
                                                  text = _("Save"),
                                                  is_enter_default = true,
                                                  callback = function()
                                                      local newval = prompt:getInputText()
                                                      UIManager:close(prompt)
                                                      callback(newval)
                                                  end,
                                              },
                                          }
                                      },
                                  }
                                  UIManager:show(prompt)
                                  prompt:onShowKeyboard()
                              end
                          end,
                      }, {
                          text = _("Execute"),
                          callback = function()
                              UIManager:close(self.input)
                              -- so we know which middle button to display in the results:
                              self.source = 'terminal'
                              self.command = self.input:getInputText()
                              Trapper:wrap(function()
                                  self:execute()
                              end)
                          end,
                      } } },
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

function Terminal:execute()
    local wait_msg = InfoMessage:new {
        text = _("Executing…"),
    }
    UIManager:show(wait_msg)
    local entries = { self.command }
    local command = self.command .. " 2>&1 ; echo" -- ensure we get stderr and output something
    local completed, result_str = Trapper:dismissablePopen(command, wait_msg)
    if completed then
        table.insert(entries, result_str)
        self:dump(entries)
        table.insert(entries, _("Output was also written to"))
        table.insert(entries, self.dump_file)
    else
        table.insert(entries, _("Execution canceled."))
    end
    UIManager:close(wait_msg)
    local viewer
    local buttons_table
    if self.source == 'terminal' then
        buttons_table = {
            {
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(viewer)
                        if self.source == 'terminal' then
                            self:onTerminalStart()
                        else
                            self:manageShortcuts()
                        end
                    end,
                },
                {
                    text = _("Shortcuts"),
                    callback = function()
                        UIManager:close(viewer)
                        self:manageShortcuts()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        }
    else
        buttons_table = {
            {
                {
                    text = _("Back"),
                    callback = function()
                        UIManager:close(viewer)
                        if self.source == 'terminal' then
                            self:onTerminalStart()
                        else
                            self:manageShortcuts()
                        end
                    end,
                },
                {
                    text = _("Terminal"),
                    callback = function()
                        UIManager:close(viewer)
                        self:onTerminalStart()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        }
    end
    viewer = TextViewer:new {
        title = _("Command output"),
        text = table.concat(entries, "\n"),
        justified = false,
        text_face = Font:getFace("smallinfont"),
        buttons_table = buttons_table,
    }
    UIManager:show(viewer)
end

function Terminal:dump(entries)
    local content = table.concat(entries, "\n")
    local file = io.open(self.dump_file, "w")
    if file then
        file:write(content)
        file:close()
    else
        logger.warn("Failed to dump terminal output " .. content .. " to " .. self.dump_file)
    end
end

function Terminal:addToMainMenu(menu_items)
    menu_items.terminal = {
        text = _("Terminal emulator"),
        keep_menu_open = true,
        callback = function()
            self:onTerminalStart()
        end,
    }
end

return Terminal
