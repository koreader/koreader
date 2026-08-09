describe("TextBoxWidget module", function()
    local TextBoxWidget, Font
    setup(function()
        require("commonrequire")
        Font = require("ui/font")
        TextBoxWidget = require("ui/widget/textboxwidget")
    end)

    it("should select the correct word on HoldWord event", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0},
            face = Font:getFace("cfont", 25),
            text = 'YOOOOOOOOOOOOOOOO\nFoo.\nBar.\nFoo welcomes Bar into the fun.',
        }

        local pos={x=110,y=4}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'YOOOOOOOOOOOOOOOO')
        end, {pos=pos})

        pos={x=0,y=50}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Foo')
        end, {pos=pos})

        pos={x=20,y=80}
        tw:onHoldStartText(nil, {pos=pos})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Bar')
        end, {pos=pos})

        tw:onHoldStartText(nil, {pos={x=50, y=100}})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'welcomes Bar into')
        end, {pos={x=240, y=100}})

        tw:onHoldStartText(nil, {pos={x=20, y=80}})
        tw:onHoldReleaseText(function(w)
            assert.is.same(w, 'Bar.\nFoo welcomes Bar into')
        end, {pos={x=240, y=100}})

        --[[
        -- No more used, not implemented when use_xtext=true
        tw:onHoldWord(function(w)
            assert.is.same(w, 'YOOOOOOOOOOOOOOOO')
        end, {pos={x=110,y=4}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Foo')
        end, {pos={x=0,y=50}})
        tw:onHoldWord(function(w)
            assert.is.same(w, 'Bar')
        end, {pos={x=20,y=80}})
        ]]--
    end)

    it("should build text cache correctly", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0},
            face = Font:getFace("cfont", 25),
            text = 'Hello World',
        }

        tw:_buildTextCache()
        assert.is_not_nil(tw._text_cache)
        assert.is_not_nil(tw._text_cache.lower)
        assert.is_not_nil(tw._text_cache.chars)
        assert.is_not_nil(tw._text_cache.char_to_byte)
        assert.is_not_nil(tw._text_cache.byte_to_char)
    end)

    it("should find text in widget", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0, w = 400, h = 600},
            face = Font:getFace("cfont", 25),
            text = 'The quick brown fox jumps over the lazy dog',
            virtual_line_num = 1,
            lines_per_page = 10,
        }

        tw.vertical_string_list = {{offset = 1}}
        local result = tw:findText('quick')
        assert.is_true(result)
        assert.is_not_nil(tw.highlight_start_idx)
        assert.is_not_nil(tw.highlight_end_idx)
    end)

    it("should return false when finding nonexistent text", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0, w = 400, h = 600},
            face = Font:getFace("cfont", 25),
            text = 'The quick brown fox',
            virtual_line_num = 1,
        }

        tw.vertical_string_list = {{offset = 1}}
        local result = tw:findText('xyz')
        assert.is_false(result)
    end)

    it("should clear search results", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0, w = 400, h = 600},
            face = Font:getFace("cfont", 25),
            text = 'search test text',
            virtual_line_num = 1,
        }

        tw.search_term = 'test'
        tw._search_lower = 'test'
        tw._search_char_len = 4
        tw._match_page_list = {1}
        tw._match_page_index = 1
        tw.highlight_start_idx = 1
        tw.highlight_end_idx = 4

        tw:clearSearch(false)
        assert.is_nil(tw.search_term)
        assert.is_nil(tw._search_lower)
        assert.is_nil(tw._search_char_len)
        assert.is_nil(tw._match_page_list)
        assert.is_nil(tw._match_page_index)
    end)

    it("should build match page list correctly", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0, w = 400, h = 600},
            face = Font:getFace("cfont", 25),
            text = 'foo bar foo baz foo',
            virtual_line_num = 1,
        }

        tw:_buildTextCache()
        tw._search_lower = 'foo'
        tw.getCharPageTopLineNumber = function(self, char) return 1 end

        tw:_buildMatchPageList()
        assert.is_not_nil(tw._match_page_list)
    end)

    it("should navigate to next page with matches", function()
        local tw = TextBoxWidget:new{
            dimen = {x = 0, y = 0, w = 400, h = 600},
            face = Font:getFace("cfont", 25),
            text = 'foo bar foo baz foo',
            virtual_line_num = 1,
            lines_per_page = 5,
        }

        tw._match_page_list = {1, 3, 5}
        tw.vertical_string_list = {{offset = 1}, {offset = 10}, {offset = 20}}

        local result = tw:findTextNextPage(1)
        assert.is_true(result)
    end)
end)
