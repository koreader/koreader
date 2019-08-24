local test_po_part1 = [[
# KOReader PATH/TO/FILE.PO
# Copyright (C) 2005-2019 KOReader Development Team
#
# Translators:
# Frans de Jonge <fransdejonge@gmail.com>, 2014-2019
# Markismus <zulde.zuldemans@gmail.com>, 2014
msgid ""
msgstr ""
"Project-Id-Version: KOReader\n"
"Report-Msgid-Bugs-To: https://github.com/koreader/koreader-base/issues\n"
"POT-Creation-Date: 2019-08-10 06:01+0000\n"
"PO-Revision-Date: 2019-08-08 06:34+0000\n"
"Last-Translator: Frans de Jonge <fransdejonge@gmail.com>\n"
"Language-Team: Dutch (Netherlands) (http://www.transifex.com/houqp/koreader/language/nl_NL/)\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Language: nl_NL\n"
]]

local test_plurals_nl = [[
"Plural-Forms: nplurals=2; plural=(n != 1);\n"
]]
local test_plurals_ru = [[
"Plural-Forms: nplurals=4; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<12 || n%100>14) ? 1 : n%10==0 || (n%10>=5 && n%10<=9) || (n%100>=11 && n%100<=14)? 2 : 3);\n"
]]

local test_po_part2 = [[

#: frontend/ui/widget/configdialog.lua:1016
msgid ""
"\n"
"message"
msgstr "\nbericht"

#: frontend/device/android/device.lua:259
msgid "1 item"
msgid_plural "%1 items"
msgstr[0] "1 ding"
msgstr[1] "%1 dingen"
msgstr[2] "%1 dingen 2"

#: frontend/ui/data/css_tweaks.lua:17
msgctxt "Style tweaks category"
msgid "Pages"
msgstr "Pagina's"

#: frontend/ui/data/css_tweaks.lua:20
msgctxt "Other pages"
msgid "Pages"
msgstr "Pages different context"
]]

describe("GetText module", function()
    local GetText
    local test_po_nl, test_po_ru

    setup(function()
        require("commonrequire")
        GetText = require("gettext")
        GetText.dirname = "i18n-test"

        local lfs = require("libs/libkoreader-lfs")
        lfs.mkdir(GetText.dirname)
        lfs.mkdir(GetText.dirname.."/nl_NL")
        lfs.mkdir(GetText.dirname.."/ru")

        test_po_nl = GetText.dirname.."/nl_NL/koreader.po"
        local f = io.open(test_po_nl, "w")
        f:write(test_po_part1, test_plurals_nl, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_ru = GetText.dirname.."/ru/koreader.po"
        f = io.open(test_po_ru, "w")
        f:write(test_po_part1, test_plurals_ru, test_po_part2)
        f:close()
    end)

    teardown(function()
        os.remove(test_po_nl)
        os.remove(test_po_ru)
        os.remove(GetText.dirname.."/nl_NL")
        os.remove(GetText.dirname.."/ru")
        os.remove(GetText.dirname)
    end)

    describe("changeLang", function()
        it("should return nil when passing newlang = C", function()
            assert.is_nil(GetText.changeLang("C"))
        end)
        it("should return nil when passing empty string or nil value", function()
            assert.is_nil(GetText.changeLang(nil))
            assert.is_nil(GetText.changeLang(""))
        end)
        it("should return nil when passing values that start with en_US", function()
            assert.is_nil(GetText.changeLang("en_US"))
            assert.is_nil(GetText.changeLang("en_US:en"))
            assert.is_nil(GetText.changeLang("en_US.utf8"))
        end)
        it("should return false when it can't find a po file", function()
            assert.is_false(GetText.changeLang("nonsense"))
            assert.is_false(GetText.changeLang("more_NONSENSE"))
        end)
    end)

    describe("cannot find string", function()
        it("gettext should return input string", function()
            assert.is_equal("bla", GetText("bla"))
        end)
        it("ngettext should return input string", function()
            assert.is_equal("bla", GetText.ngettext("bla", "blabla", 1))
            assert.is_equal("blabla", GetText.ngettext("bla", "blabla", 2))
        end)
        it("pgettext should return input string", function()
            assert.is_equal("bla", GetText.pgettext("some context", "bla"))
        end)
    end)

    describe("language with standard plurals", function()
        GetText.changeLang("nl_NL")
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 5))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
    end)

    describe("language with complex plurals", function()
        GetText.changeLang("ru")
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 dingen 2", GetText.ngettext("1 item", "%1 items", 5))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
    end)
end)
