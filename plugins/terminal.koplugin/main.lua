--[[--
This plugin provides a terminal emulator (VT52 (+some ANSI and some VT100))

@module koplugin.terminal
]]

local Device = require("device")
local logger = require("logger")
local buffer = require("string.buffer")
local util = require("util")
local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")

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

local function check_prerequisites()
    -- We of course need to be able to manipulate pseudoterminals,
    -- but Kobo's init scripts fail to set this up...
    if Device:isKobo() then
        os.execute([[if [ ! -d "/dev/pts" ] ; then
            mkdir -p /dev/pts
            mount -t devpts devpts /dev/pts
            fi]])
    end

    local ptmx = C.open("/dev/ptmx", bit.bor(C.O_RDWR, C.O_NONBLOCK, C.O_CLOEXEC))
    if ptmx == -1 then
        logger.warn("Terminal: cannot open /dev/ptmx:", ffi.string(C.strerror(ffi.errno())))
        return false
    end

    if C.grantpt(ptmx) ~= 0 then
        logger.warn("Terminal: cannot use grantpt:", ffi.string(C.strerror(ffi.errno())))
        C.close(ptmx)
        return false
    end
    if C.unlockpt(ptmx) ~= 0 then
        logger.warn("Terminal: cannot use unlockpt:", ffi.string(C.strerror(ffi.errno())))
        C.close(ptmx)
        return false
    end
    C.close(ptmx)
    return true
end

-- grantpt and friends are necessary (introduced on Android in API 21).
-- So sorry for the Tolinos with (Android 4.4.x).
-- Maybe https://f-droid.org/de/packages/jackpal.androidterm/ could be an alternative then.
if (Device:isAndroid() and Device.firmware_rev < 21) or not check_prerequisites() then
    logger.warn("Terminal: Device doesn't meet some of the plugin's requirements")
    return { disabled = true, }
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
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

local CHUNK_SIZE = 80 * 40 -- max. nb of read bytes (reduce this, if taps are not detected)

local Terminal = WidgetContainer:extend{
    name = "terminal",
    history = "",
    is_shell_open = false,
    buffer_size = 1024 * G_reader_settings:readSetting("terminal_buffer_size", 16), -- size in kB
    refresh_time = 0.2,
    terminal_data = ".",
}

function Terminal:isExecutable(file)
    -- check if file is an executable or a command in PATH
    return ffiUtil.isExecutable(file) or util.which(file) ~= nil
end

-- Try SHELL environment variable and some standard shells
function Terminal:getDefaultShellExecutable()
    if self.default_shell_executable then return self.default_shell_executable end

    local shell = {
        "bash",
        "ash",
        "sh",
        "zsh",  -- RPROMPTs aren't really handled well, so we deprioritize it a bit
        "dash",
        "hush",
        "ksh",
        "mksh",
    }
    local env_shell = os.getenv("SHELL")
    if env_shell then
        table.insert(shell, 1, env_shell)
    end

    for dummy, file in ipairs(shell) do
        if self:isExecutable(file) then
            self.default_shell_executable = file
            break
        end
    end
    logger.dbg("Terminal: default shell is", self.default_shell_executable)

    return self.default_shell_executable
end

function Terminal:init()
    G_reader_settings:readSetting("terminal_shell", self:getDefaultShellExecutable())

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    self.chunk = buffer.new(CHUNK_SIZE)

    self.terminal_data = DataStorage:getDataDir()
    lfs.mkdir(self.terminal_data .. "/scripts")
    os.remove("terminal.pid") -- clean leftover from last run
end

function Terminal:spawnShell(cols, rows)
    if self.is_shell_open then
        self.input_widget:resize(rows, cols)
        self.input_widget:interpretAnsiSeq(self:receive())
        return true
    end

    local ptmx_name = "/dev/ptmx"
    self.ptmx = C.open(ptmx_name, bit.bor(C.O_RDWR, C.O_NONBLOCK, C.O_CLOEXEC))

    if self.ptmx == -1 then
        logger.err("Terminal: can not open", ptmx_name .. ":", ffi.string(C.strerror(ffi.errno())))
        return false
    end

    if C.grantpt(self.ptmx) ~= 0 then
        logger.err("Terminal: can not grantpt:", ffi.string(C.strerror(ffi.errno())))
        C.close(self.ptmx)
        return false
    end
    if C.unlockpt(self.ptmx) ~= 0 then
        logger.err("Terminal: can not unlockpt:", ffi.string(C.strerror(ffi.errno())))
        C.close(self.ptmx)
        return false
    end

    local ptsname = C.ptsname(self.ptmx)
    if ptsname then
        self.slave_pty = ffi.string(ptsname)
    else
        logger.err("Terminal: ptsname failed")
        C.close(self.ptmx)
        return false
    end

    logger.dbg("Terminal: slave_pty", self.slave_pty)

    -- Prepare shell call
    local function get_readline_wrapper()
        if self:isExecutable("rlfe") then
            return "rlfe"
        elseif self:isExecutable("rlwrap") then
            return "rlwrap"
        end
    end
    local profile_file = "./plugins/terminal.koplugin/profile"
    local rlw = get_readline_wrapper()
    local shell = G_reader_settings:readSetting("terminal_shell")
    local args = {}
    if shell:find("bash") then
        args = { "--rcfile", profile_file}
    end

    if not self:isExecutable(shell) then
        UIManager:show(InfoMessage:new{
            text = _("Shell is not executable"),
        })
        return false
    end

    logger.info("Terminal: spawning shell", shell)
    local pid = C.fork()
    if pid < 0 then
        logger.err("Terminal: fork failed:", ffi.string(C.strerror(ffi.errno())))
        return false
    elseif pid == 0 then
        C.close(self.ptmx)
        C.setsid()

        pid = C.getpid()
        local pid_file = io.open("terminal.pid", "w")
        if pid_file then
            pid_file:write(pid)
            pid_file:close()
        end

        local pts = C.open(self.slave_pty, C.O_RDWR)
        if pts == -1 then
            logger.err("Terminal: cannot open slave pty: ", pts)
            return false
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
        C.setenv("ENV", profile_file, 1) -- when bash is started as sh
        C.setenv("BASH_ENV", profile_file, 1) -- when bash is started non-interactive
        C.setenv("TERMINAL_DATA", self.terminal_data, 1)
        if Device:isAndroid() then
            C.setenv("ANDROID", "ANDROID", 1)
        end

        -- Here we attempt to use an existing readline wrapper
        if (rlw and C.execlp(rlw, rlw, shell, unpack(args)) ~= 0)
            or C.execlp(shell, shell, unpack(args)) ~= 0 then

            -- the following two prints are shown in the terminal emulator.
            print("Terminal: something has gone really wrong in spawning the shell\n\n:-(\n")
            print("Maybe an incorrect shell: '" .. shell .. "'\nor  an incorrect wrapper: " .. tostring(rlw) .. "'\n")
            os.exit()
        end
        os.exit()
        return
    end

    self.is_shell_open = true
    if Device:isAndroid() then
        -- feed the following commands to the running shell
        self:transmit("export TERM=vt52\n")
        self:transmit("stty cols " .. cols .. " rows " .. rows .."\n")
    end

    self.input_widget:resize(rows, cols)
    self.input_widget:interpretAnsiSeq(self:receive())

    logger.info("Terminal: spawn done")
    return true
end

function Terminal:receive()
    local ptr = self.chunk:reset():ref()
    local free = CHUNK_SIZE
    repeat
        C.tcdrain(self.ptmx)
        local count = tonumber(C.read(self.ptmx, ptr, free))
        if count <= 0 then
            break
        end
        ptr = ptr + count
        free = free - count
    until free == 0
    return self.chunk:commit(CHUNK_SIZE - free):get()
end

function Terminal:refresh()
    local next_text = self:receive()
    if next_text ~= "" then
        self.input_widget:interpretAnsiSeq(next_text)
        self.input_widget:trimBuffer(self.buffer_size)
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
    self.refresh_time = 1/32
    UIManager:unschedule(Terminal.refresh)
    UIManager:tickAfterNext(function()
        UIManager:scheduleIn(self.refresh_time, Terminal.refresh, self)
    end)
end

--- kills a running shell
-- @param ask if true ask if a shell is running, don't kill
-- @return pid if shell is running, -1 otherwise
function Terminal:killShell(ask)
    UIManager:unschedule(Terminal.refresh)
    local pid_file = io.open("terminal.pid", "r")
    if not pid_file then
        return -1
    end

    local pid = pid_file:read("*n")
    pid_file:close()

    if ask then
        return pid
    else
        local terminate = "\03\n\nexit\n"
        self:transmit(terminate)
        -- do other things before killing first
        self.is_shell_open = false
        self.history = ""
        os.remove("terminal.pid")
        C.close(self.ptmx)

        C.kill(pid, C.SIGTERM)

        local status = ffi.new('int[1]')
        -- status = tonumber(status[0])
        -- If still running: ret = 0 , status = 0
        -- If exited: ret = pid , status = 0 or 9 if killed
        -- If no more running: ret = -1 , status = 0
        C.waitpid(pid, status, 0) -- wait until shell is terminated

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
        title =  _("Terminal emulator"),
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
            text = "/",  -- slash
            callback = function()
                self:transmit("/")
            end,
            },
            {
                -- @translators This is the ESC-key on the keyboard.
                text = _("Esc"),
                callback = function()
                    self:transmit("\027")
                end,
            },
            {
                -- @translators This is the CTRL-key on the keyboard.
                text = _("Ctrl"),
                callback = function()
                    self.ctrl = true
                end,
            },
            {
                -- @translators This is the CTRL-C key combination.
                text = _("Ctrl-C"),
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
            text = "⇧",
            callback = function()
                self.input_widget:upLine()
            end,
            hold_callback = function()
                self.input_widget:scrollUp()
            end,
            },
            {
            text = "⇩",
            callback = function()
                self.input_widget:downLine()
            end,
            hold_callback = function()
                self.input_widget:scrollDown()
            end,
            },
            {
            text = "☰", -- settings menu
            callback = function ()
                UIManager:close(self.input_widget.keyboard)
                Aliases:show(self.terminal_data .. "/scripts/aliases",
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
                        -- trim trialing spaces and newlines
                        while self.history:sub(#self.history, #self.history) == "\n"
                            or self.history:sub(#self.history, #self.history) == " " do
                            self.history = self.history:sub(1, #self.history - 1)
                        end

                        UIManager:unschedule(Terminal.refresh)
                        UIManager:close(self.input_dialog)
                        if self.touchmenu_instance then
                            self.touchmenu_instance:updateItems()
                        end
                    end,
                    choice2_text = _("Quit"),
                    choice2_callback = function()
                        self.history = ""
                        self:killShell()
                        UIManager:unschedule(Terminal.refresh)
                        UIManager:close(self.input_dialog)
                        if self.touchmenu_instance then
                            self.touchmenu_instance:updateItems()
                        end
                    end,
                })
            end,
            },
        }},
        del_word_callback = function()
            self:transmit("\023") -- Ctrl+U
        end,
        enter_callback = function()
            self:transmit("\r")
        end,
        strike_callback = function(chars)
            if self.ctrl and #chars == 1 then
                local n = chars:upper():byte() - ("A"):byte()+1
                if n >= 0 then
                    chars = string.char(n)
                end
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

-- Kill the shell on plugin teardown
function Terminal:onCloseWidget()
    self:killShell()
end

function Terminal:onTerminalStart(touchmenu_instance)
    self.touchmenu_instance = touchmenu_instance

    self.input_face = Font:getFace("smallinfont",
        G_reader_settings:readSetting("terminal_font_size", 14))
    self.ctrl = false
    self.input_dialog = self:generateInputDialog()
    self.input_widget = self.input_dialog._input_widget

    local scroll_bar_width = ScrollTextWidget.scroll_bar_width
        + ScrollTextWidget.text_scroll_span
    self.maxc = math.floor((self.input_widget.width  - scroll_bar_width) / self:getCharSize())

    self.maxr = math.floor(self.input_widget.height
        / self.input_widget:getLineHeight())

    self.store_position = 1

    logger.dbg("Terminal: resolution= " .. self.maxc .. "x" .. self.maxr)

    if self:spawnShell(self.maxc, self.maxr) then
        UIManager:show(self.input_dialog)
        UIManager:scheduleIn(0.25, Terminal.refresh, self, true)
        self.input_dialog:onShowKeyboard(true)
    end
end

function Terminal:addToMainMenu(menu_items)
    menu_items.terminal = {
        text = _("Terminal emulator"),
--        sorting_hint = "more_tools",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = _("About terminal emulator"),
                callback = function()
                    local about_text = _([[Terminal emulator can start a shell (command prompt).

There are two environment variables TERMINAL_HOME and TERMINAL_DATA containing the path of the install and the data folders.

Commands to be executed on start can be placed in:
'$TERMINAL_DATA/scripts/profile.user'.

Aliases (shortcuts) to frequently used commands can be placed in:
'$TERMINAL_DATA/scripts/aliases'.]])
                    if not Device:isAndroid() then
                        about_text = about_text .. "\n\n" .. _("You can use 'shfm' as a file manager, '?' shows shfm’s help message.")
                    end

                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text_func = function()
                    local state = self.is_shell_open and _("running") or _("not running")
                    return T(_("Open terminal session (%1)"), state)
                end,
                callback = function(touchmenu_instance)
                    self:onTerminalStart(touchmenu_instance)
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
                        G_reader_settings:readSetting("terminal_font_size", 14))
                end,
                callback = function(touchmenu_instance)
                    local cur_size = G_reader_settings:readSetting("terminal_font_size")
                    local size_spin = SpinWidget:new{
                        value = cur_size,
                        value_min = 8,
                        value_max = 30,
                        value_hold_step = 2,
                        default_value = 14,
                        title_text = _("Terminal emulator font size"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("terminal_font_size", spin.value)
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
                        G_reader_settings:readSetting("terminal_buffer_size", 16))
                end,
                callback = function(touchmenu_instance)
                    local cur_buffer = G_reader_settings:readSetting("terminal_buffer_size")
                    local buffer_spin = SpinWidget:new{
                        value = cur_buffer,
                        value_min = 10,
                        value_max = 30,
                        value_hold_step = 2,
                        default_value = 16,
                        unit = C_("Data storage size", "kB"),
                        title_text = _("Terminal emulator buffer size (kB)"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("terminal_buffer_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(buffer_spin)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Shell executable: %1"), G_reader_settings:readSetting("terminal_shell"))
                end,
                callback = function(touchmenu_instance)
                    self.shell_dialog = InputDialog:new{
                        title = _("Shell to use"),
                        description = T(_("Here you can select the startup shell.\nDefault: %1"),
                                      self:getDefaultShellExecutable()),
                        input = G_reader_settings:readSetting("terminal_shell"),
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
                                    G_reader_settings:saveSetting("terminal_shell", self:getDefaultShellExecutable())
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
                                    if self:isExecutable(new_shell) then
                                        G_reader_settings:saveSetting("terminal_shell", new_shell)
                                        UIManager:close(self.shell_dialog)
                                        if touchmenu_instance then
                                            touchmenu_instance:updateItems()
                                        end
                                    else
                                        UIManager:show(InfoMessage:new{
                                            text = _("Shell is not executable"),
                                        })
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
    Dispatcher:registerAction("terminal",
        {category = "none", event = "TerminalStart", title = _("Terminal emulator"), device = true})
end

return Terminal
