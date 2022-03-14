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

On most target platforms, log output is saved to `crash.log` in the `koreader` directory.

```
04/06/17-21:44:53 DEBUG foo
```

In production code, remember that arguments are *always* evaluated in Lua, so,
don't inline complex computations in logger functions' arguments.
If you *really* have to, hide the whole thing behind a `dbg.is_on` branch,
like in [frontend/device/input.lua](https://github.com/koreader/koreader/blob/ba6fef4d7ba217ca558072f090849000e72ba142/frontend/device/input.lua#L1131-L1134).

## Bug hunting in KPV (KOReader's predecessor)

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
