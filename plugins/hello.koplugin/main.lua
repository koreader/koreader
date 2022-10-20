--[[--

Hello, fellow plugin developer!

This is a plugin that showcases how to hook into KOReader features, such as
the main menu, the events/actions dispatcher and the document registry.

@module koplugin.HelloWorld
--]]--

-- This plugin is disabled by default as it has no real usage for end users.
-- Remove the following if block to enable it
--if true then
--    return { disabled = true, }
--end

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local NonDocument = require("document/nondocument")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

-- most of the plugins have some sort of UI. UIs are built with widgets.
-- In this hello plugin we're using the InfoMessage widget to show a box of text on the screen.
local function showMessage(text)
    UIManager:show(InfoMessage:new{
        text = text,
    })
end

-- plugins inherit from a widget container.
local Hello = WidgetContainer:extend{
    name = "hello",
    is_doc_only = false,
}

-- this showcases how to register an action into the dispatcher.
function Hello:onDispatcherRegisterActions()
    Dispatcher:registerAction("helloworld_action", {category="none", event="HelloWorld", title="Hello World", general=true,})
end

-- this is the action that will be fired when the "HelloWorld" event is triggered. Do notice the prefix 'on' on the name of the action.
function Hello:onHelloWorld()
    showMessage("Hello from dispatcher")
end

-- this showcases how to register an extension into the document registry.
function Hello:onRegisterExtensions()
    -- extensions we want to handle.
    local extensions = {"hello", "hi", "hola"}

    -- in this example we add two actions for each extension, and each action
    -- does *exactly* the same on each extension. Do notice that is possible to have
    -- different `open_func` for different extensions under the same action but is not
    -- possible to assign two different functions for the same extension under the same action.
    local actionA, actionB = {}, {}
    for _, extension in ipairs(extensions) do
        actionA[extension] = {
            mimetype = "text/plain",
            desc = "action A",
            icon_path = self.path .. "/hello.svg",
            open_func = function()
                showMessage("hello from action A")
            end,
        }
        actionB[extension] = {
            mimetype = "text/plain",
            desc = "action B",
            icon_path = self.path .. "/hello.svg",
            open_func = function()
                showMessage("hello from action B")
            end,
        }
    end
    NonDocument:addProvider("HelloActionA", actionA)
    NonDocument:addProvider("HelloActionB", actionB)
end

-- this showcases how to add an entry on the main menu.
function Hello:addToMainMenu(menu_items)
    menu_items.hello_world = {
        text = "Hello World",
        -- in which menu this should be appended
        sorting_hint = "more_tools",
        -- a callback when tapping
        callback = function()
            showMessage("hello from menu")
        end,
    }
end

function Hello:init()
    self:onDispatcherRegisterActions()
    self:onRegisterExtensions()
    self.ui.menu:registerToMainMenu(self)
end

return Hello
