-- NonDocument type for files that are not intended to be viewed
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local DocumentRegistry = require("document/documentregistry")
local RenderImage = require("ui/renderimage")
local UIManager = require("ui/uimanager")
local Document = require("document/document")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local NonDocument = Document:extend{
    _document = false,
    provider = "nondocument",
    provider_name = _("File Manager"),

    -- a dictionary of actions per extension
    actions = {},

    -- an array of provider names
    providers = {},

}

function NonDocument:_readMetadata() return true end

function NonDocument:init() end
function NonDocument:close() end
function NonDocument:register() end
function NonDocument:getPageCount() end

function NonDocument:getProps()
    logger.info("getProps")
    local _, _, docname = self.file:find(".*/(.*)")
    docname = docname or self.file
    return {
        title = docname:match("(.*)%."),
    }
end

function NonDocument:getCoverPageImage()
    local extension = util.getFileNameSuffix(self.file)
    if not extension then return end
    for __, v in ipairs(self.actions[extension]) do
        if v.icon_path then
            return RenderImage:renderSVGImageFile(v.icon_path, 100, 100, 4)
        end
    end
end

-- open a given file with available actions for the extension
function NonDocument:open(file)
    local extension = util.getFileNameSuffix(file)
    if not self.actions[extension] then return end
    if #self.actions[extension] > 1 then
        -- more than one action registered. Show a menu to let the user choose
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
        -- a single action
        self.actions[extension][1].open_func(file)
    end
end

-- plugins need to call this method to register themselves as handlers for specific file
-- extensions.
--
--TODO: document me better
--
-- name is the unique identifier for the handler.
-- t is a dictionary of extensions/actions.
-- actions is an array of standalone things to do with a file of a given extension

function NonDocument:addHandler(name, t)
    assert(type(name) == "string", "string expected")
    for __, v in ipairs(self.providers) do
        if name == v then
            return
        end
    end

    assert(type(t) == "table", "table expected")
    local handlers = {}
    for k, v in pairs(t) do
        local handler = {}
        if type(v) == "table" then
            handler.extension = k
            handler.desc = v.desc
            handler.mimetype = v.mimetype
            handler.open_func = v.open_func
            handler.icon_path = v.icon_path -- optional
        end
        if handler.extension and handler.desc and handler.mimetype and handler.open_func then
            table.insert(handlers, handler)
        end
    end

    table.insert(self.providers, name)
    for __, v in ipairs(handlers) do
        if not self.actions[v.extension] then
            self.actions[v.extension] = {}
            DocumentRegistry:addProvider(v.extension, v.mimetype, self, 20)
        end
        table.insert(self.actions[v.extension], v)
    end
end


return NonDocument
