local Device = require("device")

if not Device:isTouchDevice() then
    return { disabled = true }
end

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local QRMessage = require("ui/widget/qrmessage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Notification = require("ui/widget/notification")
local PathChooser = require("ui/widget/pathchooser")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = ffiutil.template

local TextEditor = WidgetContainer:new{
    name = "texteditor",
    settings_file = DataStorage:getSettingsDir() .. "/text_editor.lua",
    settings = nil, -- loaded only when needed
    -- how many to display in menu (10x3 pages minus our 3 default menu items):
    history_menu_size = 27,
    history_keep_size = 60, -- hom many to keep in settings
    normal_font = "x_smallinfofont",
    monospace_font = "infont",
    default_font_size = 20, -- x_smallinfofont default size
    min_file_size_warn = 200000, -- warn/ask when opening files bigger than this
}

function TextEditor:onDispatcherRegisterActions()
    Dispatcher:registerAction("edit_last_edited_file", { category = "none", event = "OpenLastEditedFile", title = _("Text editor: open last file"), device = true, separator = true})
end

function TextEditor:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function TextEditor:loadSettings()
    if self.settings then
        return
    end
    self.settings = LuaSettings:open(self.settings_file)
    -- NOTE: addToHistory assigns a new object
    self.history = self.settings:readSetting("history") or {}
    self.last_view_pos = self.settings:readSetting("last_view_pos") or {}
    self.last_path = self.settings:readSetting("last_path") or ffiutil.realpath(DataStorage:getDataDir())
    self.font_face = self.settings:readSetting("font_face") or self.normal_font
    self.font_size = self.settings:readSetting("font_size") or self.default_font_size
    -- The font settings could be saved in G_reader_setting if we want them
    -- to be re-used by default by InputDialog (on certain conditaions,
    -- when fullscreen or condensed or add_nav_bar...)
    --
    -- Allow users to set their prefered font manually in text_editor.lua
    -- (sadly, not via TextEditor itself, as they would be overriden on close)
    if self.settings:has("normal_font") then
        self.normal_font = self.settings:readSetting("normal_font")
    end
    if self.settings:has("monospace_font") then
        self.monospace_font = self.settings:readSetting("monospace_font")
    end
    self.auto_para_direction = self.settings:nilOrTrue("auto_para_direction")
    self.force_ltr_para_direction = self.settings:isTrue("force_ltr_para_direction")
    self.qr_code_export = self.settings:nilOrTrue("qr_code_export")
    self.show_keyboard_on_start = self.settings:nilOrTrue("show_keyboard_on_start")
end

function TextEditor:onFlushSettings()
    if self.settings then
        self.settings:saveSetting("history", self.history)
        self.settings:saveSetting("last_view_pos", self.last_view_pos)
        self.settings:saveSetting("last_path", self.last_path)
        self.settings:saveSetting("font_face", self.font_face)
        self.settings:saveSetting("font_size", self.font_size)
        self.settings:saveSetting("auto_para_direction", self.auto_para_direction)
        self.settings:saveSetting("force_ltr_para_direction", self.force_ltr_para_direction)
        self.settings:saveSetting("qr_code_export", self.qr_code_export)
        self.settings:saveSetting("show_keyboard_on_start", self.show_keyboard_on_start)
        self.settings:flush()
    end
end

function TextEditor:addToMainMenu(menu_items)
    menu_items.text_editor = {
        text = _("Text editor"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function TextEditor:getSubMenuItems()
    self:loadSettings()
    self.whenDoneFunc = nil -- discard reference to previous TouchMenu instance
    local sub_item_table
    sub_item_table = {
        {
            text = _("Settings"),
            sub_item_table = {
                {
                    text_func = function()
                        return T(_("Text font size (%1)"), self.font_size)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local font_size = self.font_size
                        UIManager:show(SpinWidget:new{
                            width = math.floor(Screen:getWidth() * 0.6),
                            value = font_size,
                            value_min = 8,
                            value_max = 26,
                            default_value = self.default_font_size,
                            title_text =  _("Text font size"),
                            callback = function(spin)
                                self.font_size = spin.value
                                touchmenu_instance:updateItems()
                            end,
                        })
                    end,
                },
                {
                    text = _("Use monospace font"),
                    checked_func = function()
                        return self.font_face == self.monospace_font
                    end,
                    callback = function()
                        if self.font_face == self.monospace_font then
                            self.font_face = self.normal_font
                        else
                            self.font_face = self.monospace_font
                        end
                    end,
                    separator = true,
                },
                {
                    text = _("Auto paragraph direction"),
                    help_text = _([[
Detect the direction of each paragraph in the text: align to the right paragraphs in languages such as Arabic and Hebrew…, while keeping other paragraphs aligned to the left.
If disabled, paragraphs align according to KOReader's language default direction.]]),
                    checked_func = function()
                        return self.auto_para_direction
                    end,
                    callback = function()
                        self.auto_para_direction = not self.auto_para_direction
                    end,
                },
                {
                    text = _("Force paragraph direction LTR"),
                    help_text = _([[
Force all text to be displayed Left-To-Right (LTR) and aligned to the left.
Enable this if you are mostly editing code, HTML, CSS…]]),
                    enabled_func = BD.rtlUIText, -- only useful for RTL users editing code
                    checked_func = function()
                        return BD.rtlUIText() and self.force_ltr_para_direction
                    end,
                    callback = function()
                        self.force_ltr_para_direction = not self.force_ltr_para_direction
                    end,
                    separator = true,
                },
                {
                    text = _("Show keyboard on start"),
                    checked_func = function()
                        return self.show_keyboard_on_start
                    end,
                    callback = function()
                        self.show_keyboard_on_start = not self.show_keyboard_on_start
                    end,
                },
                {
                    text = _("Enable QR code export"),
                    help_text = _([[
Export text to QR code, that can be scanned, for example, by a phone.]]),
                    checked_func = function()
                        return self.qr_code_export
                    end,
                    callback = function()
                        self.qr_code_export = not self.qr_code_export
                    end,
                    separator = true,
                },
                {
                    text = _("Clean text editor history"),
                    enabled_func = function()
                        return #self.history > 0
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        UIManager:show(ConfirmBox:new{
                            text = _("Clean text editor history?"),
                            ok_text = _("Clean"),
                            ok_callback = function()
                                self.history = {}
                                self.last_view_pos = {}
                                -- remove history items from the parent menu
                                for j = #sub_item_table, 1, -1 do
                                    if sub_item_table[j]._texteditor_id then
                                        table.remove(sub_item_table)
                                    end
                                end
                                touchmenu_instance:updateItems()
                            end,
                        })
                end,
                },
            },
            separator = true,
        },
        {
            text = _("New file"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:setupWhenDoneFunc(touchmenu_instance)
                self:newFile()
            end,
        },
        {
            text = _("Open file"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:setupWhenDoneFunc(touchmenu_instance)
                self:chooseFile()
            end,
            separator = true,
        },
    }
    for i=1, math.min(#self.history, self.history_menu_size) do
        local file_path = self.history[i]
        local directory, filename = util.splitFilePathName(file_path) -- luacheck: no unused
        table.insert(sub_item_table, {
            text = T("%1. %2", i, BD.filename(filename)),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:setupWhenDoneFunc(touchmenu_instance)
                self:checkEditFile(file_path, true)
            end,
            _texteditor_id = file_path, -- for removal from menu itself
            hold_callback = function(touchmenu_instance)
                -- Show full path and some info, and propose to remove from history
                local text
                local attr = lfs.attributes(file_path)
                if attr then
                    local filesize = util.getFormattedSize(attr.size)
                    local lastmod = os.date("%Y-%m-%d %H:%M", attr.modification)
                    text = T(_("File path:\n%1\n\nFile size: %2 bytes\nLast modified: %3\n\nRemove this file from text editor history?"),
                                BD.filepath(file_path), filesize, lastmod)
                else
                    text = T(_("File path:\n%1\n\nThis file does not exist anymore.\n\nRemove it from text editor history?"),
                                BD.filepath(file_path))
                end
                UIManager:show(ConfirmBox:new{
                    text = text,
                    ok_text = _("Remove"),
                    ok_callback = function()
                        self:removeFromHistory(file_path)
                        -- Also remove from menu itself
                        for j=1, #sub_item_table do
                            if sub_item_table[j]._texteditor_id == file_path then
                                table.remove(sub_item_table, j)
                                break
                            end
                        end
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        })
    end
    return sub_item_table
end

function TextEditor:setupWhenDoneFunc(touchmenu_instance)
    -- This will keep a reference to the TouchMenu instance, that may not
    -- get released if file opening is aborted while in the file selection
    -- widgets and dialogs (quite complicated to call a resetWhenDoneFunc()
    -- in every abort case). But :getSubMenuItems() will release it when
    -- the TextEditor menu is opened again.
    self.whenDoneFunc = function()
        touchmenu_instance.item_table = self:getSubMenuItems()
        touchmenu_instance.page = 1
        touchmenu_instance:updateItems()
    end
end

function TextEditor:execWhenDoneFunc()
    if self.whenDoneFunc then
        self.whenDoneFunc()
        self.whenDoneFunc = nil
    end
end

function TextEditor:removeFromHistory(file_path)
    for i = #self.history, 1, -1 do
        if self.history[i] == file_path then
            table.remove(self.history, i)
        end
    end
    self.last_view_pos[file_path] = nil
end

function TextEditor:addToHistory(file_path)
    local new_history = {}
    table.insert(new_history, file_path)
    -- Trim history and cleanup duplicates
    local seen = {}
    seen[file_path] = true
    while #self.history > 0 and #new_history < self.history_keep_size do
        local item = table.remove(self.history, 1)
        if not seen[item] then
            table.insert(new_history, item)
            seen[item] = true
        end
    end
    self.history = new_history
end

function TextEditor:newFile()
    self:loadSettings()
    UIManager:show(ConfirmBox:new{
        text = _([[To start editing a new file, you will have to:

- First select a folder
- Then enter a name for the new file
- And start editing it

Do you want to proceed?]]),
        ok_text = _("Yes"),
        cancel_text = _("No"),
        ok_callback = function()
            local path_chooser = PathChooser:new{
                select_directory = true,
                select_file = false,
                height = Screen:getHeight(),
                path = self.last_path,
                onConfirm = function(dir_path)
                    local file_input
                    file_input = InputDialog:new{
                        title =  _("Enter filename"),
                        input = dir_path == "/" and "/" or dir_path .. "/",
                        buttons = {{
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(file_input)
                                end,
                            },
                            {
                                text = _("Edit"),
                                callback = function()
                                    local file_path = file_input:getInputText()
                                    UIManager:close(file_input)
                                    -- Remember last_path
                                    self.last_path = file_path:match("(.*)/")
                                    if self.last_path == "" then self.last_path = "/" end
                                    self:checkEditFile(file_path, false, true)
                                end,
                            },
                        }},
                    }
                    UIManager:show(file_input)
                    file_input:onShowKeyboard()
                end,
            }
            UIManager:show(path_chooser)
        end,
    })
end

function TextEditor:chooseFile()
    self:loadSettings()
    local path_chooser = PathChooser:new{
        select_file = true,
        select_directory = false,
        detailed_file_info = true,
        height = Screen:getHeight(),
        path = self.last_path,
        onConfirm = function(file_path)
            -- Remember last_path only when we select a file from it
            self.last_path = file_path:match("(.*)/")
            if self.last_path == "" then self.last_path = "/" end
            self:checkEditFile(file_path)
        end
    }
    UIManager:show(path_chooser)
end

function TextEditor:checkEditFile(file_path, from_history, possibly_new_file)
    self:loadSettings()
    local attr = lfs.attributes(file_path)
    if not possibly_new_file and not attr then
        UIManager:show(ConfirmBox:new{
            text = T(_("This file does not exist anymore:\n\n%1\n\nDo you want to create it and start editing it?"), BD.filepath(file_path)),
            ok_text = _("Create"),
            ok_callback = function()
                -- go again thru there with possibly_new_file=true
                self:checkEditFile(file_path, from_history, true)
            end,
        })
        return
    end
    if attr then
        -- File exists: get its real path with symlink and ../ resolved
        file_path = ffiutil.realpath(file_path)
        attr = lfs.attributes(file_path)
    end
    if attr then -- File exists
        if attr.mode ~= "file" then
            UIManager:show(InfoMessage:new{
                text = T(_("This file is not a regular file:\n\n%1"), BD.filepath(file_path))
            })
            return
        end
        -- Check if file is writable ("r+b" checks that, and does not
        -- update the last mod timestamp, unlike "wb")
        -- No need to warn if readonly, the user will know it when we open
        -- without keyboard and the Save button says "Read only".
        local readonly = true
        local file = io.open(file_path, 'r+b')
        if file then
            file:close()
            readonly = false
        end
        -- Don't check size if coming from history: user had already confirmed it
        if not from_history and attr.size > self.min_file_size_warn then
            UIManager:show(ConfirmBox:new{
                text = T(_("This file is %2:\n\n%1\n\nAre you sure you want to open it?\n\nOpening big files may take some time."),
                    BD.filepath(file_path), util.getFriendlySize(attr.size)),
                ok_text = _("Open"),
                ok_callback = function()
                    self:editFile(file_path, readonly)
                end,
            })
        else
            self:editFile(file_path, readonly)
        end
    else -- File does not exist
        -- Try to create it just to check if writting to it later is possible
        local file, err = io.open(file_path, "wb")
        if file then
            -- Clean it, we'll create it again on Save, and allow closing
            -- without saving in case the user has changed his mind.
            file:close()
            os.remove(file_path)
            self:editFile(file_path)
        else
            UIManager:show(InfoMessage:new{
                text = T(_("This file can not be created:\n\n%1\n\nReason: %2"), BD.filepath(file_path), err)
            })
            return
        end
    end
end

function TextEditor:readFileContent(file_path)
    local file = io.open(file_path, "rb")
    if not file then
        -- We checked file existence before, so assume it's
        -- because it's a new file
        return ""
    end
    local file_content = file:read("*all")
    file:close()
    return file_content
end

function TextEditor:saveFileContent(file_path, content)
    local file, err = io.open(file_path, "wb")
    if file then
        file:write(content)
        file:close()
        logger.info("TextEditor: saved file", file_path)
        return true
    end
    logger.info("TextEditor: failed saving file", file_path, ":", err)
    return false, err
end

function TextEditor:deleteFile(file_path)
    local ok, err = os.remove(file_path)
    if ok then
        logger.info("TextEditor: deleted file", file_path)
        return true
    end
    logger.info("TextEditor: failed deleting file", file_path, ":", err)
    return false, err
end

function TextEditor:editFile(file_path, readonly)
    self:addToHistory(file_path)
    local directory, filename = util.splitFilePathName(file_path) -- luacheck: no unused
    local filename_without_suffix, filetype = util.splitFileNameSuffix(filename) -- luacheck: no unused
    local is_lua = filetype:lower() == "lua"
    local input
    local para_direction_rtl = nil -- use UI language direction
    if self.force_ltr_para_direction then
        para_direction_rtl = false -- force LTR
    end
    local buttons_first_row = {}  -- First button on first row, that will be filled with Reset|Save|Close
    if is_lua then
        table.insert(buttons_first_row, {
            text = _("Lua check"),
            callback = function()
                local parse_error = util.checkLuaSyntax(input:getInputText())
                if parse_error then
                    UIManager:show(InfoMessage:new{
                        text = T(_("Lua syntax check failed:\n\n%1"), parse_error)
                    })
                else
                    UIManager:show(Notification:new{
                        text = T(_("Lua syntax OK")),
                    })
                end
            end,
        })
    end
    if self.qr_code_export then
        table.insert(buttons_first_row, {
            text = _("QR"),
            callback = function()
                UIManager:show(QRMessage:new{
                    text = input:getInputText(),
                    height = Screen:getHeight(),
                    width = Screen:getWidth()
                })
            end,
        })
    end
    input = InputDialog:new{
        title =  filename,
        input = self:readFileContent(file_path),
        input_face = Font:getFace(self.font_face, self.font_size),
        para_direction_rtl = para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        readonly = readonly,
        add_nav_bar = true,
        keyboard_hidden = not self.show_keyboard_on_start,
        scroll_by_pan = true,
        buttons = {buttons_first_row},
        -- Set/save view and cursor position callback
        view_pos_callback = function(top_line_num, charpos)
            -- This same callback is called with no argument to get initial position,
            -- and with arguments to give back final position when closed.
            if top_line_num and charpos then
                self.last_view_pos[file_path] = {top_line_num, charpos}
            else
                local prev_pos = self.last_view_pos[file_path]
                if type(prev_pos) == "table" and prev_pos[1] and prev_pos[2] then
                    return prev_pos[1], prev_pos[2]
                end
                return nil, nil -- no previous position known
            end
        end,
        -- File restoring callback
        reset_callback = function(content) -- Will add a Reset button
            return self:readFileContent(file_path), _("Text reset to last saved content")
        end,
        -- Close callback
        close_callback = function()
            self:execWhenDoneFunc()
        end,
        -- File saving callback
        save_callback = function(content, closing) -- Will add Save/Close buttons
            if self.readonly then
                -- We shouldn't be called if read-only, but just in case
                return false, _("File is read only")
            end
            if content and #content > 0 then
                if not is_lua then
                    local ok, err = self:saveFileContent(file_path, content)
                    if ok then
                        return true, _("File saved")
                    else
                        return false, T(_("Failed saving file: %1"), err)
                    end
                end
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local ok, err = self:saveFileContent(file_path, content)
                    if ok then
                        return true, _("Lua syntax OK, file saved")
                    else
                        return false, T(_("Failed saving file: %1"), err)
                    end
                end
                local save_anyway = Trapper:confirm(T(_([[
Lua syntax check failed:

%1

KOReader may crash if this is saved.
Do you really want to save to this file?

%2]]), parse_error, BD.filepath(file_path)),  _("Do not save"), _("Save anyway"))
                -- we'll get the safer "Do not save" on tap outside
                if save_anyway then
                    local ok, err = self:saveFileContent(file_path, content)
                    if ok then
                        return true, _("File saved")
                    else
                        return false, T(_("Failed saving file: %1"), err)
                    end
                else
                    return false, false -- no need for more InfoMessage
                end
            else -- If content is empty, propose to delete the file
                local delete_file = Trapper:confirm(T(_([[
Text content is empty.
Do you want to keep this file as empty, or do you prefer to delete it?

%1]]), BD.filepath(file_path)), _("Keep empty file"), _("Delete file"))
                -- we'll get the safer "Keep empty file" on tap outside
                if delete_file then
                    local ok, err = self:deleteFile(file_path)
                    if ok then
                        return true, _("File deleted")
                    else
                        return false, T(_("Failed deleting file: %1"), err)
                    end
                else
                    local ok, err = self:saveFileContent(file_path, content)
                    if ok then
                        return true, _("File saved")
                    else
                        return false, T(_("Failed saving file: %1"), err)
                    end
                end
            end
        end,

    }
    UIManager:show(input)
    input:onShowKeyboard()
    -- Note about self.readonly:
    -- We might have liked to still show keyboard even if readonly, just
    -- to use the arrow keys for line by line scrolling with cursor.
    -- But it's easier to just let InputDialog and InputText do their
    -- own readonly prevention (and on devices where we run as root, we
    -- will hardly ever be readonly).
end

-- reopen last edited file. Invokeable with gesture:
function TextEditor:onOpenLastEditedFile()
    self:loadSettings()
    if #self.history > 0 then
        local file_path = self.history[1]
        self:checkEditFile(file_path, true)
    else
        self:chooseFile()
    end
end

return TextEditor
