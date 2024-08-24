--[[--
module used for terminal emulator to override InputText

@module koplugin.terminal
]]

local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local logger = require("logger")
local util = require("util")

local esc = "\027"
local backspace = "\008"

local esc_seq = {
    cursor_left =  "\027[D",
    cursor_right = "\027[C",
    cursor_up =    "\027[A",
    cursor_down =  "\027[B",
    cursor_pos1 =  "\027[7~",
    cursor_end =   "\027[8~",
    page_up =      "\027[5~",
    page_down =    "\027[6~",
}

local function isNum(char)
    if #char ~= 1 then return end
    if char:byte() >= ("0"):byte() and char:byte() <= ("9"):byte() then
        return true
    end
end

local function isPrintable(ch)
    return ch:byte() >= 32 or ch == "\010" or ch == "\013"
end

local TermInputText = InputText:extend{
    maxr = 40,
    maxc = 80,
    min_buffer_size = 2 * 40 * 80, -- minimal size of scrollback buffer
    strike_callback = nil,
    sequence_state = "",

    store_pos_dec = nil,
    store_pos_sco = nil,
    store_position = nil, -- when entered alternate keypad

    scroll_region_bottom = nil,
    scroll_region_top = nil,
    scroll_region_line = nil,

    wrap = true,

    alternate_buffer = nil, -- table
    save_buffer = nil, -- table
}

function TermInputText:init()
    self.alternate_buffer = {}
    self.save_buffer = {}
    InputText.init(self)
end

-- disable positioning cursor by tap in emulator mode
function TermInputText:onTapTextBox(arg, ges)
    return true
end

function TermInputText:resize(maxr, maxc)
    self.maxr = maxr
    self.maxc = maxc
    self.min_buffer_size = 2 * self.maxr * self.maxc
end

-- reduce the size of the buffer,
function TermInputText:trimBuffer(new_size)
    if not new_size or new_size < self.min_buffer_size then
        new_size = self.min_buffer_size
    end
    if #self.charlist > new_size then
        -- delete whole lines from beginning
        local n = #self.charlist - new_size
        while self.charlist[n+1] and self.charlist[n+1] ~= "\n" do
            n = n + 1
        end
        if self.charlist[n+1] == "\n" then
            n = n + 1
        end
        -- remove first n chars
        table.move(self.charlist, n+1, #self.charlist, 1)
        for dummy = 1, n do
            self.charlist[#self.charlist] = nil
        end

        self.charpos = math.max(1, self.charpos - n)

        -- update stored positions
        if self.store_position then
            self.store_position = math.max(1, self.store_position - n)
        end
        if self.store_pos_dec then
            self.store_pos_dec = math.max(1, self.store_pos_dec - n)
        end
        if self.store_pos_sco then
            self.store_pos_sco = math.max(1, self.store_pos_sco - n)
        end

        self:initTextBox(table.concat(self.charlist), true)
    end
end

function TermInputText:saveBuffer(buffer)
    table.insert(self[buffer],
        {
            self.charlist,
            self.charpos,
            self.store_pos_dec,
            self.store_pos_sco,
            self.store_position,
            self.scroll_region_bottom,
            self.scroll_region_top,
            self.scroll_region_line,
            self.wrap,
        })
    self.charlist = {}
    self.charpos = 1
    self.store_pos_dec = nil
    self.store_pos_sco = nil
    self.store_position = nil
    self.scroll_region_bottom = nil
    self.scroll_region_top = nil
    self.scroll_region_line = nil
    self.wrap = true
end

function TermInputText:restoreBuffer(buffer)
    local former_buffer = table.remove(self[buffer])
    if former_buffer and type(former_buffer[1]) == "table" then
        self.charlist,
        self.charpos,
        self.store_pos_dec,
        self.store_pos_sco,
        self.store_position,
        self.scroll_region_bottom,
        self.scroll_region_top,
        self.scroll_region_line,
        self.wrap = unpack(former_buffer)
    end
end

function TermInputText:_helperVT52VT100(cmd, mode, param1, param2, param3)
    if cmd == "A" then -- cursor up
        param1 = param1 == 0 and 1 or param1
        for i = 1, param1 do
            if self.scroll_region_line then
                self:scrollRegionDown()
            end
            self:moveCursorUp(true)
        end
        return true
    elseif cmd == "B" then -- cursor down
        param1 = param1 == 0 and 1 or param1
        for i = 1, param1 do
            self:moveCursorDown(true)
        end
        return true
    elseif cmd == "C" then -- cursor right
        param1 = param1 == 0 and 1 or param1
        for i = 1, param1 do
            self:rightChar(true)
        end
        return true
    elseif cmd == "D" then -- cursor left
        param1 = param1 == 0 and 1 or param1
        for i = 1, param1 do
            self:leftChar(true)
        end
        return true
    elseif cmd == "H" then -- cursor home
        param1 = param1 == 0 and 1 or param1
        param2 = param2 == 0 and 1 or param2
        self:moveCursorToRowCol(param1, param2)
        if self.scroll_region_line and param1 <= self.scroll_region_bottom
            and param1 >= self.scroll_region_top then
                self.scroll_region_line = param1
        end
        return true
    elseif cmd == "J" then -- clear to end of screen
        if param1 == 0 then
            self:clearToEndOfScreen()
        elseif param1 == 1 then
            return false --- @todo not implemented
        elseif param1 == 2 then
            local saved_pos = self.charpos
            self:moveCursorToRowCol(1, 1)
            self:clearToEndOfScreen()
            self.charpos = saved_pos
        end
        return true
    elseif cmd == "K" then -- clear to end of line
        self:delToEndOfLine()
        return true
    elseif cmd == "L" then
        if self.scroll_region_line then
            self:scrollRegionDown()
        end
        return true
    elseif cmd == "h" and mode == "?" then --
        --- if param2 == 25 then set cursor visible
        if param2 == 7 then -- enable wrap around
            self.wrap = true
        elseif param2 == 47 then -- save screen
            self:saveBuffer("save_buffer")
            print("xxxxxxxxxxxx save screen")
        elseif param2 == 1049 then -- enable alternate buffer
            self:saveBuffer("alternate_buffer")
            print("xxxxxxxxxxxx enable alternate buffer")
        end
        return true
    elseif cmd == "l" and mode == "?" then --
        --- if param2 == 25 then set cursor invisible
        if param2 == 7 then -- enable wrap around
            self.wrap = false
        elseif param2 == 47 then -- restore screen
            self:restoreBuffer("save_buffer")
            print("xxxxxxxxxxxx restore screen")
        elseif param2 == 1049 then -- disable alternate buffer
            self:restoreBuffer("alternate_buffer")
            print("xxxxxxxxxxxx disable alternate buffer")
        end
        return true
    elseif cmd == "m" then
        -- graphics mode not supported yet(?)
        return true
    elseif cmd == "n" then
        --- @todo
        return true
    elseif cmd == "r" then
        if param2 > 0 and param2 < self.maxr then
            self.scroll_region_bottom = param2
        else
            self.scroll_region_bottom = nil
        end

        if self.scroll_region_bottom and param1 < self.maxr and param1 <= param2 and param1 > 0 then
            self.scroll_region_top = param1
            self.scroll_region_line = 1
        else
            self.scroll_region_bottom = nil
            self.scroll_region_top = nil
            self.scroll_region_line = nil
        end
        logger.dbg("Terminal: set scroll region", param1, param2, self.scroll_region_top, self.scroll_region_bottom, self.scroll_region_line)
        return true
    end
    return false
end

function TermInputText:interpretAnsiSeq(text)
    local pos = 1
    local param1, param2, param3 = 0, 0, 0

    while pos <= #text do
        local next_byte = text:sub(pos, pos)
        if self.sequence_state == "" then
            if next_byte == esc then
                self.sequence_state = "esc"
            elseif isPrintable(next_byte) then
                local printable_ends = pos
                while printable_ends < #text and isPrintable(text:sub(printable_ends+1,printable_ends+1)) do
                    printable_ends = printable_ends + 1
                end
                self:addChars(text:sub(pos, printable_ends), true, true)
                pos = printable_ends
            elseif next_byte == backspace then
                self:leftChar(true)
            end
        elseif self.sequence_state == "esc" then
            self.sequence_state = ""
            if next_byte == "A" then -- cursor up
                self:moveCursorUp(true)
            elseif next_byte == "B" then -- cursor down
                self:moveCursorDown(true)
            elseif next_byte == "C" then -- cursor right
                self:rightChar(true)
            elseif next_byte == "D" then -- cursor left
                self:leftChar(true)
            elseif next_byte == "F" then -- enter graphics mode
                logger.dbg("Terminal: enter graphics mode not supported")
            elseif next_byte == "G" then -- exit graphics mod
                logger.dbg("Terminal: leave graphics mode not supported")
            elseif next_byte == "H" then -- cursor home
                self:moveCursorToRowCol(1, 1)
            elseif next_byte == "I" then -- reverse line feed (cursor up and insert line)
                self:reverseLineFeed(true)
            elseif next_byte == "J" then -- clear to end of screen
                self:clearToEndOfScreen()
            elseif next_byte == "K" then -- clear to end of line
                self:delToEndOfLine()
            elseif next_byte == "L" then -- insert line
                logger.dbg("Terminal: insert not supported")
            elseif next_byte == "M" then -- remove line
                logger.dbg("Terminal: remove line not supported")
            elseif next_byte == "Y" then -- set cursor pos (row, col)
                self.sequence_state = "escY"
            elseif next_byte == "Z" then -- ident(ify)
                self.strike_callback("\027/K") -- identify as VT52 without printer
            elseif next_byte == "=" then -- alternate keypad
                self:enterAlternateKeypad()
            elseif next_byte == ">" then -- exit alternate keypad
                self:exitAlternateKeypad()
            elseif next_byte == "[" then
                self.sequence_state = "CSI1"
            elseif next_byte == "7" then
                self.store_pos_dec = self.charpos
            elseif next_byte == "8" then
                self.charpos = self.store_pos_dec
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
                self:moveCursorToRowCol(row, col)
                param1, param2, param3 = 0, 0, 0
            end
            self.sequence_state = ""
        elseif self.sequence_state == "CSI1" then
            if next_byte == "s" then -- save cursor pos
                self.store_pos_sco = self.charpos
            elseif next_byte == "u" then -- restore cursor pos
                self.charpos = self.store_pos_sco
            elseif next_byte == "?" then
                self.sequence_mode = "?"
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
                if next_byte == ";" then
                    self.sequence_state = "escParam3"
                else
                    pos = pos - 1
                    self.sequence_state = "escOtherCmd"
                end
            end
        elseif self.sequence_state == "escParam3" then
            if isNum(next_byte) then
                param3 = param3 * 10 + next_byte:byte() - ("0"):byte()
            else
                pos = pos - 1
                self.sequence_state = "escOtherCmd"
            end
        elseif self.sequence_state == "escOtherCmd" then
            if not self:_helperVT52VT100(next_byte, self.sequence_mode, param1, param2, param3) then
                -- drop other VT100 sequences
                logger.info("Terminal: ANSI-final: not supported", next_byte,
                    next_byte:byte(), next_byte, param1, param2, param3)
            end
            param1, param2, param3 = 0, 0, 0
            self.sequence_state = ""
            self.sequence_mode = ""
        else
            logger.dbg("Terminal: detected error in esc sequence, not my fault.")
            self.sequence_state = ""
        end -- self.sequence_state

        pos = pos + 1
    end

    self:initTextBox(table.concat(self.charlist), true)
end

function TermInputText:scrollRegionDown(column)
    column = column or 1
    if self.scroll_region_line > self.scroll_region_top then
        self.scroll_region_line = self.scroll_region_line - 1
    else -- scroll down
        local pos = self.charpos
        for i = self.scroll_region_line, self.scroll_region_bottom  do
            while pos > 1 and self.charlist[pos] ~= "\n" do
                pos = pos + 1
            end
            if pos < #self.charlist then
                pos = pos + 1
            end
        end
        pos = pos - 1

        table.remove(self.charlist, pos)
        while self.charlist[pos] ~= "\n" do
            table.remove(self.charlist, pos)
        end

        pos = self.charpos
        for i = column, self.maxc - column + 1 do
            table.insert(self.charlist, pos, ".")
            pos = pos + 1
        end
        table.insert(self.charlist, pos, "\n")
    end
end

function TermInputText:scrollRegionUp(column)
    column = column or 1
    if self.scroll_region_line < self.scroll_region_bottom then
        self.scroll_region_line = self.scroll_region_line + 1
    else -- scroll up
        local pos = self.charpos
        for i = self.scroll_region_line, self.scroll_region_top + 1, -1 do
            while pos > 1 and self.charlist[pos] ~= "\n" do
                pos = pos - 1
            end
            if pos > 1 then
                pos = pos - 1
            end
        end
        pos = pos + 1

        table.remove(self.charlist, pos)
        self.charpos = self.charpos - 1
        pos = pos - 1
        while pos > 0 and self.charlist[pos] ~= "\n" do
            table.remove(self.charlist, pos)
            pos = pos - 1
        end

        pos = self.charpos + 1
        for i = column, self.maxc - column do
            table.insert(self.charlist, pos, " ")
            pos = pos + 1
        end
        table.insert(self.charlist, pos, "\n")
        for i = 1, column - 1 do
           table.insert(self.charlist, pos, " ")
           pos = pos + 1
        end
    end
end

-- @fixme: This interacts badly with the wrapping of addChars in e.g. ja_keyboard.
function TermInputText:addChars(chars, skip_callback, skip_table_concat)
    -- the same as in inputtext.lua
    if not chars then
        -- VirtualKeyboard:addChar(key) gave us 'nil' once (?!)
        -- which would crash table.concat()
        return
    end
    if self.enter_callback and chars == "\n" and not skip_callback then
        UIManager:nextTick(self.enter_callback)
        return
    end

    -- this is an addon to inputtext.lua
    if self.strike_callback and not skip_callback then
        self.strike_callback(chars)
        return
    end

    -- the same as in inputtext.lua
    if self.readonly or not self:isTextEditable(true) then
        return
    end

    self.is_text_edited = true
    if #self.charlist == 0 then -- widget text is empty or a hint text is displayed
        self.charpos = 1 -- move cursor to the first position
    end

    local function insertSpaces(n)
        if n > 0 then
            table.move(self.charlist, self.charpos, #self.charlist, self.charpos+n)
            for i = self.charpos, self.charpos+n-1 do
                self.charlist[i] = " "
            end
        end
        return self.charpos + math.max(0, n)
    end

    -- this is a modification of inputtext.lua
    local chars_list = util.splitToChars(chars) -- for UTF8
    for i = 1, #chars_list do
        if chars_list[i] == "\n" then
            -- detect current column
            local pos = self.charpos
            while pos > 0 and self.charlist[pos] ~= "\n" do
                pos = pos - 1
            end
            local column = self.charpos - pos

            if self.scroll_region_line then
                self:scrollRegionUp(column)
            end

            -- go to EOL
            while self.charlist[self.charpos] and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos + 1
            end

            if not self.charlist[self.charpos] then -- add new line if necessary
                table.insert(self.charlist, self.charpos, "\n")
                self.charpos = self.charpos + 1
            end

            -- go to column in next line
            if not self.charlist[self.charpos] then
                self.charpos = insertSpaces(column - 1)
            end

            if self.charlist[self.charpos] then
                self.charpos = self.charpos + 1
            end

            -- fill line
            if not self.charlist[self.charpos] then
                local p = insertSpaces(self.maxc + 1 - column)
                table.insert(self.charlist, p, "\n")
            end
        elseif chars_list[i] == "\r" then
            if self.charlist[self.charpos] == "\n" then
                self.charpos = self.charpos - 1
            end
            while self.charpos >= 1 and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos - 1
            end
            self.charpos = self.charpos + 1
        elseif chars_list[i] == "\b" then
            self.charpos = self.charpos - 1
        else
            if self.wrap then
                if self.charlist[self.charpos] == "\n" then
                    self.charpos = self.charpos + 1
                    if not self.charlist[self.charpos] then
                        local p = insertSpaces(self.maxc)
                        table.insert(self.charlist, p, "\n")
                    end
                end
            else
                local column = 1
                local pos = self.charpos
                while pos > 0 and self.charlist[pos] ~= "\n" do
                    pos = pos - 1
                    column = column + 1
                end
                if self.charlist[self.charpos] == "\n" or column > self.maxc then
                    self.charpos = self.charpos - 1
                end
            end
            self.charlist[self.charpos] = chars_list[i]
            self.charpos = self.charpos + 1
        end
    end

    -- the same as in inputtext.lua
    if not skip_table_concat then
        self:initTextBox(table.concat(self.charlist), true)
    end
end
dbg:guard(TermInputText, "addChars",
    function(self, chars)
        assert(type(chars) == "string",
            "TermInputText: Wrong chars value type (expected string)!")
    end)

-- @fixme: this secondary buffer mode has nothing to do with the meaning of
-- escape codes ^[= and ^[> according to VT52/VT100 documentation. Delete?
function TermInputText:enterAlternateKeypad()
    self.store_position = self.charpos
    self:formatTerminal(true)
end

function TermInputText:exitAlternateKeypad()
    if self.store_position then
        self.charpos = self.store_position
        self.store_position = nil
        -- clear the alternate keypad buffer
        while self.charlist[self.charpos] do
            table.remove(self.charlist, self.charpos)
        end
    end
end

--- generates a "tty-matrix"
-- @param maxr number of rows
-- @param maxc number of columns
-- @param clear if true, fill the matrix ' '
function TermInputText:formatTerminal(clear)
    local i = self.store_position or 1
    -- so we end up in a maxr x maxc array for positioning
    for r = 1, self.maxr do
        for c = 1, self.maxc do
            if not self.charlist[i] then -- end of text
                table.insert(self.charlist, i, "\n")
            end

            if self.charlist[i] ~= "\n" then
                if clear then
                    self.charlist[i] = ' '
                end
            else
                table.insert(self.charlist, i, ' ')
            end
            i = i + 1
        end
        if self.charlist[i] ~= "\n" then
            table.insert(self.charlist, i, "\n")
        end
        i = i + 1  -- skip newline
    end
--    table.remove(self.charlist, i - 1)
end

function TermInputText:moveCursorToRowCol(r, c)
    self:formatTerminal()

    local cur_r, cur_c = 1, 0
    local i = self.store_position or 1
    while i < #self.charlist do
        if self.charlist[i] ~= "\n" then
            cur_c = cur_c + 1
        else
            cur_c = 0 -- as we are at the last NL
            cur_r = cur_r + 1
        end
        self.charpos = i
        if cur_r == r and cur_c == c then
            break
        end
        i = i + 1
    end
    self:moveCursorToCharPos(self.charpos)
end

function TermInputText:clearToEndOfScreen()
    local pos = self.charpos
    while pos <= #self.charlist do
        if self.charlist[pos] ~= "\n" then
            self.charlist[pos] = " "
        end
        pos = pos + 1
    end
    self.is_text_edited = true
--    self:moveCursorToCharPos(self.charpos)
end

function TermInputText:delToEndOfLine()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    local cur_pos = self.charpos
    -- self.charlist[self.charpos] is the char after the cursor
    while self.charlist[cur_pos] and self.charlist[cur_pos] ~= "\n" do
        self.charlist[cur_pos] = " "
        cur_pos = cur_pos + 1
    end
end

-- @fixme This function doesn't implement the documented behaviour of ^[I.
-- According to the DECscope User's Manual EK-VT5X-OP-001:
-- "The cursor is moved up one character position to the same column of the
-- line above the one it was on. If the cursor was on the top line to begin
-- with, it stays where it was, but all the information on the screen appears
-- to move down one line. The information that was on the bottom line of the
-- screen is lost; a new blank line appears at the top line."
function TermInputText:reverseLineFeed(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.page_down)
        return
    end
    if self.charpos > 1 and self.charlist[self.charpos] == "\n" then
        self.charpos = self.charpos - 1
    end
    local cur_col = 0
    while self.charpos > 1 and self.charlist[self.charpos] ~= "\n" do
        self.charpos = self.charpos - 1
        cur_col = cur_col + 1
    end
    if self.charpos > 1 then
        self.charpos = self.charpos + 1
    end
    for i = 1, 80 do
        table.insert(self.charlist, self.charpos, " ")
    end
end

------------------------------------------------------------------
--              overridden InputText methods                    --
------------------------------------------------------------------

function TermInputText:leftChar(skip_callback)
    if self.charpos == 1 then return end
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.cursor_left)
        return
    end
    local left_char = self.charlist[self.charpos - 1]
    if not left_char or left_char == "\n" then
        return
    end
    --InputText.leftChar(self)
    self.charpos = self.charpos - 1
end

function TermInputText:rightChar(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.cursor_right)
        return
    end
    if self.charpos > #self.charlist then return end
    local right_char = self.charlist[self.charpos + 1]
    if not right_char or right_char == "\n" then
        return
    end
    InputText.rightChar(self)
end

function TermInputText:moveCursorUp()
    local pos = self.charpos
    while self.charlist[pos] and self.charlist[pos] ~= "\n" do
        pos = pos - 1
    end
    local column = self.charpos - pos
    pos = pos - 1
    while self.charlist[pos] and self.charlist[pos] ~= "\n" do
        pos = pos - 1
    end
    self.charpos = pos + column
    self:moveCursorToCharPos(self.charpos)
end

function TermInputText:moveCursorDown()
    local pos = self.charpos

    -- detect current column
    while pos > 0 and self.charlist[pos] ~= "\n" do
        pos = pos - 1
    end
    local column = self.charpos - pos

    while self.charlist[self.charpos] and self.charlist[self.charpos] ~= "\n" do
        self.charpos = self.charpos + 1
    end
    self.charpos = self.charpos + 1
    for i = 1, column-1 do
        if self.charlist[pos+i] or self.charlist[pos+i] ~= "\n" then
            self.charpos = self.charpos + 1
        else
            break
        end
    end
    self:moveCursorToCharPos(self.charpos)
end

function TermInputText:delChar()
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    if self.charpos == 1 then return end

    if self.strike_callback then
        self.strike_callback(backspace)
        return
    end
    InputText.delChar(self)
end

function TermInputText:delToStartOfLine()
    return
end

function TermInputText:scrollDown(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.page_down)
        return
    end
    InputText.scrollDown(self)
end

function TermInputText:scrollUp(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.page_up)
        return
    end
    InputText.scrollUp(self)
end

function TermInputText:goToStartOfLine(skip_callback)
    if self.strike_callback then
        if not skip_callback then
            self.strike_callback(esc_seq.cursor_pos1)
        else
            if self.charlist[self.charpos] == "\n" then
                self.charpos = self.charpos - 1
            end
            while self.charpos >= 1 and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos - 1
            end
            self.charpos = self.charpos + 1
            self.text_widget:moveCursorToCharPos(self.charpos)
        end
        return
    end
    InputText.goToStartOfLine(self)
end

function TermInputText:goToEndOfLine(skip_callback)
    if self.strike_callback then
        if not skip_callback then
            self.strike_callback(esc_seq.cursor_end)
        else
            while self.charpos <= #self.charlist and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos + 1
            end
        end
        self.text_widget:moveCursorToCharPos(self.charpos)
        return
    end
    InputText.goToEndOfLine(self)
end

function TermInputText:upLine(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.cursor_up)
        return
    end
    InputText.upLine(self)
end

function TermInputText:downLine(skip_callback)
    if #self.charlist == 0 then return end -- Avoid cursor moving within a hint.
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.cursor_down)
        return
    end
    InputText.downLine(self)
end

return TermInputText
