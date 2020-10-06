local UIManager = require("ui/uimanager")
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

local M = {}

function M:new(o)
    o.exists = checkFile(o.file)
    setmetatable(o, self)
    self.__index = self
    return o
end

function M:truncate()
    if not self.exists then return end
    UIManager:show(require("ui/widget/confirmbox"):new{
        text = T(_("Really truncate %1?"), self.file),
        ok_callback = function()
            local file = io.open(self.file, "w")
            if file then file:close() end
            require("logger").info(T(_("[%1 truncated]"), self.file))
        end,
    })
end

function M:show(maxsize)
    if not self.exists then return end
    local file = io.open(self.file, "r")
    local tail = type(maxsize) == "number"
    if tail then
        file:seek("end", -maxsize)
    end
    local content = file:read("*all") or _("empty")
    file:close()
    if tail then
        if content:len() == maxsize then
            local first_cr = content:find("\n")
            if first_cr then
                content = content:sub(first_cr+1)
            end
            content = T(_("[Start of %1 not shown]\n"), self.file) .. content
        else
            content = T(_("[Start of %1\n"), self.file) .. content
        end
    end
    local Font = require("ui/font")
    local view = require("ui/widget/textviewer"):new{
        title = self.file,
        text = content,
        text_face = Font:getFace("infont", 10),
        justified = false,
    }
    view.scroll_text_w:scrollToRatio(1)
    require("ui/uimanager"):show(view)
end

return M
