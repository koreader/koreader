--[[--
Unit tests for model/page.lua.

Pure Lua; no KOReader runtime needed.
Run with: busted spec/page_spec.lua
--]]--

-- Stub heavy KOReader deps before requiring our modules
package.loaded["ffi/blitbuffer"] = {}
package.loaded["ui/uimanager"]   = {}

-- Make lib/ and model/ available on the path
local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" ..
               plugin_dir .. "/model/?.lua;" .. package.path

local Page = require("model/page")

describe("Page", function()

    local tmpdir

    before_each(function()
        tmpdir = os.tmpname()
        os.remove(tmpdir)
        os.execute("mkdir -p " .. tmpdir)
    end)

    after_each(function()
        os.execute("rm -rf " .. tmpdir)
    end)

    describe("Page.new", function()
        it("creates an empty page at the given path", function()
            local p = Page.new(tmpdir .. "/p.svg")
            assert.equal(tmpdir .. "/p.svg", p.path)
            assert.truthy(p.stroke_buf)
            assert.equal(0, #p.stroke_buf.strokes)
        end)

        it("accepts a pre-populated StrokeBuffer", function()
            local StrokeBuffer = require("lib/strokebuffer")
            local sb = StrokeBuffer.new()
            sb:penDown(10, 20, 3)
            sb:penMove(30, 40, 3)
            sb:penUp()
            local p = Page.new("/tmp/x.svg", sb)
            assert.equal(1, #p.stroke_buf.strokes)
        end)
    end)

    describe("Page.load", function()
        it("returns a blank page when file does not exist", function()
            local p, w, h = Page.load(tmpdir .. "/missing.svg")
            assert.truthy(p)
            assert.equal(0, #p.stroke_buf.strokes)
            assert.is_nil(w)
            assert.is_nil(h)
        end)

        it("loads strokes from an SVG file", function()
            -- Build a minimal SVG with a metadata block
            local json = require("lib/json")
            local strokes_data = json.encode({strokes = {
                {color = "#000000", pts = {10, 20, 3, 30, 40, 3}},
            }})
            local svg_text = table.concat({
                '<svg xmlns="http://www.w3.org/2000/svg" width="500" height="700">',
                '<rect width="500" height="700" fill="white"/>',
                '<metadata><fn:data xmlns:fn="urn:fastnote:1">',
                '{"version":1,"w":500,"h":700,"strokes":[{"color":"#000000","pts":[10,20,3,30,40,3]}]}',
                '</fn:data></metadata>',
                '</svg>',
            }, "\n")
            local path = tmpdir .. "/test.svg"
            local f = io.open(path, "w"); f:write(svg_text); f:close()

            local p, w, h = Page.load(path)
            assert.equal(1, #p.stroke_buf.strokes)
            assert.equal(500, w)
            assert.equal(700, h)
            assert.equal(path, p.path)
        end)
    end)

    describe("Page:isDirty", function()
        it("is false immediately after new", function()
            local p = Page.new(tmpdir .. "/x.svg")
            assert.is_false(p:isDirty())
        end)

        it("is true after adding a stroke", function()
            local p = Page.new(tmpdir .. "/x.svg")
            p.stroke_buf:penDown(0,0,3); p.stroke_buf:penMove(10,10,3); p.stroke_buf:penUp()
            assert.is_true(p:isDirty())
        end)

        it("is false after save", function()
            local p = Page.new(tmpdir .. "/x.svg")
            p.stroke_buf:penDown(0,0,3); p.stroke_buf:penMove(10,10,3); p.stroke_buf:penUp()
            p:save(100, 100)
            assert.is_false(p:isDirty())
        end)

        it("goes dirty again after another stroke", function()
            local p = Page.new(tmpdir .. "/x.svg")
            p.stroke_buf:penDown(0,0,3); p.stroke_buf:penMove(10,10,3); p.stroke_buf:penUp()
            p:save(100, 100)
            p.stroke_buf:penDown(1,1,3); p.stroke_buf:penMove(5,5,3); p.stroke_buf:penUp()
            assert.is_true(p:isDirty())
        end)
    end)

    describe("Page:save", function()
        it("writes an SVG file", function()
            local p = Page.new(tmpdir .. "/out.svg")
            p.stroke_buf:penDown(0,0,3); p.stroke_buf:penMove(50,50,3); p.stroke_buf:penUp()
            local ok, err = p:save(200, 300)
            assert.is_true(ok)
            assert.is_nil(err)
            local f = io.open(tmpdir .. "/out.svg", "r")
            assert.truthy(f)
            local text = f:read("*a"); f:close()
            assert.truthy(text:find("<svg"))
            assert.truthy(text:find("fn:data"))
        end)

        it("returns false for an unwritable path", function()
            local p = Page.new("/no/such/dir/x.svg")
            local ok, err = p:save(100, 100)
            assert.is_false(ok)
            assert.truthy(err)
        end)
    end)

end)
