describe("Wikipedia module", function()
    local util
    setup(function()
        require("commonrequire")
        Wikipedia = package.reload("ui/wikipedia")
    end)

    it("should return Wikipedia server", function()
        local expected_server_default = "https://en.wikipedia.org"
        local expected_server_nl = "https://nl.wikipedia.org"
        assert.is.same(expected_server_default, Wikipedia:getWikiServer())
        assert.is.same(expected_server_nl, Wikipedia:getWikiServer("nl"))
    end)
end)
