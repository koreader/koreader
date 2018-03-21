describe("FocusManager module", function()
    local FocusManager
    local layout
    local Up,Down,Left,Right
    Up = function(self) self:onFocusMove({0, -1}) end
    Down = function(self) self:onFocusMove({0, 1}) end
    Left = function(self) self:onFocusMove({-1, 0}) end
    Right = function(self) self:onFocusMove({1, 0}) end
    setup(function()
        require("commonrequire")
        FocusManager = require("ui/widget/focusmanager")
        local Widget = require("ui/widget/textwidget")
        local w = Widget:new{}
        layout= {
                {w,  w,  w},
                {nil,w,nil},
                {nil,w,nil},
                }

    end)
    it("should go right", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Right(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should go left", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 2}
        Left(focusmanager)
        assert.are.same({y = 1,x = 1}, focusmanager.selected)
    end)
    it("should go up", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Up(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should go down", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Down(focusmanager)
        assert.are.same({y = 3,x = 2}, focusmanager.selected)
    end)
    it("should vertical wrapAround up", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Up(focusmanager)
        assert.are.same({y = 3,x = 2}, focusmanager.selected)
    end)
    it("should vertical wrapAround down", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 3,x = 2}
        Down(focusmanager)
        assert.are.same({y = 1,x = 2}, focusmanager.selected)
    end)
    it("should do vertical step to the right", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 1}
        Down(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should do vertical step to the left", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 1,x = 3}
        Down(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should respect left limit", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Left(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
    it("should respect right limit", function()
        local focusmanager = FocusManager:new{}
        focusmanager.layout = layout
        focusmanager.selected = {y = 2,x = 2}
        Right(focusmanager)
        assert.are.same({y = 2,x = 2}, focusmanager.selected)
    end)
end)
