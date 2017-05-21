Hacking
=======

## How to Debug

We have a helper function called `logger.dbg` to help with debugging. You can use that function to print string and tables:

```lua
local logger = require("logger")
a = {"1", "2", "3"}
logger.dbg("table a: ", a)
```

Anything printed by `logger.dbg` starts with `DEBUG`.

```
04/06/17-21:44:53 DEBUG foo
```

## Bug hunting in kpv

A real example of bug hunting in KPV's cache system: <https://github.com/koreader/kindlepdfviewer/pull/475>


## Developing UI widgets ##

`tools/wbuilder.lua` is your friend, if you need to create new UI widgets. It
sets up a minimal environment to bootstrap KOReader's UI framework to avoid
starting the whole reader. This gives you quick feedback loop while iterating
through your widget changes. It's also a handy tool for debugging widget
issues.

To get a taste of how it works, try running this command at the root of
KOReader's source tree:

```
./kodev wbuilder
```

It will spawn up an emulator window with a grid and simple timer widget for
demonstration.

You can add more `UIManager:show` call at the end of `tools/wbuilder.lua` to
test your new widgets.
