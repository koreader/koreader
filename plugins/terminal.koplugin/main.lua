local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
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
local N_ = _.ngettext
local Screen = require("device").screen
local T = util.template

local Terminal = WidgetContainer:new{
    name = "terminal",
    command = "",
    dump_file = util.realpath(DataStorage:getDataDir()) .. "/terminal_output.txt",
    items_per_page = 16,
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/terminal_shortcuts.lua"),
    shortcuts_dialog = nil,
    shortcuts_menu = nil,
    --    shortcuts_file = DataStorage:getSettingsDir() .. "/terminal_shortcuts.lua",
    shortcuts = {},
    source = "terminal",
}

function Terminal:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_terminal", { category = "none", event = "TerminalStart", title = _("Show terminal"), device = true, })
end

function Terminal:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.items_per_page = G_reader_settings:readSetting("items_per_page") or 16
    self.shortcuts = self.settings:readSetting("shortcuts", {})
end

function Terminal:saveShortcuts()
    self.settings:flush()
    UIManager:show(InfoMessage:new{
        text = _("Shortcuts saved"),
        timeout = 2
    })
end

function Terminal:manageShortcuts()
    self.shortcuts_dialog = CenterContainer:new {
        dimen = Screen:getSize(),
    }
    self.shortcuts_menu = Menu:new{
        show_parent = self.ui,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
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
                    self.source = "shortcut"
                    -- execute immediately, skip terminal dialog:
                    self.command = self:ensureWhitelineAfterCommands(f.commands)
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
                    text = " ",
                    deletable = false,
                    editable = false,
                    callback = function()
                        self:manageShortcuts()
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
    local title = N_("Terminal shortcut", "Terminal shortcuts", #self.shortcuts)
    self.shortcuts_menu:switchItemTable(tostring(#self.shortcuts) .. " " .. title, item_table)
    UIManager:show(self.shortcuts_dialog)
end

function Terminal:insertPageActions(item_table)
    table.insert(item_table, {
        text = "   " .. _("to terminal…"),
        deletable = false,
        editable = false,
        callback = function()
            self:terminal()
        end,
    })
    table.insert(item_table, {
        text = "   " .. _("close…"),
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
        shortcut_shortcuts_dialog = ButtonDialog:new{
            buttons = {{
                {
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
            },
            {
                {
                    text = _("Copy"),
                    enabled = item.editable,
                    callback = function()
                        UIManager:close(shortcut_shortcuts_dialog)
                        if self._manager.shortcuts_dialog ~= nil then
                            UIManager:close(self._manager.shortcuts_dialog)
                            self._manager.shortcuts_dialog = nil
                        end
                        self._manager:copyCommands(item)
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
                }
            }}
        }
        UIManager:show(shortcut_shortcuts_dialog)
        return true
    end
end

function Terminal:copyCommands(item)
    local new_item = {
        text = item.text .. " (copy)",
        commands = item.commands
    }
    table.insert(self.shortcuts, new_item)
    UIManager:show(InfoMessage:new{
        text = _("Shortcut copied"),
        timeout = 2
    })
    self:saveShortcuts()
    self:manageShortcuts()
end

function Terminal:editCommands(item)
    local edit_dialog
    edit_dialog = InputDialog:new{
        title = T(_('Edit commands for "%1"'), item.text),
        input = item.commands,
        width = Screen:getWidth() * 0.9,
        para_direction_rtl = false, -- force LTR
        input_type = "string",
        allow_newline = true,
        cursor_at_end = true,
        fullscreen = true,
        buttons = {{{
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
                      if input:match("[A-Za-z]") then
                          self.shortcuts[item.nr]["commands"] = input
                          self:saveShortcuts()
                          self:manageShortcuts()
                      end
                  end,
              }}},
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
end

function Terminal:editName(item)
    local edit_dialog
    edit_dialog = InputDialog:new{
        title = _("Edit name"),
        input = item.text,
        width = Screen:getWidth() * 0.9,
        para_direction_rtl = false, -- force LTR
        input_type = "string",
        allow_newline = false,
        cursor_at_end = true,
        fullscreen = true,
        buttons = {{{
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
                  if input:match("[A-Za-z]") then
                      self.shortcuts[item.nr]["text"] = input
                      self:saveShortcuts()
                      self:manageShortcuts()
                  end
              end,
          }}},
    }
    UIManager:show(edit_dialog)
    edit_dialog:onShowKeyboard()
end

function Terminal:deleteShortcut(item)
    for i = #self.shortcuts, 1, -1 do
        local element = self.shortcuts[i]
        if element.text == item.text and element.commands == item.commands then
            table.remove(self.shortcuts, i)
        end
    end
    self:saveShortcuts()
    self:manageShortcuts()
end

function Terminal:onTerminalStart()
    -- if shortcut commands are defined, go directly to the the shortcuts manager (so we can execute scripts more quickly):
    if #self.shortcuts == 0 then
        self:terminal()
    else
        self:manageShortcuts()
    end
end

function Terminal:terminal()
    self.input = InputDialog:new{
        title = _("Enter a command and press \"Execute\""),
        input = self.command:gsub("\n+$", ""),
        para_direction_rtl = false, -- force LTR
        input_type = "string",
        allow_newline = true,
        cursor_at_end = true,
        fullscreen = true,
        buttons = {{{
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
                  if input:match("[A-Za-z]") then

                      local function callback(name)
                          local new_shortcut = {
                              text = name,
                              commands = input,
                          }
                          table.insert(self.shortcuts, new_shortcut)
                          self:saveShortcuts()
                      end

                      local prompt
                      prompt = InputDialog:new{
                          title = _("Name"),
                          input = "",
                          input_type = "text",
                          fullscreen = true,
                          condensed = true,
                          allow_newline = false,
                          cursor_at_end = true,
                          buttons = {{{
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
                          }}}
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
                  self.source = "terminal"
                  self.command = self:ensureWhitelineAfterCommands(self.input:getInputText())
                  Trapper:wrap(function()
                      self:execute()
                  end)
              end,
          }}},
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

-- for prettier formatting of output by separating commands and result thereof with a whiteline:
function Terminal:ensureWhitelineAfterCommands(commands)
    if string.sub(commands, -1) ~= "\n" then
        commands = commands .. "\n"
    end
    return commands
end

function Terminal:execute()
    local wait_msg = InfoMessage:new{
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
    local back_button = {
        text = _("Back"),
        callback = function()
            UIManager:close(viewer)
            if self.source == "terminal" then
                self:terminal()
            else
                self:manageShortcuts()
            end
        end,
    }
    local close_button = {
        text = _("Close"),
        callback = function()
            UIManager:close(viewer)
        end,
    }
    if self.source == "terminal" then
        buttons_table = {
            {
                back_button,
                {
                    text = _("Shortcuts"),
                    -- switch to shortcuts:
                    callback = function()
                        UIManager:close(viewer)
                        self:manageShortcuts()
                    end,
                },
                close_button,
            },
        }
    else
        buttons_table = {
            {
                back_button,
                {
                    text = _("Terminal"),
                    -- switch to terminal:
                    callback = function()
                        UIManager:close(viewer)
                        self:terminal()
                    end,
                },
                close_button,
            },
        }
    end
    viewer = TextViewer:new{
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
