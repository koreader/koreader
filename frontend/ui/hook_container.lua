--[[--
HookContainer allows listeners to register and unregister a hook for speakers to execute.

It's an experimental feature: use with cautions, it can easily pin an object in memory and unblock
GC from recycling the memory.
]]

local HookContainer = {}

function HookContainer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function HookContainer:_assertIsValidName(name)
    assert(type(name) == "string")
    assert(string.len(name) > 0)
end

function HookContainer:_assertIsValidFunction(func)
    assert(type(func) == "function" or type(func) == "table")
end

function HookContainer:_assertIsValidFunctionOrNil(func)
    if func == nil then return end
    self:_assertIsValidFunction(func)
end

--- Register a function to name. Must be called with self.
-- @tparam string name The name of the hook. Can only be an non-empty string.
-- @tparam function func The function to handle the hook. Can only be a function.
function HookContainer:register(name, func)
    self:_assertIsValidName(name)
    self:_assertIsValidFunction(func)
    if self[name] == nil then
        self[name] = {}
    end
    table.insert(self[name], func)
end

--- Register a widget to name. Must be called with self.
-- @tparam string name The name of the hook. Can only be an non-empty string.
-- @tparam table widget The widget to handle the hook. Can only be a table with required functions.
function HookContainer:registerWidget(name, widget)
    self:_assertIsValidName(name)
    assert(type(widget) == "table")
    -- *That* is the function we actually register and need to unregister later, so keep a ref to it...
    local hook_func = function(args)
        local f = widget["on" .. name]
        self:_assertIsValidFunction(f)
        f(widget, args)
    end
    self:register(name, hook_func)
    local original_close_widget = widget.onCloseWidget
    self:_assertIsValidFunctionOrNil(original_close_widget)
    widget.onCloseWidget = function()
        if original_close_widget then original_close_widget(widget) end
        self:unregister(name, hook_func)
    end
end

--- Unregister a function from name. Must be called with self.
-- @tparam string name The name of the hook. Can only be an non-empty string.
-- @tparam function func The function to handle the hook. Can only be a function.
-- @treturn boolean Return true if the function is found and removed, otherwise false.
function HookContainer:unregister(name, func)
    self:_assertIsValidName(name)
    self:_assertIsValidFunction(func)
    if self[name] == nil then
        return false
    end

    for i, f in ipairs(self[name]) do
        if f == func then
            table.remove(self[name], i)
            return true
        end
    end
    return false
end

--- Execute all registered functions of name. Must be called with self.
-- @tparam string name The name of the hook. Can only be an non-empty string.
-- @param args Any kind of arguments sending to the functions.
-- @treturn number The number of functions have been executed.
function HookContainer:execute(name, args)
    self:_assertIsValidName(name)
    if self[name] == nil or #self[name] == 0 then
        return 0
    end

    for _, f in ipairs(self[name]) do
        f(args)
    end
    return #self[name]
end

return HookContainer
