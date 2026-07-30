describe("Cache module", function()
    local DocumentRegistry, DocCache
    local doc
    local max_page = 1
    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        DocCache = require("document/doccache")

        local sample_pdf = "spec/front/unit/data/sample.pdf"
        doc = DocumentRegistry:openDocument(sample_pdf)
    end)
    teardown(function()
        doc:close()
    end)

    it("should clear cache", function()
        DocCache:clear()
    end)

    it("should serialize blitbuffer", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 1.0)
            DocCache:serialize()
        end
        DocCache:clear()
    end)

    it("should deserialize blitbuffer", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:hintPage(pageno, 1, 0, 1.0, 1.0)
        end
        DocCache:clear()
    end)

    it("should serialize koptcontext", function()
        doc.configurable.text_wrap = 1
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 1.0)
            doc:getPageDimensions(pageno)
            DocCache:serialize()
        end
        DocCache:clear()
        doc.configurable.text_wrap = 0
    end)

    it("should deserialize koptcontext", function()
        for pageno = 1, math.min(max_page, doc.info.number_of_pages) do
            doc:renderPage(pageno, nil, 1, 0, 1.0, 1.0)
        end
        DocCache:clear()
    end)
end)

describe("Cache memory pressure", function()
    local Cache, util
    local orig_calcFreeMem
    -- Strong ref: the instance registry holds weak values.
    local probe, chopped

    setup(function()
        require("commonrequire")
        Cache = require("cache")
        util = require("util")
        orig_calcFreeMem = util.calcFreeMem
    end)
    teardown(function()
        util.calcFreeMem = orig_calcFreeMem
    end)
    before_each(function()
        chopped = 0
        probe = Cache:new{ slots = 4 }
        probe.cache = { chop = function() chopped = chopped + 1 end }
    end)

    it("should do nothing when free memory is comfortable", function()
        util.calcFreeMem = function() return 800 * 1024 * 1024, 1024 * 1024 * 1024 end
        assert.is_false(Cache.checkAllMemoryPressure())
        assert.are.equal(0, chopped)
    end)

    it("should do nothing on platforms without memory info", function()
        util.calcFreeMem = function() return nil, nil end
        assert.is_false(Cache.checkAllMemoryPressure())
        assert.are.equal(0, chopped)
    end)

    it("should chop every registered cache when redlining", function()
        util.calcFreeMem = function() return 64 * 1024 * 1024, 1024 * 1024 * 1024 end
        assert.is_true(Cache.checkAllMemoryPressure())
        assert.are.equal(1, chopped)
    end)

    it("should still support the single-cache check", function()
        util.calcFreeMem = function() return 64 * 1024 * 1024, 1024 * 1024 * 1024 end
        assert.is_true(probe:memoryPressureCheck())
        assert.is_true(chopped >= 1)
    end)
end)

describe("Cache resizing", function()
    local Cache, DocCache, util
    local orig_calcFreeMem

    setup(function()
        require("commonrequire")
        Cache = require("cache")
        DocCache = require("document/doccache")
        util = require("util")
        orig_calcFreeMem = util.calcFreeMem
    end)
    teardown(function()
        util.calcFreeMem = orig_calcFreeMem
    end)

    it("should rebuild the LRU against a new budget", function()
        local cache = Cache:new{ size = 8 * 1024 * 1024, avg_itemsize = 1024 * 1024 }
        assert.are.equal(8, cache.slots)
        assert.is_true(cache:resize(4 * 1024 * 1024))
        assert.are.equal(4 * 1024 * 1024, cache.size)
        assert.are.equal(4, cache.slots)
    end)

    it("should ignore a no-op resize", function()
        local cache = Cache:new{ size = 8 * 1024 * 1024, avg_itemsize = 1024 * 1024 }
        assert.is_false(cache:resize(8 * 1024 * 1024))
        assert.is_false(cache:resize(nil))
    end)

    it("should re-evaluate the document cache budget on a substantial change", function()
        if not DocCache.size then return end -- cache was disabled at load time
        util.calcFreeMem = function() return 1000 * 1024 * 1024, 2048 * 1024 * 1024 end
        DocCache:reevaluate()
        local before = DocCache.size

        util.calcFreeMem = function() return 400 * 1024 * 1024, 2048 * 1024 * 1024 end
        assert.is_true(DocCache:reevaluate())
        assert.is_true(DocCache.size < before)
    end)

    it("should leave the document cache alone on a small change", function()
        if not DocCache.size then return end
        util.calcFreeMem = function() return 400 * 1024 * 1024, 2048 * 1024 * 1024 end
        DocCache:reevaluate()
        local before = DocCache.size

        util.calcFreeMem = function() return 440 * 1024 * 1024, 2048 * 1024 * 1024 end
        assert.is_false(DocCache:reevaluate())
        assert.are.equal(before, DocCache.size)
    end)
end)
