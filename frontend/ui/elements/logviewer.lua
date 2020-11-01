--[[ This module implements a log viewer.

 Its intended usage is for crash.log, but you can repurpose it for your own file.
 All logviewer instances share the same settings but you can override them if you wish.

]]--

local Font = require("ui/font")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local BUTTONS_IN_ROW = 4
local MIN_FONT_SIZE, MAX_FONT_SIZE = 6, 40
local MIN_FILE_SIZE, MAX_FILE_SIZE = 4 * 1024, 512 * 1024

local function getSize(file)
    if not file then return end
    local handle, err = io.open(file, "r")
    if handle then
        local bytes = handle:seek("end")
        handle:close()
        return bytes
    end
end

local function scaleFont(size, direction)
    if type(size) ~= "number" then return end
    if size < MAX_FONT_SIZE and direction == "up" then
        return size + 1
    elseif size > MIN_FONT_SIZE and direction == "down" then
        return size - 1
    else
        return size
    end
end

local function scaleBytes(file, bytes)
    local full_size = getSize(file)
    local max_size = full_size <= MAX_FILE_SIZE and full_size or MAX_FILE_SIZE
    
    if type(bytes) ~= "number" or bytes <= 0 then
        if full_size >= MIN_FILE_SIZE then
            return MIN_FILE_SIZE
        else
            return nil
        end
    else
        local result = bytes * 2
        if result >= max_size then
            result = nil
        end
        return result
    end
end

local LogViewer = {}

function LogViewer:new(o)
    setmetatable(o, self)
    self.__index = self
    return o:init(o.file)
end

function LogViewer:init(file)
    if not file then return nil, "file not specified" end
    local handle = io.open(file, "r")
    if handle then
        handle:close()
        self._exists = true
    end

    -- default settings if there's no override
    for k, v in pairs({
        font_face = "infont",
        font_size = 10,
        tail_bytes = 512 * 1024,
    }) do
        if not self[k] then
            self[k] = v
        end
    end
    return self
end

-- getters and setters for G_reader_settings
function LogViewer:getFontSize()
    return G_reader_settings:readSetting("logviewer_font_size") or self.font_size
end

function LogViewer:setFontSize(size)
    G_reader_settings:saveSetting("logviewer_font_size", size or self.font_size)
end

function LogViewer:getTailBytes()
    return G_reader_settings:readSetting("logviewer_tail_bytes") or self.tail_bytes
end

function LogViewer:setTailBytes(bytes)
    G_reader_settings:saveSetting("logviewer_tail_bytes", bytes or self.tail_bytes)
end

function LogViewer:exists()
    return self._exists
end

function LogViewer:truncate()
    if not self._exists then return end
    UIManager:show(require("ui/widget/confirmbox"):new{
        text = T(_("Really truncate %1?"), self.file),
        ok_callback = function()
            local handle, err = io.open(self.file, "w")
            if not handle then return nil, err end
            handle:write(T(_("%1 [%2 truncated]"), os.date("%x-%X"), self.file))
            handle:close()
        end,
    })
end

function LogViewer:read(tail_bytes)
    local handle, err = io.open(self.file, "r")
    if not handle then return nil, err end
    local tailOnly = type(tail_bytes) == "number"

    if tailOnly then
        handle:seek("end", -tail_bytes)
    end

    local content = handle:read("*all")
    handle:close()

    if tailOnly then
        if content:len() == tail_bytes then
            local first_cr = content:find("\n")
            if first_cr then
                content = content:sub(first_cr + 1)
            end
            content = T(_("[Start of %1 not shown]\n"), self.file) .. content
        else
            content = T(_("[Start of %1]\n"), self.file) .. content
        end
    end

    return content
end

function LogViewer:show()
    if not self._exists then return end
    self:update()
end

function LogViewer:getTitle(bytes)
    local path, fname = util.splitFilePathName(self.file)
    if fname == "" then
        fname = path
    end

    if bytes and bytes > 0 then
        size = string.format("Last %dKB", bytes/1024)
    else
        size = string.format("All %dKB", getSize(self.file)/1024)
    end
    return string.format("%s (%s)", fname, size)
end

function LogViewer:update(bytes, size, filter)
    if not size then
        size = self:getFontSize() or self.font_size
    else
        self:setFontSize(size)
    end
    
    if bytes then
        self:setTailBytes(bytes)
    end

    local input_text = self:read(bytes)
    local output_text = type(filter) == "function" and filter(input_text)
        or input_text

    -- UI buttons
    local buttons_table = {
        {
            {
                text = "▕◁",
                callback = function()
                    self.textviewer.scroll_text_w:scrollToTop()
                end,
            },
            {
                text = "◁",
                callback = function()
                    self.textviewer.scroll_text_w:scrollUp()
                end,
            },
            {
                text = "▷",
                callback = function()
                    self.textviewer.scroll_text_w:scrollDown()
                end,
            },
            {
                text = "▷▏",
                callback = function()
                    self.textviewer.scroll_text_w:scrollToBottom()
                end,
            }
        },
        {
            {
                text = _("A-"),
                callback = function()
                    UIManager:close(self.textviewer)
                    self:update(bytes, scaleFont(size, "down"), filter)
                end,
            },
            {
                text = _("A+"),
                callback = function()
                    UIManager:close(self.textviewer)
                    self:update(bytes, scaleFont(size, "up"), filter)
                end,
            },
            {
                text_func = function()
                    if not bytes or bytes <= 0 then
                        return _("All")
                    else
                        return T(_("%1 kb"), bytes / 1024)
                    end
                end,
                callback = function()
                    UIManager:close(self.textviewer)
                    self:update(scaleBytes(self.file, bytes), size, filter)
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(self.textviewer)
                end,
            },
        },
    }

    if self.disable_arrows then
        table.remove(buttons_table, 1)
    end

    -- hook user-defined buttons in the UI
    if type(self.user_buttons) == "table" then
        local buttons = #self.user_buttons
        local offset = #buttons_table - 1
        local rows = math.ceil(buttons / BUTTONS_IN_ROW)
        for row = #buttons_table, offset + rows do
            table.insert(buttons_table, row, {})
        end
        for index, value in ipairs(self.user_buttons) do
            local row
            repeat
                row = row and row + 1 or 1
            until(index <= math.floor(math.ceil(buttons/rows) * row))
            table.insert(buttons_table[row + offset], value)
        end
    end

    if self.textviewer then
        UIManager:close(self.textviewer)
    end

    self.textviewer = TextViewer:new{
        title = self:getTitle(bytes),
        text = output_text,
        text_face = Font:getFace(self.font_face, size),
        width = self.textviewer_width,
        height = self.textviewer_height,
        justified = false,
        buttons_table = buttons_table
    }

    self.textviewer.scroll_text_w:scrollToBottom()
    UIManager:show(self.textviewer)
end

return LogViewer
