#!./koreader-base

require "defaults"
print(package.path)
package.path = "./frontend/?.lua;./?.lua"
local UIManager = require("ui/uimanager")
local RenderText = require("ui/rendertext")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Menu = require("ui/widget/menu")
local Widget = require("ui/widget/widget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local TouchMenu = require("ui/widget/touchmenu")
local InputText = require("ui/widget/inputtext")
local DocumentRegistry = require("document/documentregistry")
local ReaderUI = require("ui/readerui")
local Dbg = require("dbg")
local Device = require("ui/device")
local Screen = require("ui/screen")


-----------------------------------------------------
-- widget that paints the grid on the background
-----------------------------------------------------
TestGrid = Widget:new{}

function TestGrid:paintTo(bb)
    v_line = math.floor(bb:getWidth() / 50)
    h_line = math.floor(bb:getHeight() / 50)
    for i=1,h_line do
        y_num = i*50
        RenderText:renderUtf8Text(bb, 0, y_num+10, Font:getFace("ffont", 12), y_num, true)
        bb:paintRect(0, y_num, bb:getWidth(), 1, 10)
    end
    for i=1,v_line do
        x_num = i*50
        RenderText:renderUtf8Text(bb, x_num, 10, Font:getFace("ffont", 12), x_num, true)
        bb:paintRect(x_num, 0, 1, bb:getHeight(), 10)
    end
end

-----------------------------------------------------
-- we create a widget that paints a background:
-----------------------------------------------------
Background = InputContainer:new{
    is_always_active = true, -- receive events when other dialogs are active
    key_events = {
        OpenDialog = { { "Press" } },
        OpenConfirmBox = { { "Del" } },
        QuitApplication = { { {"Home","Back"} } }
    },
    -- contains a gray rectangular desktop
    FrameContainer:new{
        background = 3,
        bordersize = 0,
        dimen = Screen:getSize(),
        Widget:new{
            dimen = {
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
        },
    }
}

function Background:onOpenDialog()
    UIManager:show(InfoMessage:new{
        text = "Example message.",
        timeout = 10
    })
end

function Background:onOpenConfirmBox()
    UIManager:show(ConfirmBox:new{
        text = "Please confirm delete"
    })
end

function Background:onInputError()
    UIManager:quit()
end

function Background:onQuitApplication()
    UIManager:quit()
end



-----------------------------------------------------
-- example widget: a clock
-----------------------------------------------------
Clock = FrameContainer:new{
    background = 0,
    bordersize = 1,
    margin = 0,
    padding = 1
}

function Clock:schedFunc()
    self[1]:free()
    self[1] = self:getTextWidget()
    UIManager:setDirty(self)
    -- reschedule
    -- TODO: wait until next real second shift
    UIManager:scheduleIn(1, function() self:schedFunc() end)
end

function Clock:onShow()
    self[1] = self:getTextWidget()
    self:schedFunc()
end

function Clock:getTextWidget()
    return CenterContainer:new{
        dimen = { w = 300, h = 25 },
        TextWidget:new{
            text = os.date("%H:%M:%S"),
            face = Font:getFace("cfont", 12)
        }
    }
end

-----------------------------------------------------
-- a confirmbox box widget
-----------------------------------------------------
Quiz = ConfirmBox:new{
    text = "Tell me the truth, isn't it COOL?!",
    width = 300,
    ok_text = "Yes, of course.",
    cancel_text = "No, it's ugly.",
    cancel_callback = function()
        UIManager:show(InfoMessage:new{
            text="You liar!",
        })
    end,
}

-----------------------------------------------------
-- a menu widget
-----------------------------------------------------
menu_items = {
    {text = "item1"},
    {text = "item2"},
    {text = "This is a very very log item whose length should exceed the width of the menu."},
    {text = "item3"},
    {text = "item4"},
    {text = "item5"},
    {text = "item6"},
    {text = "item7"},
    {text = "item8"},
    {text = "item9"},
    {text = "item10"},
    {text = "item11"},
    {text = "item12"},
    {text = "item13"},
    {text = "item14"},
    {text = "item15"},
    {text = "item16"},
    {text = "item17"},
}
M = Menu:new{
    title = "Test Menu",
    item_table = menu_items,
    width = 500,
    height = 600,
}


-----------------------------------------------------
-- a reader view widget
-----------------------------------------------------
readerwindow = CenterContainer:new{
    dimen = Screen:getSize(),
    FrameContainer:new{
        background = 0
    }
}
reader = ReaderUI:new{
    dialog = readerwindow,
    dimen = Geom:new{ w = Screen:getWidth() - 100, h = Screen:getHeight() - 100 },
    document = DocumentRegistry:openDocument("test/2col.pdf")
    --document = DocumentRegistry:openDocument("test/djvu3spec.djvu")
    --document = DocumentRegistry:openDocument("./README.TXT")
}
readerwindow[1][1] = reader


touch_menu = TouchMenu:new{
    title = "Document menu",
    width = Screen:getWidth(),
    tab_item_table = {
        {
            icon = "resources/icons/appbar.pokeball.png",
            {
                text = "item1",
                callback = function()
                end,
            },
            {
                text = "item2",
                callback = function()
                end,
            },
            {
                text = "item3",
                callback = function()
                end,
            },
            {
                text = "item4",
                callback = function()
                end,
            },
            {
                text = "item5",
                callback = function()
                end,
            },
            {
                text = "item6",
                callback = function()
                end,
            },
            {
                text = "item7",
                callback = function()
                end,
            },
            {
                text = "item8",
                callback = function()
                end,
            },
            {
                text = "item9",
                callback = function()
                end,
            },
        },
        {
            icon = "resources/icons/appbar.page.corner.bookmark.png",
            {
                text = "item10",
                callback = function()
                end,
            },
            {
                text = "item11",
                callback = function()
                end,
            },
        },
        {
            icon = "resources/icons/appbar.home.png",
            callback = function()
                DEBUG("hello world!")
            end
        }
    },
}

inputtext = InputText:new{
    width = 400,
    height = 300,
}

-----------------------------------------------------------------------
-- you may want to uncomment following show calls to see the changes
-----------------------------------------------------------------------
UIManager:show(Background:new())
UIManager:show(TestGrid)
--UIManager:show(Clock:new())
--UIManager:show(M)
--UIManager:show(Quiz)
--UIManager:show(readerwindow)
--UIManager:show(touch_menu)
--UIManager:show(keyboard)
UIManager:show(inputtext)

UIManager:run()
