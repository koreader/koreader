Events
======

## Overview ##

All widgets is a subclass of @{ui.widget.eventlistener}, therefore inherit
the @{ui.widget.eventlistener:handleEvent|handleEvent} method. To send an event
to a widget, you can simply invoke the handleEvent method like the following:

```lua
widget_foo:handleEvent(Event:new("Timeout"))
```


## Builtin events ##

### Reader events ###

* UpdatePos: emitted by typesetting related modules to notify other modules to
recalculate the view based on the new typesetting.

* PosUpdate: emitted by readerrolling module to signal a change in pos.


## Event propagation ##

Most of the UI components is a subclass of
@{ui.widget.container.widgetcontainer|WidgetContainer}. A WidgetContainer is an array that
stores a list of children widgets.

When @{ui.widget.container.widgetcontainer:handleEvent|WidgetContainer:handleEvent} is called with a new
event, it will run roughly the following code:

```lua
-- First propagate event to its children
for _, widget in ipairs(self) do
    if widget:handleEvent(event) then
        -- stop propagating when an event handler returns true
        return true
    end
end
-- If not consumed by children, try consume by itself
return self["on"..event.name](self, unpack(event.args))
```

