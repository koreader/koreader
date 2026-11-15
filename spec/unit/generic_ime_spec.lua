-- Generic IME engine: numbered candidate window, digit selection, paging,
-- width-adaptive page size and fuzzy pinyin merging (pinyin layout only).
describe("Generic IME engine candidate enhancements", function()
    local IME, code_map, util, wrapMethod
    local PAGE = 9

    setup(function()
        require("commonrequire")
        util = require("util")
        IME = require("ui/data/keyboardlayouts/generic_ime")
        code_map = dofile("frontend/ui/data/keyboardlayouts/zh_pinyin_data.lua")
    end)

    local function utf8_last_len(s)
        local n = #s
        if n == 0 then return 0 end
        local i = n
        while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
        return n - i + 1
    end

    -- stub input box wired like keyboard layouts wrap it
    local function newInputbox(ime, geom)
        local ib = { text = "" }
        function ib:addChars(chars) ib.text = ib.text .. chars end
        function ib:delChar()
            local len = utf8_last_len(ib.text)
            if len > 0 then ib.text = ib.text:sub(1, #ib.text - len) end
        end
        if geom then
            ib.width = geom.width
            ib.face = { size = geom.size }
            ib.margin, ib.bordersize, ib.padding = 0, 0, 0
        end
        util.wrapMethod(ib, "addChars", function(box, char) ime:wrappedAddChars(box, char) end, nil)
        util.wrapMethod(ib, "delChar", function(box) ime:wrappedDelChar(box) end, nil)
        return ib
    end

    local function newIME(opts)
        opts = opts or {}
        return IME:new {
            code_map = opts.code_map or code_map,
            partial_separators = {" "},
            show_candi_callback = function()
                return opts.show_candi ~= false
            end,
            candidate_pages = opts.candidate_pages,
            fuzzy_rules = opts.fuzzy_rules,
            fuzzy_enabled_callback = function()
                return opts.fuzzy ~= false
            end,
            switch_char = "→",
            switch_char_prev = "←",
        }
    end

    local function typeKeys(ib, s)
        for i = 1, #s do ib:addChars(s:sub(i, i)) end
    end

    local function reset(ib, ime)
        ib.text = ""
        ime:clear_stack()
    end

    local function stageOf(ib)
        return ib.text:match("^(.-)%[") or ib.text
    end

    local function textUnits(s)
        local w = 0
        for _, ch in ipairs(util.splitToChars(s)) do
            w = w + (ch:byte(1) >= 0xE0 and 1 or 0.5)
        end
        return w
    end

    local function candiList(code)
        local v = code_map[code]
        if type(v) == "string" then return { v } end
        return v
    end

    local function buildExpected(candi, stage_idx, geom, numbered)
        local out = candi[stage_idx]
        if numbered and #candi > 1 then
            local last = math.min(stage_idx + PAGE - 1, #candi)
            out = out .. "["
            for i = stage_idx + 1, last do
                out = out .. (i - stage_idx + 1) .. candi[i]
            end
            if last < #candi then out = out .. "…" end
            out = out .. "]"
        elseif #candi > 1 then
            out = out .. "["
            local pos = (stage_idx + 1) % #candi
            pos = pos == 0 and #candi or pos
            for i = 1, math.min(#candi - 1, 5) do
                out = out .. candi[pos]
                pos = pos == #candi and 1 or pos + 1
            end
            if #candi > 6 then out = out .. "…" end
            out = out .. "]"
        end
        return out
    end

    describe("stock behavior when candidate_pages is not set", function()
        it("keeps the plain upcoming-candidate hint", function()
            local ime = newIME({})
            local ib = newInputbox(ime)
            typeKeys(ib, "ni")
            assert.equals(buildExpected(candiList("ni"), 1), ib.text)
        end)
        it("cycles the selection with the switch key", function()
            local ime = newIME({})
            local ib = newInputbox(ime)
            typeKeys(ib, "ni")
            ib:addChars("→")
            assert.equals(candiList("ni")[2], stageOf(ib))
        end)
        it("commits digits literally while composing", function()
            local ime = newIME({})
            local ib = newInputbox(ime)
            typeKeys(ib, "ni")
            ib:addChars("2")
            assert.equals(candiList("ni")[1] .. "2", ib.text)
        end)
    end)

    describe("numbered candidate window and digit selection", function()
        local ime, ib, ni
        before_each(function()
            ime = newIME({ candidate_pages = 9 })
            ib = newInputbox(ime)
            ni = candiList("ni")
            typeKeys(ib, "ni")
        end)
        after_each(function()
            reset(ib, ime)
        end)

        it("shows the stage char and the numbered window", function()
            assert.equals(ni[1], ib.text:sub(1, #ni[1]))
            assert.truthy(ib.text:find("2" .. ni[2], 1, true))
            if #ni >= 9 then
                assert.truthy(ib.text:find("9" .. ni[9], 1, true))
            end
        end)
        it("commits the n-th candidate on digit keys", function()
            ib:addChars("3")
            assert.equals(ni[3], ib.text)
            assert.is_false(ime:hasCandidates())
            ib:addChars(" ")
            assert.equals(ni[3] .. " ", ib.text)
        end)
        it("commits a word candidate on digit 1", function()
            reset(ib, ime)
            typeKeys(ib, "zhichi")
            ib:addChars("1")
            assert.equals("支持", ib.text)
        end)
        it("pages by the page size and wraps on both ends", function()
            reset(ib, ime)
            local big_code
            for k, v in pairs(code_map) do
                if type(v) == "table" and #v >= 19 then big_code = k break end
            end
            typeKeys(ib, big_code)
            local big = candiList(big_code)
            ib:addChars("→")
            assert.equals(big[10], stageOf(ib))
            ib:addChars("←")
            assert.equals(big[1], stageOf(ib))
            local last_page_start = #big - ((#big - 1) % PAGE)
            ib:addChars("←")
            assert.equals(big[last_page_start], stageOf(ib))
            ib:addChars("→")
            assert.equals(big[1], stageOf(ib))
        end)
        it("commits space on the page-first candidate", function()
            reset(ib, ime)
            typeKeys(ib, "ni")
            ib:addChars(" ")
            assert.equals(ni[1], ib.text)
        end)
        it("commits a literal digit when no candidate matches", function()
            reset(ib, ime)
            local small_code
            for k, v in pairs(code_map) do
                if type(v) == "table" and #v >= 1 and #v <= 8 then small_code = k break end
            end
            local small = code_map[small_code]
            if type(small) == "string" then small = { small } end
            typeKeys(ib, small_code)
            ib:addChars("9")
            assert.equals(small[1] .. "9", ib.text)
        end)
        it("passes multi-character input through literally", function()
            reset(ib, ime)
            typeKeys(ib, "ni")
            ib:addChars("——")
            assert.equals(ni[1] .. "——", ib.text)
        end)
        it("hides the bracket when show_candi is off, digits still work", function()
            local ime2 = newIME({ candidate_pages = 9, show_candi = false })
            local ib2 = newInputbox(ime2)
            typeKeys(ib2, "ni")
            assert.equals(ni[1], ib2.text)
            ib2:addChars("3")
            assert.equals(ni[3], ib2.text)
        end)
    end)

    describe("width-adaptive page size", function()
        local ime, geom, ib, word_map
        before_each(function()
            word_map = { ni = { "你好", "你好吗", "你们好", "你号", "你", "拟", "腻", "倪", "霓", "呢" } }
            ime = newIME({ candidate_pages = 9, code_map = word_map })
            geom = { width = 200, size = 20 }
            ib = newInputbox(ime, geom)
        end)

        it("caps the window so the stage char stays visible", function()
            typeKeys(ib, "ni")
            assert.equals(word_map.ni[1], ib.text:sub(1, #word_map.ni[1]))
            assert.truthy(ib.text:find("…", 1, true))
            -- only the first extra candidate fits at this width
            assert.truthy(ib.text:find("2" .. word_map.ni[2], 1, true))
            assert.falsy(ib.text:find("3" .. word_map.ni[3], 1, true))
        end)
        it("pages by the visible page size", function()
            typeKeys(ib, "ni")
            ib:addChars("→")
            assert.equals(word_map.ni[3], stageOf(ib))
        end)
        it("commits digits beyond the visible page literally", function()
            typeKeys(ib, "ni")
            ib:addChars("→")
            ib:addChars("9")
            assert.equals(word_map.ni[3] .. "9", ib.text)
        end)
        it("uses the full page on a wide field", function()
            local wide = newInputbox(ime, { width = 2000, size = 20 })
            typeKeys(wide, "ni")
            assert.equals(word_map.ni[1], wide.text:sub(1, #word_map.ni[1]))
            assert.falsy(wide.text:find("…", 1, true))
        end)
    end)

    describe("fuzzy pinyin merging", function()
        local FUZZY = {
            { "zh", "z" }, { "ch", "c" }, { "sh", "s" },
            { "n", "l" }, { "an", "ang" }, { "en", "eng" }, { "in", "ing" },
        }
        local function merged(ime, code)
            return ime:getMergedCandidates(code)
        end

        it("resolves fuzzy codes to their targets first", function()
            local ime = newIME({ candidate_pages = 9, fuzzy_rules = FUZZY })
            assert.equals("支持", merged(ime, "zichi")[1])
        end)
        it("keeps the typed code ahead of variants", function()
            local ime = newIME({ candidate_pages = 9, fuzzy_rules = FUZZY })
            local m = merged(ime, "nan")
            local nan, lan = candiList("nan")[1], candiList("lan")[1]
            local p_nan, p_lan
            for i, v in ipairs(m) do
                if v == nan then p_nan = p_nan or i end
                if v == lan then p_lan = p_lan or i end
            end
            assert.truthy(p_nan and p_lan and p_lan > p_nan)
        end)
        it("merges n->l and an->ang variants", function()
            local ime = newIME({ candidate_pages = 9, fuzzy_rules = FUZZY })
            local m = merged(ime, "nan")
            assert.truthy(#m > #candiList("nan"))
        end)
        it("returns exact candidates only when no fuzzy_rules are set", function()
            local ime = newIME({ candidate_pages = 9 })
            assert.equals(candiList("si")[1], merged(ime, "si")[1])
            assert.equals(#candiList("si"), #merged(ime, "si"))
        end)
    end)
end)
