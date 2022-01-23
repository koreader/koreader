Events
======

## Overview ##

All widgets are a subclass of @{ui.widget.eventlistener}, therefore they inherit
the @{ui.widget.eventlistener:handleEvent|handleEvent} method. To send an event
to a widget, you can simply invoke the handleEvent method like the following:

```lua
widget_foo:handleEvent(Event:new("Timeout"))
```
If the widget can be destroyed during the event you should call @{ui.uimanager:sendEvent|UIManager:sendEvent} to propagate the event from the topmost widget or @{ui.uimanager:broadcastEvent|UIManager:broadcastEvent} to send the event to all widgets.

Events are passed to child Widgets (or child containers) before their own handler sees them. See the implementation of WidgetContainer:handleEvent(). So a child widget, for instance a text input widget, gets the input events before the layout manager. The child widgets can "consume" an event by returning `true` from the event handler. Thus a text input widget just implements an input handler and consumes left/right presses, returning `true` in those cases. It can even make its return code dependent on whether the cursor is on the last position (do not consume press to right) or first position (do not consume press to left) to have proper focus movement in those cases.

## Builtin events ##

### Reader events ###

* UpdatePos: emitted by typesetting related modules to notify other modules to
recalculate the view based on the new typesetting.

* PosUpdate: emitted by readerrolling module to signal a change in pos.


## Event propagation ##

Most UI components are a subclass of @{ui.widget.container.widgetcontainer|WidgetContainer}.
A WidgetContainer is an array that stores a list of children widgets.

When @{ui.widget.container.widgetcontainer:handleEvent|WidgetContainer:handleEvent} is called with a new event,
it will run roughly the following code:

```lua
-- First propagate event to its children
for _, widget in ipairs(self) do
    if widget:handleEvent(event) then
        -- stop propagating when an event handler returns true
        return true
    end
end
-- If not consumed by children, consume it ourself
return self["on"..event.name](self, unpack(event.args, 1, event.argc))
```

## Event system
The @{ui.event|Event} system is used by widgets to communicate.

Each event is an object that has two properties: `args` and `handler`. `handler` is the name of function that will be called on receive. `args` is a table that contains all the arguments needed to be passed to the event handler. When a widget receives a event, it will first check to see if `self[event.handler]` exists. If yes, the `self[event.handler]` function will be called and the return value of the handler will be returned to UIManager.

Notice that if you don't want the event propagate after consumed in your handler, your handler must return `true`. Otherwise, the event will be passed to other widgets' handlers until one of the handlers returns `true`.

@{ui.widget.container.widgetcontainer|WidgetContainer} is a special kind of widget. When it receives an event, it will first propagate the event to all its children. If the event is still not consumed (i.e., its handler returns `true`), then it will try to handle the event by itself.

When you call @{ui.uimanager.show|UIManager:show} on a widget, this widget will be added to the top of the `UIManager._window_stack`.
Events are sent to the first widget in `UIManager._window_stack`. If it is not consumed, then UIManager will try to send it to all active widgets (`widget.is_always_active` equals `true`) in the `_window_stack`.

## Draw Page Code Path

* **in readerview.lua:** ReaderView widget flag itself dirty in `ReaderView:recalculate`
* **in ui.lua:** UI main loop calls `ReaderView:paintTo`
* **in readerview.lua:** `ReaderView:paintTo` calls `document:drawPage`
* **in document.lua:** `document:drawPage` check for cache, if found, **return cache**
* **in document.lua:** if cache not found, `document:drawPage` calls `document:renderPage`
* **in document.lua:** `document:renderPage` calls `_document:openPage`, `page:draw` and put the result into cache
