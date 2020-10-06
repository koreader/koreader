local Font = require("ui/font")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

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

function LogViewer:loadLog()
    local file = io.open(self.file, "r")
    local tail = type(self.maxsize) == "number"
    if tail then
        file:seek("end", -self.maxsize)
    end
    local content = file:read("*all") or _("empty")
    file:close()
    if tail then
        if content:len() == self.maxsize then
            local first_cr = content:find("\n")
            if first_cr then
                content = content:sub(first_cr + 1)
            end
            content = T(_("[Start of %1 not shown]\n"), self.file) .. content
        else
            content = T(_("[Start of %1\n"), self.file) .. content
        end
    end
    self.content = content
end

function LogViewer:show(maxsize)
    if not self.exists then return end
    self.maxsize = maxsize
    self:loadLog()

    self.textviewer = TextViewer:new{
        title = self.file,
        text = self.content,
        text_face = Font:getFace("infont", 10),
        width = self.textviewer_width,
        height = self.textviewer_height,
        justified = false,
        buttons_table = {
            {
                {
                    text = "<<",
                    callback = function()
                        self.textviewer.scroll_text_w:scrollToTop()
                    end,
                },
                {
                    text = "<",
                    callback = function()
                        self.textviewer.scroll_text_w:scrollUp()
                    end,
                },
                {
                    text = ">",
                    callback = function()
                        self.textviewer.scroll_text_w:scrollDown()
                    end,
                },
                {
                    text = ">>",
                    callback = function()
                        self.textviewer.scroll_text_w:scrollToBottom()
                    end,
                }
            },
            {
                {
                    text = _("Update"),
                    enabled = false,
                    callback = function()
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
