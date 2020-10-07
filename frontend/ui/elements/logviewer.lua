local Font = require("ui/font")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local function downscale(font_size)
    local min = 8
    return font_size > min and font_size - 1 or min
end

local function upscale(font_size)
    local max = 16
    return font_size < max and font_size + 1 or max
end

local function checkFile(f)
    if not f then return end
    local file = io.open(f, "r")
    if file then
        file:close()
        return true
    end
end

local LogViewer = {}

function LogViewer:new(o)
    o.exists = checkFile(o.file)
    setmetatable(o, self)
    self.__index = self
    return o
end

function LogViewer:savedLines()
    return G_reader_settings:readSetting("logviewer_tail_lines") or 20000
end

function LogViewer:truncate()
    if not self.exists then return end
    UIManager:show(require("ui/widget/confirmbox"):new{
        text = T(_("Really truncate %1?"), self.file),
        ok_callback = function()
            local file = io.open(self.file, "w")
            local msg = T(_("%1 [%2 truncated]"), os.date("%x-%X"), self.file)
            if file then
                file:write(msg .. "\n")
                file:close()
            end
        end,
    })
end

function LogViewer:getLog(lines)
    local file = io.open(self.file, "r")
    local tail = type(lines) == "number"
    if tail then
        file:seek("end", -lines)
    end
    local content = file:read("*all") or _("empty")
    file:close()
    if tail then
        if content:len() == lines then
            local first_cr = content:find("\n")
            if first_cr then
                content = content:sub(first_cr + 1)
            end
            content = T(_("[Start of %1 not shown]\n"), self.file) .. content
        else
            content = T(_("[Start of %1\n"), self.file) .. content
        end
    end
    return content
end

function LogViewer:show(lines)
    if not self.exists then return end
    local size = G_reader_settings:readSetting("logviewer_font_size") or 10
    self:update(lines, size)
end

function LogViewer:update(lines, size)
    local subtitle = _("full")
    if type(lines) == "number" then
        subtitle = T(_("tail %1 lines"), lines)
    end
    G_reader_settings:saveSetting("logviewer_font_size", size)
    self.textviewer = TextViewer:new{
        title = string.format("%s (%s)", self.file, subtitle),
        text = self:getLog(lines),
        text_face = Font:getFace("infont", size),
        width = self.textviewer_width,
        height = self.textviewer_height,
        justified = false,
        buttons_table = {
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
                        self:update(lines, downscale(size))
                    end,
                },
                {
                    text = _("A+"),
                    callback = function()
                        UIManager:close(self.textviewer)
                        self:update(lines, upscale(size))
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
    }
    self.textviewer.scroll_text_w:scrollToBottom()
    UIManager:show(self.textviewer)
end

return LogViewer
