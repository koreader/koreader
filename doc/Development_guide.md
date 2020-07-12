# Development Guide

The whole frontend part of KOReader is scripted in [Lua](http://www.lua.org/about.html) programming language which means you can start development with just a decent text editor. Instructions about how to get and compile the source of the backend part on a linux OS are [here](https://github.com/koreader/koreader#building-prerequisites)

The source tree of frontend looks like this:
```
frontend
├── apps
│   ├── filemanager
│   │   ├── filemanagerhistory.lua
│   │   ├── filemanager.lua
│   │   └── filemanagermenu.lua
│   └── reader *
│       ├── modules
│       │   ├── readeractivityindicator.lua
│       │   ├── readerbookmark.lua
│       │   ├── readerconfig.lua
│       │   ├── readercoptlistener.lua
│       │   ├── readercropping.lua
│       │   ├── readerdictionary.lua
│       │   ├── readerdogear.lua
│       │   ├── readerflipping.lua
│       │   ├── readerfont.lua
│       │   ├── readerfooter.lua
│       │   ├── readergoto.lua
│       │   ├── readerhighlight.lua
│       │   ├── readerhinting.lua
│       │   ├── readerhyphenation.lua
│       │   ├── readerkoptlistener.lua
│       │   ├── readerlink.lua
│       │   ├── readermenu.lua
│       │   ├── readerpaging.lua
│       │   ├── readerpanning.lua
│       │   ├── readerrolling.lua
│       │   ├── readerrotation.lua
│       │   ├── readerscreenshot.lua
│       │   ├── readertoc.lua
│       │   ├── readertypeset.lua
│       │   ├── readerview.lua
│       │   └── readerzooming.lua
│       ├── pluginloader.lua
│       └── readerui.lua
├── cacheitem.lua
├── cache.lua
├── configurable.lua
├── dbg.lua
├── docsettings.lua
├── document *
│   ├── credocument.lua
│   ├── djvudocument.lua
│   ├── document.lua
│   ├── documentregistry.lua
│   ├── koptinterface.lua
│   ├── pdfdocument.lua
│   ├── picdocument.lua
│   └── tilecacheitem.lua
├── gettext.lua
├── JSON.lua
├── optmath.lua
└── ui
    ├── data
    │   ├── creoptions.lua
    │   ├── koptoptions.lua
    │   └── strings.lua
    ├── device
    │   ├── basepowerd.lua
    │   ├── kindlepowerd.lua
    │   ├── kobopowerd.lua
    │   └── screen.lua
    ├── device.lua
    ├── event.lua
    ├── font.lua
    ├── geometry.lua
    ├── gesturedetector.lua
    ├── gesturerange.lua
    ├── input.lua
    ├── language.lua
    ├── rendertext.lua
    ├── screen.lua
    ├── timeval.lua
    ├── uimanager.lua
    └── widget *
        ├── bboxwidget.lua
        ├── buttondialog.lua
        ├── button.lua
        ├── buttontable.lua
        ├── closebutton.lua
        ├── configdialog.lua
        ├── confirmbox.lua
        ├── container
        │   ├── bottomcontainer.lua
        │   ├── centercontainer.lua
        │   ├── framecontainer.lua
        │   ├── inputcontainer.lua
        │   ├── leftcontainer.lua
        │   ├── rightcontainer.lua
        │   ├── underlinecontainer.lua
        │   └── widgetcontainer.lua
        ├── dictquicklookup.lua
        ├── eventlistener.lua
        ├── filechooser.lua
        ├── fixedtextwidget.lua
        ├── focusmanager.lua
        ├── horizontalgroup.lua
        ├── horizontalspan.lua
        ├── iconbutton.lua
        ├── imagewidget.lua
        ├── infomessage.lua
        ├── inputdialog.lua
        ├── inputtext.lua
        ├── linewidget.lua
        ├── menu.lua
        ├── notification.lua
        ├── overlapgroup.lua
        ├── progresswidget.lua
        ├── rectspan.lua
        ├── scrolltextwidget.lua
        ├── textboxwidget.lua
        ├── textwidget.lua
        ├── toggleswitch.lua
        ├── touchmenu.lua
        ├── verticalgroup.lua
        ├── verticalscrollbar.lua
        ├── verticalspan.lua
        ├── virtualkeyboard.lua
        └── widget.lua
```
in which you will find the asterisked `frontend/document`, `frontend/apps/reader` and `frontend/ui/widget` the most interesting parts.

### document: API for document parsing and rendering

### reader: reader functionality implementation

### widget: a light-weight widget toolkit
