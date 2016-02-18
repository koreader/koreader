Hacking
=======

Developing UI Widgets
---------------------

If you need to create new UI widgets, `utils/wbuilder.lua` is your friend. It
sets up a minimal environment to bootstrap KOReader's UI framework to avoid
starting the whole reader. This gives you quick feedback loop while iterating
through your widget changes.

To get a taste of how it works, try running this command at the root of
KOReader's source tree:

```
./kodev wbuilder
```

It will spawn up an emulator window with a grid and simple timer widget for
demonstration.

You can add your own `UIManager:show` show call at the end of
`utils/wbuilder.lua` to test your new widget.
