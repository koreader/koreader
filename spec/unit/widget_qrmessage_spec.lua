describe("QRMessage.splitText", function()
    local QRMessage, QRWidget, qrencode

    -- floor((MAX_BYTES - PREFIX_RESERVE) * 0.85) = floor((2953 - 15) * 0.85)
    -- (DENSITY_THRESHOLD in qrmessage.lua). Pinned here on purpose: if the
    -- constants change, this should be a conscious decision.
    local LIMIT = 2497
    local PREFIX_RESERVE = 15

    setup(function()
        require("commonrequire")
        QRMessage = require("ui/widget/qrmessage")
        QRWidget = require("ui/widget/qrwidget")
        qrencode = require("ffi/qrencode")
    end)

    -- Splits "(i/n) payload" into i, n, payload.
    local function parse(chunk)
        local i, n, payload = chunk:match("^%((%d+)/(%d+)%) (.*)$")
        return tonumber(i), tonumber(n), payload
    end

    -- Strips the prefixes, checking the numbering on the way, and returns the payloads.
    local function payloads(chunks)
        local out = {}
        for idx, chunk in ipairs(chunks) do
            local i, n, payload = parse(chunk)
            assert.are.equal(idx, i)
            assert.are.equal(#chunks, n)
            out[idx] = payload
        end
        return out
    end

    local function spread(list)
        local min, max = math.huge, 0
        for _, s in ipairs(list) do
            min = math.min(min, #s)
            max = math.max(max, #s)
        end
        return max - min
    end

    -- True if s is well-formed UTF-8: no stray continuation bytes, no truncated sequences.
    local function isValidUtf8(s)
        local i, len = 1, #s
        while i <= len do
            local b = s:byte(i)
            local extra
            if b < 0x80 then
                extra = 0
            elseif b >= 0xC2 and b <= 0xDF then
                extra = 1
            elseif b >= 0xE0 and b <= 0xEF then
                extra = 2
            elseif b >= 0xF0 and b <= 0xF4 then
                extra = 3
            else
                return false
            end
            if i + extra > len then return false end
            for k = 1, extra do
                local c = s:byte(i + k)
                if c < 0x80 or c > 0xBF then return false end
            end
            i = i + extra + 1
        end
        return true
    end

    -- Deterministic mixed text of exactly `target` bytes: 2 byte (Cyrillic, Greek),
    -- 3 byte (CJK) and 4 byte (emoji) characters.
    local WORDS = {
        "щгд", "丮乊", "νδσκςφζ", "🎲📚", "мчждгн", "丫乘丬乌", "γγιπχ", "🌍🌍😀",
        "ьтшцбэ", "串丿上丕丹", "βοωφςνν", "🚀🌸🎲", "зягнти", "両丽乘且乂", "ταγη",
    }
    local function sample(target)
        local parts, size, i = {}, 0, 0
        while true do
            i = i + 1
            local word = WORDS[(i * 7) % #WORDS + 1] .. " "
            if size + #word > target then break end
            parts[#parts + 1] = word
            size = size + #word
        end
        local remaining = target - size
        while remaining >= 2 do
            if remaining % 2 == 1 and remaining >= 3 then
                parts[#parts + 1] = "世"
                remaining = remaining - 3
            else
                parts[#parts + 1] = "я"
                remaining = remaining - 2
            end
        end
        if remaining == 1 then parts[#parts + 1] = " " end
        local s = table.concat(parts)
        assert(#s == target)
        return s
    end

    local ALPHABETS = {
        { "a", "b", "c", " ", "\n" },
        { "щ", "я", "δ", "ξ" },
        { "丮", "乊", "世", "界" },
        { "🎲", "📚", "🌍", "😀" },
    }
    -- Random mixed text of at least `target` bytes.
    local function randomText(target)
        local parts, size = {}, 0
        while size < target do
            local alphabet = ALPHABETS[math.random(#ALPHABETS)]
            local c = alphabet[math.random(#alphabet)]
            parts[#parts + 1] = c
            size = size + #c
        end
        return table.concat(parts)
    end

    it("should return an empty table for nil and empty text", function()
        assert.are.same({}, QRMessage.splitText(nil))
        assert.are.same({}, QRMessage.splitText(""))
    end)

    it("should return text up to the limit unchanged, with no prefix", function()
        for _, len in ipairs({ 1, 100, LIMIT - 1, LIMIT }) do
            local text = ("x"):rep(len)
            assert.are.same({ text }, QRMessage.splitText(text))
        end
    end)

    it("should split one byte over the limit into two prefixed pages", function()
        local text = ("x"):rep(LIMIT + 1)
        local chunks = QRMessage.splitText(text)
        assert.are.equal(2, #chunks)
        assert.are.equal("(1/2) ", chunks[1]:sub(1, 6))
        assert.are.equal("(2/2) ", chunks[2]:sub(1, 6))
        assert.are.equal(text, table.concat(payloads(chunks)))
    end)

    it("should fill exactly two pages at twice the limit, and need three one byte more", function()
        local chunks = QRMessage.splitText(("x"):rep(LIMIT * 2))
        assert.are.equal(2, #chunks)
        for _, payload in ipairs(payloads(chunks)) do
            assert.are.equal(LIMIT, #payload)
        end
        assert.are.equal(3, #QRMessage.splitText(("x"):rep(LIMIT * 2 + 1)))
    end)

    it("should use the fewest pages and balance them to within one byte for ASCII", function()
        for len = LIMIT + 1, 30000, 997 do
            local text = ("x"):rep(len)
            local chunks = QRMessage.splitText(text)
            assert.are.equal(math.ceil(len / LIMIT), #chunks)
            local list = payloads(chunks)
            assert.are.equal(text, table.concat(list))
            assert.is_true(spread(list) <= 1, "spread too large at length " .. len)
            for _, payload in ipairs(list) do
                assert.is_true(#payload <= LIMIT)
            end
        end
    end)

    it("should keep the prefix within PREFIX_RESERVE even for a few hundred pages", function()
        local chunks = QRMessage.splitText(("x"):rep(300000))
        assert.is_true(#chunks > 100)
        local widest = 0
        for _, chunk in ipairs(chunks) do
            local _, _, payload = parse(chunk)
            widest = math.max(widest, #chunk - #payload)
        end
        assert.is_true(widest <= PREFIX_RESERVE)
    end)

    it("should split a 2600 byte non-ASCII paragraph into two balanced, valid pages", function()
        local text = sample(2600)
        local chunks = QRMessage.splitText(text)
        assert.are.equal(2, #chunks)
        local list = payloads(chunks)
        assert.are.equal(text, table.concat(list))
        for _, payload in ipairs(list) do
            assert.is_true(isValidUtf8(payload))
            assert.is_true(#payload > 0)
        end
        assert.is_true(spread(list) <= 6)
    end)

    it("should never cut inside a 4 byte character", function()
        -- 1300 emoji = 5200 bytes -> 3 pages; every cut lands between characters
        local text = ("🌍"):rep(1300)
        local list = payloads(QRMessage.splitText(text))
        assert.are.equal(3, #list)
        assert.are.equal(text, table.concat(list))
        for _, payload in ipairs(list) do
            assert.is_true(isValidUtf8(payload))
            assert.are.equal(0, #payload % 4)
        end
    end)

    it("should not lose, duplicate or corrupt anything for random mixed text", function()
        math.randomseed(12345)
        for _ = 1, 60 do
            local text = randomText(math.random(LIMIT + 1, 20000))
            local chunks = QRMessage.splitText(text)
            -- no runt page: the count is always the planned one, multi-byte or not
            assert.are.equal(math.ceil(#text / LIMIT), #chunks)
            local list = payloads(chunks)
            assert.are.equal(text, table.concat(list))
            for _, payload in ipairs(list) do
                assert.is_true(#payload > 0)
                assert.is_true(isValidUtf8(payload))
            end
            -- pages stay within a handful of bytes of each other
            assert.is_true(spread(list) <= 12, "spread " .. spread(list))
        end
    end)

    it("should keep every symbol within one version of the others", function()
        -- The point of balancing: no 3 pages at version 26 and one at version 3.
        -- Adjacent versions are 4 modules apart, so allow a difference of 4.
        math.randomseed(777)
        for _ = 1, 25 do
            local text = randomText(math.random(LIMIT + 1, 12000))
            local min_size, max_size = math.huge, 0
            for _, chunk in ipairs(QRMessage.splitText(text)) do
                assert.is_true(#chunk <= QRWidget.MAX_BYTES)
                local ok, _, _, size = pcall(qrencode.qrcode, chunk)
                assert.is_true(ok)
                min_size = math.min(min_size, size)
                max_size = math.max(max_size, size)
            end
            assert.is_true(max_size - min_size <= 4)
        end
    end)

    it("should terminate, and lose nothing, on input with no lead bytes", function()
        -- 6000 continuation bytes: nothing valid to step back to, so it must hard cut.
        local text = ("\xA9"):rep(6000)
        local chunks = QRMessage.splitText(text)
        assert.is_true(#chunks >= 3)
        assert.are.equal(text, table.concat(payloads(chunks)))
    end)

    it("should cope with text ending in a truncated multi-byte sequence", function()
        local text = ("x"):rep(5000) .. "\xE4\xB8" -- first two bytes of a 3 byte character
        local chunks = QRMessage.splitText(text)
        assert.are.equal(text, table.concat(payloads(chunks)))
    end)

    it("should number pages by the real count, not the estimate", function()
        local text = sample(9000)
        local chunks = QRMessage.splitText(text)
        for idx, chunk in ipairs(chunks) do
            local i, n = parse(chunk)
            assert.are.equal(idx, i)
            assert.are.equal(#chunks, n)
        end
    end)
end)

describe("QRMessage widget", function()
    local QRMessage, UIManager, BD, Device, Geom
    local dirty_calls, orig_setDirty, orig_mirrored, orig_inverted

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        BD = require("ui/bidi")
        Device = require("device")
        Geom = require("ui/geometry")
        QRMessage = require("ui/widget/qrmessage")
    end)

    before_each(function()
        -- Nothing is shown in these tests, so record repaint requests instead of queueing them.
        dirty_calls = {}
        orig_setDirty = UIManager.setDirty
        UIManager.setDirty = function(_, widget, refreshtype)
            table.insert(dirty_calls, { widget = widget, refreshtype = refreshtype })
        end
        orig_mirrored = BD._mirrored_ui_layout
        orig_inverted = BD._inverted
    end)

    after_each(function()
        UIManager.setDirty = orig_setDirty
        BD._mirrored_ui_layout = orig_mirrored
        BD._inverted = orig_inverted
    end)

    local LONG = ("a"):rep(5000) -- 3 pages

    local function lastDirty()
        return dirty_calls[#dirty_calls]
    end

    describe("layout", function()
        it("should show a single code without a footer for short text", function()
            local msg = QRMessage:new{ text = "hello" }
            assert.are.equal(1, #msg.pages)
            assert.are.equal("hello", msg.pages[1])
            assert.is_nil(msg.footer)
        end)

        it("should page long text and show a footer", function()
            local msg = QRMessage:new{ text = LONG }
            assert.are.equal(3, #msg.pages)
            assert.are.equal(1, msg.page_num)
            assert.is_not_nil(msg.footer)
            assert.are.equal("Page 1 of 3", msg.page_indicator.text)
        end)

        it("should show a placeholder instead of a QR code for empty text", function()
            local msg = QRMessage:new{ text = "" }
            assert.are.equal(0, #msg.pages)
            assert.are.equal("Could not generate a QR code", msg.content_group[2][1].text)
        end)

        it("should treat nil text as empty", function()
            local msg
            assert.has_no.errors(function() msg = QRMessage:new{} end)
            assert.are.equal(0, #msg.pages)
        end)

        it("should title the code with the byte count, not the character count", function()
            assert.are.equal("Scan me (5 bytes)", QRMessage:new{ text = "hello" }.title_bar.title)
            assert.are.equal("Scan me (2 bytes)", QRMessage:new{ text = "é" }.title_bar.title)
            assert.are.equal("Send to Device (5 bytes)",
                QRMessage:new{ title = "Send to Device", text = "hello" }.title_bar.title)
        end)
    end)

    describe("paging", function()
        it("should move between pages and stay inside the range", function()
            local msg = QRMessage:new{ text = LONG }
            assert.is_true(msg:onNextPage())
            assert.are.equal(2, msg.page_num)
            msg:onNextPage()
            msg:onNextPage() -- already on the last page
            assert.are.equal(3, msg.page_num)
            msg:onPrevPage()
            assert.are.equal(2, msg.page_num)
            msg:onFirstPage()
            assert.are.equal(1, msg.page_num)
            msg:onPrevPage() -- already on the first page
            assert.are.equal(1, msg.page_num)
            msg:onLastPage()
            assert.are.equal(3, msg.page_num)
        end)

        it("should swap the image, update the indicator and request a repaint", function()
            local msg = QRMessage:new{ text = LONG }
            local first = msg.content_group[2]
            msg:onNextPage()
            assert.are_not.equal(first, msg.content_group[2])
            assert.are.equal("Page 2 of 3", msg.page_indicator.text)
            assert.are.equal(msg, lastDirty().widget)
            assert.are.equal("ui", lastDirty().refreshtype)
        end)

        it("should not repaint when the page does not change", function()
            local msg = QRMessage:new{ text = LONG }
            local before = #dirty_calls
            msg:onPrevPage()
            assert.are.equal(before, #dirty_calls)
        end)

        it("should disable the footer buttons that cannot be used", function()
            local msg = QRMessage:new{ text = LONG }
            local b = msg.footer_buttons
            assert.is_false(b.first.enabled)
            assert.is_false(b.prev.enabled)
            assert.is_true(b.next.enabled)
            assert.is_true(b.last.enabled)
            msg:onLastPage()
            assert.is_true(b.first.enabled)
            assert.is_true(b.prev.enabled)
            assert.is_false(b.next.enabled)
            assert.is_false(b.last.enabled)
        end)
    end)

    describe("swipes", function()
        it("should page on horizontal swipes", function()
            local msg = QRMessage:new{ text = LONG }
            assert.is_truthy(msg:onSwipe(nil, { direction = "west" }))
            assert.are.equal(2, msg.page_num)
            assert.is_truthy(msg:onSwipe(nil, { direction = "east" }))
            assert.are.equal(1, msg.page_num)
        end)

        it("should swap the paging direction in a mirrored layout", function()
            local msg = QRMessage:new{ text = LONG }
            msg:onNextPage()
            BD._mirrored_ui_layout = true
            msg:onSwipe(nil, { direction = "west" })
            assert.are.equal(1, msg.page_num)
        end)

        it("should leave vertical and diagonal swipes to other handlers", function()
            local msg = QRMessage:new{ text = LONG }
            for _, direction in ipairs({ "north", "south", "northeast", "northwest", "southeast", "southwest" }) do
                assert.is_falsy(msg:onSwipe(nil, { direction = direction }))
            end
            assert.are.equal(1, msg.page_num)
        end)

        it("should do a full refresh on any diagonal swipe", function()
            local msg = QRMessage:new{ text = LONG }
            for _, direction in ipairs({ "northeast", "northwest", "southeast", "southwest" }) do
                local before = #dirty_calls
                assert.is_true(msg:onDiagonalSwipe(nil, { direction = direction }))
                assert.are.equal(before + 1, #dirty_calls)
                assert.are.equal(msg, lastDirty().widget)
                assert.are.equal("full", lastDirty().refreshtype)
            end
        end)

        it("should refresh screen on onFullRefresh", function()
            local msg = QRMessage:new{ text = "hello" }
            assert.is_true(msg:onFullRefresh())
            assert.are.equal(msg, lastDirty().widget)
            assert.are.equal("full", lastDirty().refreshtype)
        end)
    end)

    describe("input handling", function()
        local function gesture(direction)
            return {
                ges = "swipe",
                direction = direction,
                pos = Geom:new{ x = 10, y = 10, w = 0, h = 0 },
            }
        end

        it("should register the swipe handlers", function()
            if not Device:isTouchDevice() then
                return pending("needs a touch device")
            end
            local single = QRMessage:new{ text = "hello" }
            assert.is_not_nil(single.ges_events.DiagonalSwipe)
            assert.is_nil(single.ges_events.Swipe)
            local paged = QRMessage:new{ text = LONG }
            assert.is_not_nil(paged.ges_events.DiagonalSwipe)
            assert.is_not_nil(paged.ges_events.Swipe)
        end)

        it("should resolve swipes the same way whichever handler is tried first", function()
            if not Device:isTouchDevice() then
                return pending("needs a touch device")
            end
            -- Both registrations match every swipe, and ges_events is walked in
            -- undefined order, so the handlers must be disjoint by direction.
            local msg = QRMessage:new{ text = LONG }
            assert.is_true(msg:onGesture(gesture("west")))
            assert.are.equal(2, msg.page_num)
            local before = #dirty_calls
            assert.is_true(msg:onGesture(gesture("northeast")))
            assert.are.equal(before + 1, #dirty_calls)
            assert.are.equal("full", lastDirty().refreshtype)
            assert.are.equal(2, msg.page_num)
        end)

        it("should swallow gestures it does not handle", function()
            if not Device:isTouchDevice() then
                return pending("needs a touch device")
            end
            -- Otherwise they reach the (always active) InputDialog underneath.
            local msg = QRMessage:new{ text = LONG }
            assert.is_true(msg:onGesture(gesture("north")))
            assert.is_true(msg:onGesture({
                ges = "tap",
                pos = Geom:new{ x = 10, y = 10, w = 0, h = 0 },
            }))
            assert.are.equal(1, msg.page_num)
        end)

        it("should register paging keys only for multi-page codes", function()
            if not Device:hasKeys() then
                return pending("needs a device with keys")
            end
            local single = QRMessage:new{ text = "hello" }
            assert.is_nil(single.key_events.NextPage)
            assert.is_nil(single.key_events.PrevPage)
            assert.is_not_nil(single.key_events.Close)
            assert.is_not_nil(single.key_events.FullRefresh)
            local paged = QRMessage:new{ text = LONG }
            assert.is_not_nil(paged.key_events.NextPage)
            assert.is_not_nil(paged.key_events.PrevPage)
        end)
    end)

    describe("closing", function()
        it("should invert and then restore the bidi layout", function()
            local before = BD.mirroredUILayout()
            local msg = QRMessage:new{ text = "hello", invert_bidi = true }
            assert.are_not.equal(before, BD.mirroredUILayout())
            msg:onCloseWidget()
            assert.are.equal(before, BD.mirroredUILayout())
        end)

        it("should leave the bidi layout alone when not asked to invert", function()
            local before = BD.mirroredUILayout()
            local msg = QRMessage:new{ text = "hello" }
            assert.are.equal(before, BD.mirroredUILayout())
            msg:onCloseWidget()
            assert.are.equal(before, BD.mirroredUILayout())
        end)

        it("should call dismiss_callback once", function()
            local calls = 0
            local msg = QRMessage:new{
                text = "hello",
                dismiss_callback = function() calls = calls + 1 end,
            }
            msg:onCloseWidget()
            msg:onCloseWidget()
            assert.are.equal(1, calls)
        end)

        it("should free the current image", function()
            local msg = QRMessage:new{ text = "hello" }
            local image = msg.content_group[2]
            local freed = 0
            local orig_free = image.free
            image.free = function(self, ...)
                freed = freed + 1
                return orig_free(self, ...)
            end
            msg:onCloseWidget()
            assert.are.equal(1, freed)
        end)
    end)
end)
