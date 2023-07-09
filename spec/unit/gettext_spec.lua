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
local test_plurals_none = [[
"Plural-Forms: nplurals=1; plural=0;"
]]
local test_plurals_ar = [[
"Plural-Forms: nplurals=6; plural=n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 && n%100<=99 ? 4 : 5;\n"
]]
local test_plurals_ru = [[
"Plural-Forms: nplurals=4; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<12 || n%100>14) ? 1 : n%10==0 || (n%10>=5 && n%10<=9) || (n%100>=11 && n%100<=14)? 2 : 3);\n"
]]
local test_plurals_simple = [[
"Plural-Forms: nplurals=2; plural=(n > 2);\n"
]]
local test_plurals_many = [[
"Plural-Forms: nplurals=5; plural=(n > 3 ? 3 : n > 2 ? 2 : n > 1 ? 1 : 0);"
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
msgstr[3] ""
msgstr[4] ""
msgstr[5] ""

#: frontend/device/android/device.lua:359
msgid "1 untranslated"
msgid_plural "%1 untranslated"
msgstr[0] ""
msgstr[1] ""
msgstr[2] ""
msgstr[3] ""
msgstr[4] ""
msgstr[5] ""

#: frontend/ui/data/css_tweaks.lua:17
msgctxt "Style tweaks category"
msgid "Pages"
msgstr "Pagina's"

#: frontend/ui/data/css_tweaks.lua:20
msgctxt "Other pages"
msgid "Pages"
msgstr "Pages different context"

#: frontend/ui/data/css_tweaks.lua:30
msgctxt "Context 1"
msgid "Page"
msgid_plural "Pages"
msgstr[0] "Pagina"
msgstr[1] "Pagina's"
msgstr[2] "Pagina's plural 2"
msgstr[3] "Pagina's plural 3"
msgstr[4] "Pagina's plural 4"
msgstr[5] "Pagina's plural 5"

#: frontend/ui/data/css_tweaks.lua:40
msgctxt "Context 2"
msgid "Page"
msgid_plural "Pages"
msgstr[0] "Pagina context 2 plural 0"
msgstr[1] "Pagina's context 2 plural 1"
msgstr[2] "Pagina's context 2 plural 2"
msgstr[3] ""
msgstr[4] ""
msgstr[5] ""

#: frontend/ui/data/css_tweaks.lua:50
#, fuzzy
msgid "Fuzzy"
msgstr "Fuzzy translated"
]]

describe("GetText module", function()
    local GetText
    local test_po_ar
    local test_po_nl, test_po_ru
    local test_po_none, test_po_simple
    local test_po_many

    setup(function()
        require("commonrequire")
        GetText = require("gettext")
        GetText.dirname = "i18n-test"

        local lfs = require("libs/libkoreader-lfs")
        lfs.mkdir(GetText.dirname)
        lfs.mkdir(GetText.dirname.."/nl_NL")
        lfs.mkdir(GetText.dirname.."/none")
        lfs.mkdir(GetText.dirname.."/ar")
        lfs.mkdir(GetText.dirname.."/ru")
        lfs.mkdir(GetText.dirname.."/simple")
        lfs.mkdir(GetText.dirname.."/many")

        test_po_nl = GetText.dirname.."/nl_NL/koreader.po"
        local f = io.open(test_po_nl, "w")
        f:write(test_po_part1, test_plurals_nl, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_none = GetText.dirname.."/none/koreader.po"
        f = io.open(test_po_none, "w")
        f:write(test_po_part1, test_plurals_none, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_ar = GetText.dirname.."/ar/koreader.po"
        f = io.open(test_po_ar, "w")
        f:write(test_po_part1, test_plurals_ar, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_ru = GetText.dirname.."/ru/koreader.po"
        f = io.open(test_po_ru, "w")
        f:write(test_po_part1, test_plurals_ru, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_simple = GetText.dirname.."/simple/koreader.po"
        f = io.open(test_po_simple, "w")
        f:write(test_po_part1, test_plurals_simple, test_po_part2)
        f:close()

        -- same file, just different plural for testing
        test_po_many = GetText.dirname.."/many/koreader.po"
        f = io.open(test_po_many, "w")
        f:write(test_po_part1, test_plurals_many, test_po_part2)
        f:close()
    end)

    teardown(function()
        os.remove(test_po_nl)
        os.remove(test_po_none)
        os.remove(test_po_ar)
        os.remove(test_po_ru)
        os.remove(test_po_simple)
        os.remove(test_po_many)
        os.remove(GetText.dirname.."/nl_NL")
        os.remove(GetText.dirname.."/none")
        os.remove(GetText.dirname.."/ar")
        os.remove(GetText.dirname.."/ru")
        os.remove(GetText.dirname.."/simple")
        os.remove(GetText.dirname.."/many")
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
        it("npgettext should return input string", function()
            assert.is_equal("bla", GetText.npgettext("some context", "bla", "blabla", 1))
            assert.is_equal("blabla", GetText.npgettext("some context", "bla", "blabla", 2))
        end)
    end)

    describe("language with standard plurals", function()
        setup(function()
            GetText.changeLang("nl_NL")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
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
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina's", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina's context 2 plural 1", GetText.npgettext("Context 2", "Page", "Pages", 2))
        end)
    end)

    describe("language with simple plurals n > 2", function()
        setup(function()
            GetText.changeLang("simple")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 3))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina's", GetText.npgettext("Context 1", "Page", "Pages", 3))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 2))
            assert.is_equal("Pagina's context 2 plural 1", GetText.npgettext("Context 2", "Page", "Pages", 3))
        end)
    end)

    describe("language with no plurals", function()
        setup(function()
            GetText.changeLang("none")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 3))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 3))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 2))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 3))
        end)
    end)

    describe("language with complex plurals (Arabic)", function()
        setup(function()
            GetText.changeLang("ar")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("%1 dingen 2", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 items", GetText.ngettext("1 item", "%1 items", 5))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 0))
            assert.is_equal("Pagina's", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina's plural 2", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina's plural 3", GetText.npgettext("Context 1", "Page", "Pages", 5))
            assert.is_equal("Pagina's plural 4", GetText.npgettext("Context 1", "Page", "Pages", 99))
            assert.is_equal("Pagina's context 2 plural 1", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina's context 2 plural 2", GetText.npgettext("Context 2", "Page", "Pages", 2))
            assert.is_equal("Pages", GetText.npgettext("Context 2", "Page", "Pages", 5))
        end)
    end)

    describe("language with complex plurals (Russian)", function()
        setup(function()
            GetText.changeLang("ru")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
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
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina's", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina's plural 2", GetText.npgettext("Context 1", "Page", "Pages", 5))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina's context 2 plural 1", GetText.npgettext("Context 2", "Page", "Pages", 2))
            assert.is_equal("Pagina's context 2 plural 2", GetText.npgettext("Context 2", "Page", "Pages", 5))
        end)
    end)

    -- This one's mainly to test fallback stuff. Russian/Polish are hard
    -- to follow, so there we focus on algorithm correctness.
    describe("language with many plurals", function()
        setup(function()
            GetText.changeLang("many")
        end)
        it("gettext should ignore fuzzy strings", function()
            assert.is_equal("Fuzzy", GetText("Fuzzy"))
        end)
        it("gettext should translate multiline string", function()
            assert.is_equal("\nbericht", GetText("\nmessage"))
        end)
        it("ngettext should translate plurals", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 dingen 2", GetText.ngettext("1 item", "%1 items", 3))
        end)
        it("ngettext should fallback to default plural if not yet translated", function()
            assert.is_equal("1 ding", GetText.ngettext("1 item", "%1 items", 1))
            assert.is_equal("%1 dingen", GetText.ngettext("1 item", "%1 items", 2))
            assert.is_equal("%1 dingen 2", GetText.ngettext("1 item", "%1 items", 3))
            assert.is_equal("%1 items", GetText.ngettext("1 item", "%1 items", 4))
            assert.is_equal("%1 items", GetText.ngettext("1 item", "%1 items", 5))
            assert.is_equal("1 untranslated", GetText.ngettext("1 untranslated", "%1 untranslated", 1))
            assert.is_equal("%1 untranslated", GetText.ngettext("1 untranslated", "%1 untranslated", 2))
            assert.is_equal("%1 untranslated", GetText.ngettext("1 untranslated", "%1 untranslated", 3))
            assert.is_equal("%1 untranslated", GetText.ngettext("1 untranslated", "%1 untranslated", 4))
            assert.is_equal("%1 untranslated", GetText.ngettext("1 untranslated", "%1 untranslated", 5))
        end)
        it("pgettext should distinguish context", function()
            assert.is_equal("Pagina's", GetText.pgettext("Style tweaks category", "Pages"))
            assert.is_equal("Pages different context", GetText.pgettext("Other pages", "Pages"))
        end)
        it("npgettext should translate plurals and distinguish context", function()
            assert.is_equal("Pagina", GetText.npgettext("Context 1", "Page", "Pages", 1))
            assert.is_equal("Pagina's", GetText.npgettext("Context 1", "Page", "Pages", 2))
            assert.is_equal("Pagina's plural 3", GetText.npgettext("Context 1", "Page", "Pages", 5))
            assert.is_equal("Pagina context 2 plural 0", GetText.npgettext("Context 2", "Page", "Pages", 1))
            assert.is_equal("Pagina's context 2 plural 1", GetText.npgettext("Context 2", "Page", "Pages", 2))
            assert.is_equal("Pages", GetText.npgettext("Context 2", "Page", "Pages", 5))
        end)
    end)
end)
