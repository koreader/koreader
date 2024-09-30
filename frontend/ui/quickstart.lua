--[[--This module is responsible for generating the quickstart guide.
]]
local DataStorage = require("datastorage")
local Device = require("device")
local FileConverter = require("apps/filemanager/filemanagerconverter")
local DocSettings = require("docsettings")
local Language = require("ui/language")
local Version = require("version")
local FFIUtil = require("ffi/util")
local T = FFIUtil.template
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local QuickStart = {
    quickstart_force_show_version = 2021070000,
}

local language = G_reader_settings:readSetting("language") or "en"
local version = Version:getNormalizedCurrentVersion()
local rev = Version:getCurrentRevision()

local stylesheet = [[
div.logo { float: right; }
div.logo > img { height: 4em; }
h1 { page-break-before: avoid; margin-bottom: 1em; text-transform: uppercase; }
h2 { background-color: black; color: white; text-align: center; page-break-after: avoid; text-transform: uppercase; }

hr { margin: 1em 20%; }
div.generated { font-size: x-small; }

li { margin: 0.5em 0; page-break-inside: avoid; }
blockquote { text-align: center; page-break-before: avoid; page-break-inside: avoid; } /* Markdown lines starting with '>' */

/* Inline image (icons) */
p img, blockquote img { height: 1.5em; vertical-align: bottom; }

/* Standalone image (UI screenshots) */
div.img-block { text-align: center; margin: 0.5em; }
div.img-block > img { max-height: 60vh; max-width: 80vw; }
div.break-before-avoid { page-break-before: avoid; }
div.break-after-avoid { page-break-after: avoid; }

div.table { display: table; page-break-inside: avoid; width: 100%; }
div.table > div { display: table-row; }
div.table > div > * { display: table-cell; text-indent: 0; padding: 0.3em; }
div.table > div > *:nth-child(2) { text-align: left; hyphens: none; background-color: #eeeeee; }
div.table > div > *:nth-child(3) { white-space: nowrap; }
]]

local quickstart_guide = {}
if Device:hasScreenKB() or Device:hasSymKey() then
    -- On Non-Touch kindle, not showing "Frontlight", showing specific section "Shortcuts"
    table.insert(quickstart_guide, _([[
<div class="logo">![KOReader](resources/koreader.svg)</div>

# Quickstart guide

* [User interface](#ui)
* [User interface tips](#uitips)
* [Accessing files](#afiles)
* [Transferring files](#tfiles)
* [Shortcuts](#short)
* [While reading](#reading)
* [Installing dictionaries](#dicts)
* [More info](#more)

---
You can access the complete user manual from [our GitHub page](https://github.com/koreader/koreader).
]])
    ) --insert toc
else
    table.insert(quickstart_guide, _([[
<div class="logo">![KOReader](resources/koreader.svg)</div>

# Quickstart guide

* [User interface](#ui)
* [User interface tips](#uitips)
* [Accessing files](#afiles)
* [Transferring files](#tfiles)
* [Frontlight/backlight](#flight)
* [While reading](#reading)
* [Installing dictionaries](#dicts)
* [More info](#more)

---
You can access the complete user manual from [our GitHub page](https://github.com/koreader/koreader).
]])
    ) -- insert toc
end

-- User interface
if Device:hasScreenKB() then
    -- Use correct k4 illustration and appropriate button mapping
    table.insert(quickstart_guide, _([[## User interface <a id="ui"></a>

<div class="img-block">![Touch zones](resources/quickstart/kindle4.png)</div>

- To show the **TOP MENU** or **BOTTOM MENU** press the **Menu** or **Press** keys respectively.
- The **STATUS BAR** can be set to show a multitude of information regarding your reading progress or device state.
]])
    ) -- inset user interface
elseif Device:hasSymKey() then
    -- Use correct k3 illustration and appropriate button mapping
    table.insert(quickstart_guide, _([[## User interface <a id="ui"></a>

<div class="img-block">![Touch zones](resources/quickstart/kindle3.png)</div>

- To show the **TOP MENU** or **BOTTOM MENU** press the **Menu** or **Aa** keys respectively.
- The **STATUS BAR** can be set to show a multitude of information regarding your reading progress or device state.
]])
    ) -- insert user interface
else
    table.insert(quickstart_guide, _([[## User interface <a id="ui"></a>

<div class="img-block">![Touch zones](resources/quickstart/touchzones.png)</div>

- To show the **TOP MENU** or **BOTTOM MENU** you can click the indicated zones. You can click or swipe down the upper zone to show the **TOP MENU**.
- The **STATUS BAR** zone can be used to cycle between STATUS BAR items if one item is visible. This will also hide and show the STATUS BAR if you tap enough times.
]])
    ) -- insert user interface
end

-- User interface tips
if Device:hasScreenKB() then
    table.insert(quickstart_guide, _([[## User interface tips <a id="uitips"></a>

- You can change the interface language using:

> **Menu ➔ ![Settings](resources/icons/mdlight/appbar.settings.svg) ➔ Language**

- If you press both **ScreenKB** + **Press** on an option or menu item (font weight, line spacing etc.), you can set its value as **DEFAULT**.  The new value will only be applied to documents opened from now on. Previously opened documents will keep their settings. You can identify default values as a STAR in menu or as a black border around indicators as seen below:

<div class="img-block break-before-avoid">![Default setting 1](resources/quickstart/defaultsetting1.png)</div>
<div class="img-block break-before-avoid">![Default setting 2](resources/quickstart/defaultsetting2.png)</div>

- You can see explanations for some items on the **TOP MENU** by pressing both **ScreenKB** + **Press** on the name of the option.
- You can **CLOSE** full screen dialogs (History, Table of Contents, Bookmarks, Reading Statistics etc.) by pressing the **Back** key.
- **SCREENSHOTS** can be taken by pressing the **ScreenKB** + **Menu** keys

<div class="img-block break-after-avoid">![Number picker](resources/quickstart/numberpicker.png)</div>

- In dialogs containing adjustment arrow buttons like the one above, you can use the directional keys to move around. If widgets have menus, pressing the **Menu** key should open them.
- You can toggle content selection mode by pressing either the **Up** or **Down** keys. The selection tool becomes available so you can select one or multiple words, for either dictionary, wikipedia or text look ups.
- You can highlight blocks of text by selecting multiple words with the content selection tool.
- You can move through your document with the **Left** or **Right** cursor keys which, should take you to the previous or next chapter respectively.
- The content selection tool's sensitivity can be adjusted in the **TOP MENU**.

> **Menu ➔ ![Typesettings](resources/icons/mdlight/appbar.typeset.svg) ➔ Selection on text**
]])
    ) -- insert UI tips
elseif Device:hasSymKey() then
    table.insert(quickstart_guide, _([[## User interface tips <a id="uitips"></a>

- You can change the interface language using:

> **Menu ➔ ![Settings](resources/icons/mdlight/appbar.settings.svg) ➔ Language**

- If you press both **Shift** + **Press** on an option or menu item (font weight, line spacing etc.), you can set its value as **DEFAULT**.  The new value will only be applied to documents opened from now on. Previously opened documents will keep their settings. You can identify default values as a STAR in menu or as a black border around indicators as seen below:

<div class="img-block break-before-avoid">![Default setting 1](resources/quickstart/defaultsetting1.png)</div>
<div class="img-block break-before-avoid">![Default setting 2](resources/quickstart/defaultsetting2.png)</div>

- You can see explanations for some items on the **TOP MENU** by pressing both **Shift** + **Press** on the name of the option.
- You can **CLOSE** full screen dialogs (History, Table of Contents, Bookmarks, Reading Statistics etc.) by pressing the **Back** key.
- **SCREENSHOTS** can be taken by pressing the **Alt** + **Shift** + **G** keys

<div class="img-block break-after-avoid">![Number picker](resources/quickstart/numberpicker.png)</div>

- In dialogs containing adjustment arrow buttons like the one above, you can use the directional keys to move around. If widgets have menus, pressing the **Menu** key should open them.
- You can toggle content selection mode by pressing either the **Up** or **Down** keys. The selection tool becomes available so you can select one or multiple words, for either dictionary, wikipedia or text look ups.
- You can highlight blocks of text by selecting multiple words with the content selection tool.
- You can move through your document with the **Left** or **Right** cursor keys which, should take you to the previous or next chapter respectively.
- The content selection tool's sensitivity can be adjusted in the **TOP MENU**.

> **Menu ➔ ![Typesettings](resources/icons/mdlight/appbar.typeset.svg) ➔ Selection on text**
]])
    ) -- insert UI tips
else
    table.insert(quickstart_guide, _([[## User interface tips <a id="uitips"></a>

- You can change the interface language using:

> **TOP MENU ➔ ![Settings](resources/icons/mdlight/appbar.settings.svg) ➔ Language**

- If you tap and hold on an option or menu item (font weight, line spacing etc.), you can set its value as **DEFAULT**.  The new value will only be applied to documents opened from now on. Previously opened documents will keep their settings. You can identify default values as a STAR in menu or as a black border around indicators as seen below:

<div class="img-block break-before-avoid">![Default setting 1](resources/quickstart/defaultsetting1.png)</div>
<div class="img-block break-before-avoid">![Default setting 2](resources/quickstart/defaultsetting2.png)</div>

- You can see explanations for all items on the **BOTTOM MENU** by tapping and holding the name of the option. This is also available for most of the **TOP MENU** menu items.
- You can **CLOSE** full screen dialogs (History, Table of Contents, Bookmarks, Reading Statistics etc.) by swiping down
- **SCREENSHOTS** can be taken by touching opposing corners of the screen diagonally at the same time or by making a long diagonal swipe

<div class="img-block break-after-avoid">![Number picker](resources/quickstart/numberpicker.png)</div>

- In dialogs containing adjustment arrow buttons like the one above, you can tap and hold on arrow buttons to increase / decrease the value in bigger increments
- You can **CLOSE** this type of dialog (non-full screen) by tapping outside of the window. You can **MOVE** this type of dialog by holding the window title and dragging
- You can make this type of dialog **SEMI-TRANSPARENT** (to see the text under it while adjusting a value) by tapping and holding the window title
- Tapping and holding a word brings up a dialog which allows you to search for the selection to find more occurrences in the document or to look it up on Wikipedia
- You can highlight sections by tapping and holding a word and dragging your finger
- You can move through your document via the **SKIM DOCUMENT** dialog:

> **TOP MENU ➔ ![Navigation](resources/icons/mdlight/appbar.navigation.svg) ➔ Skim document**
]])
    ) -- insert UI tips
end

-- Accessing files
if Device:hasScreenKB() or Device:hasSymKey() then
    -- This NT version removes mentions of gestures
    table.insert(quickstart_guide, _([[## Accessing files <a id="afiles"></a>

The following methods are available for accessing your books and articles:

* File Browser
* Favorites
* History

You can also set KOReader to open with any of these dialogs on startup via:

> **Menu (in File Browser) ➔ ![Filebrowser](resources/icons/mdlight/appbar.filebrowser.svg) ➔ Start with**
]])
    ) -- insert Accessing files
else
    table.insert(quickstart_guide, _([[## Accessing files <a id="afiles"></a>

The following methods are available for accessing your books and articles:

* File Browser
* Favorites
* History

You can assign gestures for quick access to each of these dialogs.

You can also set KOReader to open with any of these dialogs on startup via:

> **TOP MENU (in File Browser) ➔ ![Filebrowser](resources/icons/mdlight/appbar.filebrowser.svg) ➔ Start with**
]])
    ) -- insert accessing files
end

-- Transferring files
table.insert(quickstart_guide, _([[## Transferring files <a id="tfiles"></a>

In addition to transferring files the same way you would with the built-in reader application, other options are available depending on your device:

1. USB Mass Storage mode within KOReader
2. Cloud storage (Dropbox/FTP/Webdav)
3. SSH/SFTP access
4. Calibre transfer
5. News downloader
6. Wallabag
]])
) -- insert

-- Frontlight (shortcuts on NT)
if Device:hasScreenKB() then
    table.insert(quickstart_guide, _([[## Shortcuts <a id="short"></a>

The following is a non-exhaustive list of shortcuts available.

When inside the reading module:

- **ScreenKB** + **Up**: Table of contents
- **ScreenKB** + **Right**: Add a bookmark
- **ScreenKB** + **Down**: Book map
- **ScreenKB** + **Left**: Bookmarks, notes and highlights
- **ScreenKB** + **Press**: Save current page to location history
- **ScreenKB** + **Home**: Toggle wifi on/off
- **ScreenKB** + **Back**: Switch to previously opened book

When using a virtual keyboard:

- **ScreenKB** + **Right**: Move cursor to right char
- **ScreenKB** + **Left**: Move cursor to left char
- **ScreenKB** + **Press**: Show special characters behind virtual keyboard keys
- **ScreenKB** + **Home**: Toggle virtual keyboard on/off
- **ScreenKB** + **Back**: Delete char
]])
    ) -- insert shortcuts
elseif Device:hasSymKey() then
    table.insert(quickstart_guide, _([[## Shortcuts <a id="short"></a>

The following is a non-exhaustive list of shortcuts available.

When inside the reading module:

- **T** or **Shift** + **Up**: Table of contents
- **Shift** + **Right**: Add a bookmark
- **Shift** + **Down**: Book map
- **B** or **Shift** + **Left**: Bookmarks, notes and highlights
- **Shift** + **Press**: Save current page to location history
- **Shift** + **Home**: Toggle wifi on/off
- **Shift** + **Back**: Switch to previously opened book

When using a virtual keyboard:

- **Shift** + **Right**: Move cursor to right char
- **Shift** + **Left**: Move cursor to left char
- **Shift** + **Press**: Show special characters behind virtual keyboard keys
- **Shift** + **Home**: Toggle virtual keyboard on/off
- **Shift** + **Del**: Delete word
- **Shift** + **Back**: Delete whole line
- **Sym** + **Alphabet keys**: symbols, numbers and special characters
]])
    ) -- insert shortcuts
else
    table.insert(quickstart_guide, _([[## Frontlight/backlight <a id="flight"></a>

You can control your screen light via this menu. If you have warm lighting (normal white LEDs+orange ones) you can control them separately from this dialog:

> **TOP MENU ➔ ![Settings](resources/icons/mdlight/appbar.settings.svg) ➔ Frontlight**
]])
    ) -- insert frontlight
end

-- While reading
table.insert(quickstart_guide, _([[## While reading <a id="reading"></a>

<div class="table"><div>

You can change the font

**TOP MENU ➔ ![Typesettings](resources/icons/mdlight/appbar.typeset.svg) ➔ Font**

</div><div>

Make font bigger

**BOTTOM MENU ➔ ![Textsize](resources/icons/mdlight/appbar.textsize.svg)**

</div><div>

Make font bolder

**BOTTOM MENU ➔ ![Contrast](resources/icons/mdlight/appbar.contrast.svg)**

</div><div>

Invert the colors (white text on black)

**TOP MENU ➔ ![Settings](resources/icons/mdlight/appbar.settings.svg) ➔ Night mode**

</div><div>

Change many formatting options

**TOP MENU ➔ ![Typesettings](resources/icons/mdlight/appbar.typeset.svg) ➔ Style tweaks**

</div></div>
]])
) -- insert while reading

-- Dictionaries
table.insert(quickstart_guide, _([[## Installing dictionaries <a id="dicts"></a>

KOReader supports dictionary lookup in EPUB and even in scanned PDF/DJVU documents. To see the dictionary definition or translation, tap and hold a word.

To use the dictionary lookup function, first you need to install one or more dictionaries in the StarDict format. KOReader has an inbuilt dictionary installation system:

**TOP MENU ➔ ![Search](resources/icons/mdlight/appbar.search.svg) ➔ Dictionary Settings > Download dictionaries**
]])
) -- insert dictionaries

-- More information
table.insert(quickstart_guide, T(_([[## More info <a id="more"></a>

You can find more information on our GitHub page

[https://github.com/koreader/koreader](https://github.com/koreader/koreader)

You can find other KOReader users on MobileRead forums

[https://www.mobileread.com/forums/forumdisplay.php?f=276](https://www.mobileread.com/forums/forumdisplay.php?f=276)

---
<div class="generated">Generated by KOReader %1.</div>
]]),
    rev)
) -- insert more information

quickstart_guide = table.concat(quickstart_guide, "\n")

--[[-- Returns `true` if shown, `false` if the quickstart guide hasn't been
shown yet or if display is forced through a higher version number than when
it was first shown.
]]
function QuickStart:isShown()
    local shown_version = G_reader_settings:readSetting("quickstart_shown_version")
    return shown_version ~= nil and (shown_version >= self.quickstart_force_show_version)
end

--[[-- Generates the quickstart guide in the user's language and returns its location.

The fileformat is `quickstart-en-v2015.11-985-g88308992.html`, `en` being the
language of the generated file and `v2015.11-985-g88308992` the KOReader version
used to generate the file.

@treturn string path to generated HTML quickstart guide
]]
function QuickStart:getQuickStart()
    local quickstart_dir = ("%s/help"):format(DataStorage:getDataDir())
    if lfs.attributes(quickstart_dir, "mode") ~= "dir" then
        lfs.mkdir(quickstart_dir)
    end

    local quickstart_filename = ("%s/quickstart-%s-%s.html"):format(quickstart_dir, language, rev)
    if lfs.attributes(quickstart_filename, "mode") ~= "file" then
        -- purge old quickstart guides
        local iter, dir_obj = lfs.dir(quickstart_dir)
        for f in iter, dir_obj do
            if f:match("quickstart-.*%.html") then
                local file_abs_path = FFIUtil.realpath(("%s/%s"):format(quickstart_dir, f))
                os.remove(file_abs_path)
                DocSettings:open(file_abs_path):purge()
            end
        end

        local quickstart_html = FileConverter:mdToHtml(quickstart_guide, _("KOReader Quickstart Guide"), stylesheet)
        if quickstart_html then
            -- Fix links to images, which are in KOReader install directory, which may not
            -- be alongside help/ on some platforms like Android.
            -- crengine won't accept full paths, so we need to make these relative
            local src = FFIUtil.realpath(quickstart_dir) .. "/"
            local dst = lfs.currentdir() .. "/"
            -- Find the common leading directories
            local idx = 0
            while true do
                local tst = src:find("/", idx + 1, true)
                if tst and src:sub(1,tst) == dst:sub(1,tst) then
                    idx = tst
                else
                    break
                end
            end
            -- Trim off the common directories from the front
            src = src:sub(idx + 1)
            dst = dst:sub(idx + 1)
            -- Back up from dst to get to this common parent
            local relpath = ""
            idx = src:find("/")
            while idx do
                relpath = relpath .. "../"
                idx = src:find("/", idx + 1)
            end
            -- Add the path down to dst from here
            relpath = relpath .. dst
            relpath = relpath:gsub("//", "/") -- make it prettier
            quickstart_html = quickstart_html:gsub([[src="resources/]], [[src="]]..relpath..[[resources/]])
            if Language:isLanguageRTL(language) then
                quickstart_html = quickstart_html:gsub('<html>', '<html dir="rtl">')
            end
            -- Write the fixed HTML content
            util.writeToFile(quickstart_html, quickstart_filename)
        end
    end
    -- remember filename for file manager
    self.quickstart_filename = quickstart_filename
    G_reader_settings:saveSetting("quickstart_shown_version", version)
    return quickstart_filename
end

return QuickStart
