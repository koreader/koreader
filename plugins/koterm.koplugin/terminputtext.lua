--[[
module used for terminal emulator to override InputText
]]

local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local logger = require("logger")
local util = require("util")

local esc = "\027"

local esc_seq = {
    backspace = "\008",
    cursor_left =  "\027[D",
    cursor_right = "\027[C",
    cursor_up =    "\027[A",
    cursor_down =  "\027[B",
    cursor_pos1 =  "\027[7~",
    cursor_end =   "\027[8~",
    page_up =      "\027[5~",
    page_down =    "\027[6~",
}

local TermInputText = InputText:extend{
    maxr = 40,
    maxc = 80,
    strike_callback = nil,
    sequence_state = "",
}

function TermInputText:onTapTextBox(arg, ges)
    -- disable positioning cursor by tap in emulator mode
    return true
end

function TermInputText:addChars(chars, skip_callback)
    if not chars then
        -- VirtualKeyboard:addChar(key) gave us 'nil' once (?!)
        -- which would crash table.concat()
        return
    end
    if self.enter_callback and chars == "\n" and not skip_callback then
        UIManager:scheduleIn(0.3, function() self.enter_callback() end)
        return
    end
    if self.strike_callback and not skip_callback then
        self.strike_callback(chars)
        return
    end
    if self.readonly or not self:isTextEditable(true) then
        return
    end

    self.is_text_edited = true
    if #self.charlist == 0 then -- widget text is empty or a hint text is displayed
        self.charpos = 1 -- move cursor to the first position
    end

    local chars_list = util.splitToChars(chars) -- for UTF8
    for i = 1, #chars_list do
        if chars_list[i] == "\n" then
            local pos = self.charpos

            -- detect current column
            while pos > 0 and self.charlist[pos] ~= "\n" do
                pos = pos - 1
            end
            local column = self.charpos - pos

            -- go to EOL
            pos = self.charpos
            while self.charlist[pos] and self.charlist[pos] ~= "\n" do
                pos = pos + 1
            end

            if not self.charlist[pos] then -- add new line if necessary
                table.insert(self.charlist, pos, "\n")
                pos = pos + 1
            end

            -- go to column in next line
            for j = 1, column-1 do
                if self.charlist[pos+i] or self.charlist[pos+i] ~= "\n" then
                    table.insert(self.charlist, pos, " ")
                else
                    break
                end
            end
            self.charpos = pos
        elseif chars_list[i] == "\r" then
            if self.charlist[self.charpos] == "\n" then
                self.charpos = self.charpos - 1
            end
            while self.charpos >=1 and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos - 1
            end
            self.charpos = self.charpos + 1
        elseif chars_list[i] == "\b" then
            self.charpos = self.charpos - 1
        else
            if self.charlist[self.charpos] == "\n" then
                self.charpos = self.charpos + 1
            end
            table.remove(self.charlist, self.charpos)
            table.insert(self.charlist, self.charpos, chars_list[i])
            self.charpos = self.charpos + 1
        end
    end
    self:initTextBox(table.concat(self.charlist), true)
    return
end
dbg:guard(TermInputText, "addChars",
    function(self, chars)
        assert(type(chars) == "string",
            "TermInputText: Wrong chars value type (expected string)!")
    end)

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
-- @param clear if true, fill the matrix with filler
-- @param filler if unset, use ' '
function TermInputText:formatTerminal(clear, filler)
    filler = filler or " "

    local i = self.store_position or 1
    -- so we end up in a maxr x maxc array for positioning
    for r = 1, self.maxr do
        for c = 1, self.maxc do
            if not self.charlist[i] then -- end of text
                table.insert(self.charlist, i, "\n")
            end

            if self.charlist[i] ~= "\n" then
                if clear then
                    self.charlist[i] = filler
                end
            else
                table.insert(self.charlist, i, filler)
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
    if r==1 and c==1 and not self.store_position then
        self.store_position = self.charpos
    end

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
    self:initTextBox(table.concat(self.charlist))
    self:moveCursorToCharPos(self.charpos)
end

function TermInputText:delToEndOfLine(is_terminal)
    if self.readonly or not self:isTextEditable(true) then
        return
    end
    local cur_pos = self.charpos
    -- self.charlist[self.charpos] is the char after the cursor
    while self.charlist[cur_pos] and self.charlist[cur_pos] ~= "\n" do
        if not is_terminal then
            table.remove(self.charlist, cur_pos)
        else
            self.charlist[cur_pos]=" "
            cur_pos = cur_pos + 1
        end
    end
    -- delete the newline at end
    if self.charlist[cur_pos] ~= "\n" and not is_terminal then
        table.remove(self.charlist, cur_pos)
    end
    self.is_text_edited = true
    self:initTextBox(table.concat(self.charlist))
end

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
    InputText.leftChar(self)
end

function TermInputText:rightChar(skip_callback)
    if self.strike_callback and not skip_callback then
        self.strike_callback(esc_seq.cursor_right)
        return
    end
    if self.charpos > #self.charlist then return end
    local right_char = self.charlist[self.charpos + 1]
    if not right_char and right_char == "\n" then
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
        self.strike_callback(esc_seq.backspace)
        return
    end
    InputText.delChar(self)
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
            while self.charpos >=1 and self.charlist[self.charpos] ~= "\n" do
                self.charpos = self.charpos - 1
            end
            self.charpos = self.charpos + 1
        end
        self.text_widget:moveCursorToCharPos(self.charpos)
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

--------------------- move this up ------

function TermInputText:resize(maxr, maxc)
    self.maxr = maxr
    self.maxc = maxc
end

function TermInputText:_helperVT52VT100(cmd, param1, param2, param3)
    if cmd == "A" then -- cursor up
        param1 = param1 == 0 and 1 or param1
        for i = 1, param1 do
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
        return true
    elseif cmd == "J" then -- clear to end of screen
        self:clearToEndOfScreen()
        return true
    elseif cmd == "K" then -- clear to end of line
        self:delToEndOfLine(true)
        return true
    elseif cmd == "m" then
        -- graphics mode not supported yet(?)
        return true
    elseif cmd == "n" then
        --- @todo
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

function TermInputText:interpretAnsiSeq(text)
    local pos = 1
    local param1, param2, param3 = 0, 0, 0

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
                self:addChars(part, true)
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
                logger.dbg("KOTerm: enter graphics mode not supported")
            elseif next_byte == "G" then -- exit graphics mod
                logger.dbg("KOTerm: leave graphics mode not supported")
            elseif next_byte == "H" then -- cursor home
                self:moveCursorToRowCol(1, 1)
            elseif next_byte == "I" then -- reverse line feed (cursor up and insert line)
                self:reverseLineFeed(true)
            elseif next_byte == "J" then -- clear to end of screen
                self:clearToEndOfScreen()
            elseif next_byte == "K" then -- clear to end of line
                self:delToEndOfLine(true)
            elseif next_byte == "L" then -- insert line
                logger.dbg("KOTerm: insert not supported")
            elseif next_byte == "M" then -- remove line
                logger.dbg("KOTerm: remove line not supported")
            elseif next_byte == "Y" then -- set cursor pos (row, col)
                self.sequence_state = "escY"
            elseif next_byte == "Z" then -- ident(ify)
                self:transmit("\027/K") -- identify as VT52 without printer
            elseif next_byte == "=" then -- alternate keypad
                self:enterAlternateKeypad()
            elseif next_byte == ">" then -- exit alternate keypad
                self:exitAlternateKeypad()
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
                self:moveCursorToRowCol(row, col)
                param1, param2, param3 = 0, 0, 0
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
            if not self:_helperVT52VT100(next_byte, param1, param2, param3) then
                -- drop other VT100 sequences
                logger.info("xxxxxxxxx ANSI-final: not supported", next_byte,
                    next_byte:byte(), next_byte)
            end
            param1, param2, param3 = 0, 0, 0
            self.sequence_state = ""
        else
            logger.dbg("KOTerm: detected error in esc sequence, not my fault.")
            self.sequence_state = ""
        end -- self.sequence_state

        pos = pos + 1
    end
end

return TermInputText
