--[[
This plugin provides a terminal emulator (VT52 (+some ANSI))
]]

local Device = require("device")

-- grantpt and friends are necessary (introduced on Android in API 21).
-- So sorry for the Tolinos with (Android 4.4.x)
if Device:isAndroid() then
    local A, android = pcall(require, "android")  -- luacheck: ignore
    local api = android.app.activity.sdkVersion
    if api < 21 then
        return { disabled = true }
    end
end

local Aliases = require("aliases")
local Dispatcher = require("dispatcher")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TermInputText = require("terminputtext")
local TextWidget = require("ui/widget/textwidget")
local bit = require("bit")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ffi = require("ffi")
local C = ffi.C

-- for terminal emulator
ffi.cdef[[
static const int SIGTERM = 15;

int grantpt(int fd) __attribute__((nothrow, leaf));
int unlockpt(int fd) __attribute__((nothrow, leaf));
char *ptsname(int fd) __attribute__((nothrow, leaf));
pid_t setsid(void) __attribute__((nothrow, leaf));

static const int TCIFLUSH = 0;
int tcdrain(int fd) __attribute__((nothrow, leaf));
int tcflush(int fd, int queue_selector) __attribute__((nothrow, leaf));
]]

--[[
local ctrl_c = "\003"
local ctrl_f = "\006" -- right
local ctrl_b = "\002" -- left
local ctrl_n = "\014" -- down
local ctrl_p = "\016" -- up
local ctrl_x = "\024"
local ctrl_z = "\026"
]]

local esc = "\027"

local CHUNK_SIZE = 80 * 40 -- max. nb of read bytes (reduce this, if taps are not detected)

local Terminal = WidgetContainer:new{
    name = "KOTerm",
    history = "",
    is_shell_open = false,
    font_size = G_reader_settings:readSetting("KOTerm_font_size", 14),
    buffer_size = 1024 * G_reader_settings:readSetting("KOTerm_buffer_size", 16), -- size in kB
    buffer_used_approx = 0,
    refresh_time = 0.2,
    sequence_state = "",
    koterm_home = ".",
}

function Terminal:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    self.terminal_font_size = G_reader_settings:readSetting("terminal_font_size", 14)

    self.chunk_size = CHUNK_SIZE
    self.chunk = ffi.new('uint8_t[?]', self.chunk_size)

    self.koterm_home = DataStorage:getDataDir() .. "/scripts"
    lfs.mkdir(self.koterm_home)
    os.remove("koterm.pid") -- clean leftover from last run
end

function Terminal:spawnShell(cols, rows)
    if self.is_shell_open then return end

    local shell = G_reader_settings:readSetting("KOTerm_shell", "sh")

    local ptmx_name = "/dev/ptmx"
    self.ptmx = C.open(ptmx_name, bit.bor(C.O_RDWR, C.O_NONBLOCK, C.O_CLOEXEC))

    if C.grantpt(self.ptmx) ~= 0 then
        logger.err("KOTerm: can not grantpt")
    end
    if C.unlockpt(self.ptmx) ~= 0 then
        logger.err("KOTerm: can not unockpt")
    end

    self.slave_pty = ffi.string(C.ptsname(self.ptmx))

    logger.info("KOTerm: slave_pty", self.slave_pty)

    local pid = C.fork()
    if pid < 0 then
        logger.err("KOTerm: fork failed")
        return
    elseif pid == 0 then
        C.close(self.ptmx)
        C.setsid()

        pid = C.getpid()
        local pid_file = io.open("koterm.pid", "w")
        if pid_file then
            pid_file:write(pid)
            pid_file:close()
        end

        local pts = C.open(self.slave_pty, C.O_RDWR)
        if pts == -1 then
            logger.err("KOTerm: cannot open slave pty: ", pts)
            return
        end

        C.dup2(pts, 0);
        C.dup2(pts, 1);
        C.dup2(pts, 2);
        C.close(pts);

        if cols and rows then
            if not Device:isAndroid() then
                os.execute("stty cols " .. cols .. " rows " .. rows)
            end
        end

        C.setenv("TERM", "vt52", 1)
        C.setenv("ENV", "./plugins/koterm.koplugin/profile", 1)
        C.setenv("BASH_ENV", "./plugins/koterm.koplugin/profile", 1)
        C.setenv("KOTERM_HOME", self.koterm_home, 1)
        if C.execlp(shell, shell) ~= 0 then
            -- the following two prints are shown in the KOTerm emulator.
            print("KOTerm: something has gone really wrong in spawning the shell\n\n:-(\n")
            print("Maybe an incorrect shell: '" .. shell .. "'\n")
            os.exit()
        end
        os.exit()
        return
    end

    self.is_shell_open = true
    if Device:isAndroid() then
        -- feed the following commands to the running shell
        self:transmit(" export TERM=vt52\n")
        self:transmit(" stty cols " .. cols .. " rows " .. rows .."\n")
    end

--    self:transmit("source ./plugins/koterm.koplugin/profile\n")
    self:interpretAnsiSeq(self:receive())

    logger.info("KOTerm: spawn done")
end

function Terminal:receive()
    local last_result = ""
    repeat
        C.tcdrain(self.ptmx)
        local count = tonumber(C.read(self.ptmx, self.chunk, self.chunk_size))
        if count > 0 then
            last_result = last_result .. string.sub(ffi.string(self.chunk), 1, count)
        end
    until count <= 0 or #last_result >= self.chunk_size - 1
    return last_result
end

function Terminal:refresh(reset)
    if reset then
        self.refresh_time = 1/32
        UIManager:unschedule(Terminal.refresh)
    end

    local next_text = self:receive()
    if next_text ~= "" then
        self:interpretAnsiSeq(next_text)
        if self.is_shell_open then
            UIManager:tickAfterNext(function()
                UIManager:scheduleIn(self.refresh_time, Terminal.refresh, self)
            end)
        end
    else
        if self.is_shell_open then
            if self.refresh_time > 5 then
                self.refresh_time = self.refresh_time
            elseif self.refresh_time > 1 then
                self.refresh_time = self.refresh_time * 1.1
            else
                self.refresh_time = self.refresh_time * 2
            end
            UIManager:scheduleIn(self.refresh_time, Terminal.refresh, self)
        end
    end
end

function Terminal:transmit(chars)
    C.write(self.ptmx, chars, #chars)
    self:refresh(true)
end

function Terminal:_helperVT52VT100(cmd, param1, param2)
    if cmd == "A" then -- cursor up
        self.input_widget:moveCursorUp(true)
        return true
    elseif cmd == "B" then -- cursor down
        self.input_widget:moveCursorDown(true)
        return true
    elseif cmd == "C" then -- cursor right
        self.input_widget:rightChar(true)
        return true
    elseif cmd == "D" then -- cursor left
        self.input_widget:leftChar(true)
        return true
    elseif cmd == "H" then -- cursor home
        param1 = param1 == 0 and 1 or param1
        param2 = param2 == 0 and 1 or param2
        self.input_widget:moveCursorToRowCol(param1, param2, self.maxr, self.maxc)
        return true
    elseif cmd == "J" then -- clear to end of screen
        self.input_widget:clearToEndOfScreen()
        return true
    elseif cmd == "K" then -- clear to end of line
        self.input_widget:delToEndOfLine(true)
        return true
    end
    return false
end

local function isNum(char)
    if #char ~= 1 then return end
    if char:byte() >= ("0"):byte() and char:byte() <= ("9"):byte() then
        return true
    end
end

function Terminal:interpretAnsiSeq(text)
    local pos = 1
    local param1, param2 = 0, 0

    while pos <= #text do
        local next_byte = text:sub(pos, pos)
        if self.sequence_state == "" then
            local function isPrintable(ch)
                return ch:byte() >= 32 or ch == "\010" or ch == "\013" or ch == "\008"
            end
            if next_byte == esc then
                self.sequence_state = "esc"
            elseif isPrintable(next_byte) then
                local part = next_byte
                -- all bytes up to the next control sequence
                while pos < #text and isPrintable(next_byte) do
                    next_byte = text:sub(pos+1, pos+1)
                    if next_byte ~= "" and pos < #text and isPrintable(next_byte) then
                        part = part .. next_byte
                        pos = pos + 1
                    end
                end
                self.input_widget:addChars(part, true)
            end
        elseif self.sequence_state == "esc" then
            self.sequence_state = ""
            if next_byte == "A" then -- cursor up
                self.input_widget:moveCursorUp(true)
            elseif next_byte == "B" then -- cursor down
                self.input_widget:moveCursorDown(true)
            elseif next_byte == "C" then -- cursor right
                self.input_widget:rightChar(true)
            elseif next_byte == "D" then -- cursor left
                self.input_widget:leftChar(true)
            elseif next_byte == "F" then -- enter graphics mode
                logger.dbg("KOTerm: enter graphics mode not supported")
            elseif next_byte == "G" then -- exit graphics mod
                logger.dbg("KOTerm: leave graphics mode not supported")
            elseif next_byte == "H" then -- cursor home
                self.input_widget:moveCursorToRowCol(1, 1, self.maxr, self.maxc)
            elseif next_byte == "I" then -- reverse line feed (cursor up and insert line)
                self.input_widget:reverseLineFeed(true)
            elseif next_byte == "J" then -- clear to end of screen
                self.input_widget:clearToEndOfScreen()
            elseif next_byte == "K" then -- clear to end of line
                self.input_widget:delToEndOfLine(true)
            elseif next_byte == "L" then -- insert line
                logger.dbg("KOTerm: insert not supported")
            elseif next_byte == "M" then -- remove line
                logger.dbg("KOTerm: remove line not supported")
            elseif next_byte == "Y" then -- set cursor pos (row, col)
                self.sequence_state = "escY"
            elseif next_byte == "Z" then -- ident(ify)
                self:transmit("\027/K") -- identify as VT52 without printer
            elseif next_byte == "=" then -- alternate keypad
                self.input_widget:enterAlternateKeypad(self.maxr, self.maxc)
            elseif next_byte == ">" then -- exit alternate keypad
                self.input_widget:exitAlternateKeypad()
            elseif next_byte == "[" then
                self.sequence_state = "CSI1"
            end
        elseif self.sequence_state == "escY" then
            param1 = next_byte
            self.sequence_state = "escYrow"
        elseif self.sequence_state == "escYrow" then
            param2 = next_byte
            -- row and column are offsetted with 32 (' ')
            if param1 ~= 0 and param2 ~= 0 then
                local row = param1 and (param1:byte() - (" "):byte() + 1) or 1
                local col = param2 and (param2:byte() - (" "):byte() + 1) or 1
                self.input_widget:moveCursorToRowCol(row, col, self.maxr, self.maxc)
                param1, param2 = 0, 0
            end
            self.sequence_state = ""
        elseif self.sequence_state == "CSI1" then
            if next_byte == "s" then -- save cursor pos
                logger.dbg("KOTerm: save cursor pos not implemented")
                --- @todo
            elseif next_byte == "u" then -- restore cursor pos
                logger.dbg("KOTerm: restore cursor pos not implemented")
                --- @todo
            elseif next_byte == "?" then
                self.sequence_state = "escParam2"
            elseif isNum(next_byte) then
                param1 = param1 * 10 + next_byte:byte() - ("0"):byte()
            else
                if next_byte == ";" then
                    self.sequence_state = "escParam2"
                else
                    pos = pos - 1
                    self.sequence_state = "escOtherCmd"
                end
            end
        elseif self.sequence_state == "escParam2" then
            if isNum(next_byte) then
                param2 = param2 * 10 + next_byte:byte() - ("0"):byte()
            else
                pos = pos - 1
                self.sequence_state = "escOtherCmd"
            end
        elseif self.sequence_state == "escOtherCmd" then
            if not self:_helperVT52VT100(next_byte, param1, param2) then
                -- drop other VT100 sequences
                logger.info("xxxxxxxxx ANSI-final: not supported", next_byte,
                    next_byte:byte(), next_byte)
            end
            param1, param2 = 0, 0
            self.sequence_state = ""
        else
            logger.dbg("KOTerm: detected error in esc sequence, not my fault.")
            self.sequence_state = ""
        end -- self.sequence_state

        pos = pos + 1
        if #self.input_dialog:getInputText() > self.buffer_size then
            local input = self.input_dialog:getInputText()
            input = input:sub(#input - self.buffer_size)
            self.input_dialog:setInputText(input)
        end
    end

end

--- kills a running shell
-- @param ask if true ask if a shell is running, don't kill
-- @return pid if shell is running, -1 otherwise
function Terminal:killShell(ask)
    UIManager:unschedule(Terminal.refresh)
    local pid_file = io.open("koterm.pid", "r")
    if not pid_file then
        return -1
    end

    local pid = tonumber(pid_file:read("*a"))
    pid_file:close()

    if ask then
        return pid
    else
        local terminate = "\03\n\nexit\n"
        self:transmit(terminate)
        -- do other things before killing first
        self.is_shell_open = false
        self.history = ""
        os.remove("koterm.pid")  -- check this todo
        C.close(self.ptmx)

        C.kill(pid, C.SIGTERM)
        return -1
    end
end

function Terminal:getCharSize()
    local tmp = TextWidget:new{
        text = " ",
        face = self.input_face,
    }
    return tmp:getSize().w
end
function Terminal:generateInputDialog()
    return InputDialog:new{
        title =  _("KOTerm: Terminal Emulator"),
        input = self.history,
        input_face = self.input_face,
        para_direction_rtl = false,
        input_type = "string",
        allow_newline = false,
        cursor_at_end = true,
        fullscreen = true,
        inputtext_class = TermInputText,
        buttons = {{
            {
            text = "↹",  -- tabulator "⇤" and "⇥"
            callback = function()
                self:transmit("\009")
            end,
            },
            {
            text = "Esc",
            callback = function()
                self:transmit(esc)
            end,
            },
            {
            text = "Ctrl",
            callback = function()
                self.ctrl = true
            end,
            },
            {
            text = "Ctrl-C",
            callback = function()
                self:transmit("\003")
                -- consume and drop everything
                C.tcflush(self.ptmx, C.TCIFLUSH)
                while self:receive() ~= "" do
                    C.tcflush(self.ptmx, C.TCIFLUSH)
                end
                self.input_widget:addChars("\003", true) -- as we flush the queue
            end,
            },
            {
            text = "⎚", --clear
            callback = function()
                self.history = ""
                self.input = {}
                self.input_dialog:setInputText("")
            end,
            },
            {
            text = "⇧",
            callback = function()
                self.input_widget:upLine()
            end,
            hold_callback = function()
                self.input_widget:upPage()
            end,
            },
            {
            text = "⇩",
            callback = function()
                self.input_widget:downLine()
            end,
            hold_callback = function()
                self.input_widget:downPage()
            end,
            },
            {
            text = "☰", -- settings menu
            callback = function ()
                UIManager:close(self.input_widget.keyboard)
                Aliases:show(self.koterm_home .. "/aliases",
                    function()
                        UIManager:show(self.input_widget.keyboard)
                        UIManager:setDirty(self.input_dialog, "fast") -- is there a better solution
                    end,
                    self)
            end,
            },
            {
            text = "✕", --cancel
            callback = function()
                UIManager:show(MultiConfirmBox:new{
                    text = _("You can close the terminal, but leave the shell open for further commands or quit it now."),
                    choice1_text = _("Close"),
                    choice1_callback = function()
                        self.history = self.input_dialog:getInputText()
                        UIManager:close(self.input_dialog)
                        if self.touchmenu_instance then
                            self.touchmenu_instance:updateItems()
                        end
                    end,
                    choice2_text = _("Quit"),
                    choice2_callback = function()
                        self.history = ""
                        self:killShell()
                        UIManager:close(self.input_dialog)
                        if self.touchmenu_instance then
                            self.touchmenu_instance:updateItems()
                        end
                    end,
                })
            end,
            },
        }},
        enter_callback = function()
            self:transmit("\r")
        end,
        strike_callback = function(chars)
            if self.ctrl and #chars == 1 then
                chars = string.char(chars:upper():byte() - ("A"):byte()+1)
                self.ctrl = false
            end
            if chars == "\n" then
                chars = "\r\n"
            end
            self:transmit(chars)
        end,
    }
end

function Terminal:onClose()
    self:killShell()
end

function Terminal:onKOTermStart(touchmenu_instance)
    self.touchmenu_instance = touchmenu_instance

    self.input_face = Font:getFace("smallinfont",
        G_reader_settings:readSetting("KOTerm_font_size",14))
    self.ctrl = false
    self.input_dialog = self:generateInputDialog()
    self.input_widget = self.input_dialog._input_widget

    local scroll_bar_width = ScrollTextWidget.scroll_bar_width
        + ScrollTextWidget.text_scroll_span
    self.maxc = math.floor((self.input_widget.width  - scroll_bar_width) / self:getCharSize())

    self.maxr = math.floor(self.input_widget.height
        / self.input_widget:getLineHeight())

    self.store_position = 1

    logger.dbg("KOTerm: resolution= " .. self.maxc .. "x" .. self.maxr)

    self:spawnShell(self.maxc, self.maxr)
    UIManager:show(self.input_dialog)
    UIManager:scheduleIn(0.25, Terminal.refresh, self, true)
    self.input_dialog:onShowKeyboard(true)
end

function Terminal:addToMainMenu(menu_items)
    menu_items.Terminal = {
        text = "KOTerm",
        sorting_hint = "more_tools",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = _("About KOTerm"),
                callback = function()
                    local about_text = T(_([[
KOTerm is a terminal emulator, which starts a shell (command prompt).

Commands to be executed on start can be placed in:
'%1/profile.user'.

Aliases (shortcuts) to frequently used commands can be placed in:
'%1/aliases'.]]),
self.koterm_home)

                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text_func = function()
                    local state = self.is_shell_open and "running" or "not running"
                    return T(_("Open terminal session (%1)"), state)
                end,
                callback = function(touchmenu_instance)
                    self:onKOTermStart(touchmenu_instance)
                end,
                keep_menu_open = true,
            },
            {
                text = _("End terminal session"),
                enabled_func = function()
                    return self:killShell(true) >= 0
                end,
                callback = function(touchmenu_instance)
                    self:killShell()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Font size: %1"),
                        G_reader_settings:readSetting("KOTerm_font_size", 14))
                end,
                callback = function(touchmenu_instance)
                    local cur_size = G_reader_settings:readSetting("KOTerm_font_size")
                    local size_spin = SpinWidget:new{
                        value = cur_size,
                        value_min = 10,
                        value_max = 30,
                        value_hold_step = 2,
                        default_value = 14,
                        title_text = _("KOTerm font size "),
                        callback = function(spin)
                            G_reader_settings:saveSetting("KOTerm_font_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(size_spin)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Buffer size: %1 kB"),
                        G_reader_settings:readSetting("KOTerm_buffer_size", 16))
                end,
                callback = function(touchmenu_instance)
                    local cur_buffer = G_reader_settings:readSetting("KOTerm_buffer_size")
                    local buffer_spin = SpinWidget:new{
                        value = cur_buffer,
                        value_min = 10,
                        value_max = 30,
                        value_hold_step = 2,
                        default_value = 16,
                        title_text = _("KOTerm font size"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("KOTerm_buffer_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(buffer_spin)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Shell executable: %1"),
                        G_reader_settings:readSetting("KOTerm_shell", "sh"))
                end,
                callback = function(touchmenu_instance)
                    self.shell_dialog = InputDialog:new{
                        title = _("Shell to use"),
                        description = _("Here you can select the startup shell.\nDefault: sh"),
                        input = G_reader_settings:readSetting("KOTerm_shell", "sh"),
                        buttons = {{
                            {
                                text = _("Cancel"),
                                callback = function()
                                    UIManager:close(self.shell_dialog)
                                end,
                            },
                            {
                                text = _("Default"),
                                callback = function()
                                    G_reader_settings:saveSetting("KOTerm_shell", "sh")
                                    UIManager:close(self.shell_dialog)
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local new_shell = self.shell_dialog:getInputText()
                                    if new_shell == "" then
                                        new_shell = "sh"
                                    end
                                    G_reader_settings:saveSetting("KOTerm_shell", new_shell)
                                    UIManager:close(self.shell_dialog)
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end
                            },
                        }}}
                    UIManager:show(self.shell_dialog)
                    self.shell_dialog:onShowKeyboard()
                end,
                keep_menu_open = true,
            },
        }
    }
end

function Terminal:onDispatcherRegisterActions()
    Dispatcher:registerAction("KOTerm",
        {category = "none", event = "KOTermStart", title = "KOTerm", device = true})
end

return Terminal
