--[[--
NonDocument

any file *with extension* can become a nondocument
if there's one or more providers that know how to open it.

@module nondocument
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Document = require("document/document")
local DocumentRegistry = require("document/documentregistry")
local RenderImage = require("ui/renderimage")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local function getIcon(path, width, height, zoom)
    local bb, is_straight_alpha = RenderImage:renderSVGImageFile(path, width, height, zoom)
    local icon = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    icon:fill(Blitbuffer.COLOR_WHITE)
    if is_straight_alpha then
        if Screen.sw_dithering then
            icon:ditheralphablitFrom(bb, 0, 0, 0, 0, icon.w, icon.h)
        else
            icon:alphablitFrom(bb, 0, 0, 0, 0, icon.w, icon.h)
        end
    else
        if Screen.sw_dithering then
            icon:ditherpmulalphablitFrom(bb, 0, 0, 0, 0, icon.w, icon.h)
        else
            icon:pmulalphablitFrom(bb, 0, 0, 0, 0, icon.w, icon.h)
        end
    end
    return icon
end

local NonDocument = Document:extend{
    _document = false,
    provider = "nondocument",
    provider_name = _("File Manager"),

    extensions = {},
    providers = {},
}

function NonDocument:_readMetadata() return true end

function NonDocument:init() end
function NonDocument:close() end
function NonDocument:register() end
function NonDocument:getPageCount() end

function NonDocument:getProps()
    local _, _, docname = self.file:find(".*/(.*)")
    docname = docname or self.file
    return {
        title = docname:match("(.*)%."),
    }
end

function NonDocument:getCoverPageImage()
    local extension = util.getFileNameSuffix(self.file)
    for __, v in ipairs(self.extensions[extension]) do
        if v.icon_path then
            return getIcon(v.icon_path, 100, 100, 4)
        end
    end
end

function NonDocument:open(file)
    local extension = util.getFileNameSuffix(file)
    if not self.extensions[extension] then return end
    if #self.extensions[extension] > 1 then
        -- more than one action registered. Show a menu to let the user choose
        local buttons = {}
        for index, action in ipairs(self.extensions[extension]) do
            table.insert(buttons, {
                {
                    text = action.desc,
                    callback = function()
                        UIManager:close(self.choose_dialog)
                        self.extensions[extension][index].open_func(file)
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
        self.extensions[extension][1].open_func(file)
    end
end

--[[--
Register actions for specific extensions.

An action is an operation done on a given extension.
It is represented as a table with some fields:

    desc        description of what the action does
    open_func   a function that performs the operation on a specific file
    mimetype    the mimetype for the extension
    icon_path   (optional) icon for the extension

Actions can be shared between different extensions but you cannot register different
actions for a single extension with the same id.

If you want to register multiple actions for each extension then call this method as many
times as you need, using different identifiers for each action.

@param id string unique identifier
@param t table of extensions/actions
@treturn true on success
]]

function NonDocument:addProvider(id, t)
    assert(type(id) == "string", "string expected")
    -- prevent duplicates
    for __, v in ipairs(self.providers) do
        if id == v then
            return
        end
    end

    assert(type(t) == "table", "table expected")
    local actions = {}
    for k, v in pairs(t) do
        local action = {}
        if type(v) == "table" then
            action.extension = k
            action.desc = v.desc
            action.mimetype = v.mimetype
            action.open_func = v.open_func
            action.icon_path = v.icon_path -- optional
        end
        if action.extension and action.desc and action.mimetype and action.open_func then
            table.insert(actions, action)
        end
    end

    if #actions < 1 then
        logger.warn(id, "no valid actions")
        return
    end

    table.insert(self.providers, id)
    for __, v in ipairs(actions) do
        if not self.extensions[v.extension] then
            self.extensions[v.extension] = {}
            DocumentRegistry:addProvider(v.extension, v.mimetype, self, 20)
        end
        table.insert(self.extensions[v.extension], v)
    end
    return true
end

return NonDocument
