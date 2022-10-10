local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Document = require("document/document")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local FileManagerDocument = Document:extend{
    _document = false,
    provider = "filemanagerdocument",
    provider_name = "File Manager",

    -- a dictionary of actions per extension
    actions = {},

    -- an array of provider names
    providers = {},
}

function FileManagerDocument:init() end
function FileManagerDocument:close() end
function FileManagerDocument:register() end

-- opens a file with the provider with highest priority for that extension
function FileManagerDocument:open(file)
    local extension = util.getFileNameSuffix(file)
    if not self.actions[extension] then return end

    if #self.actions[extension] > 1 then
        -- more than one action paired to this extension. Show a menu to let the user choose between them.
        local buttons = {}
        for index, action in ipairs(self.actions[extension]) do
            table.insert(buttons, {
                {
                    text = action.desc,
                    callback = function()
                        UIManager:close(self.choose_dialog)
                        self.actions[extension][index].open_func(file)
                    end,
                },
            })
        end
        self.choose_dialog = ButtonDialogTitle:new{
            title = _("Choose action"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.choose_dialog)
    else
        self.actions[extension][1].open_func(file)
    end
end

function FileManagerDocument:addHandler(name, t)
    assert(type(name) == "string", "string expected")
    assert(type(t) == "table", "table expected")

    -- don't add duplicates
    for __, v in ipairs(self.providers) do
        if name == v then
            return
        end
    end

    local extension, mimetype, open_func
    for k, v in pairs(t) do
        if type(v) == "table" then
            if type(k) == "string" then
                extension = k
            end
            if type(v.mimetype) == "string" then
                mimetype = v.mimetype
            end
            if type(v.open_func) == "function" then
                open_func = v.open_func
            end
        end

        if extension and mimetype and open_func then
            v.provider = name
            if not self.actions[extension] then
                self.actions[extension] = {}
                require("document/documentregistry"):addProvider(extension, mimetype, self, 20)
            end
            table.insert(self.actions[extension], v)
        end
    end
end

function FileManagerDocument:getProps()
    local _, _, docname = self.file:find(".*/(.*)")
    docname = docname or self.file
    return {
        title = docname:match("(.*)%."),
    }
end

function FileManagerDocument:_readMetadata()
    Document._readMetadata(self)
    return true
end

function FileManagerDocument:getCoverPageImage()
    return nil
end

return FileManagerDocument
