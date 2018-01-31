describe("document registry module", function()
    local DocumentRegistry

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    it("should get preferred rendering engine", function()
        assert.is_equal("Cool Reader Engine",
                        DocumentRegistry:getProvider("bla.epub").provider_name)
        assert.is_equal("MuPDF",
                        DocumentRegistry:getProvider("bla.pdf").provider_name)
    end)

    it("should return all supported rendering engines", function()
        local providers = DocumentRegistry:getProviders("bla.epub")
        assert.is_equal("Cool Reader Engine",
                        providers[1].provider.provider_name)
        assert.is_equal("MuPDF",
                        providers[2].provider.provider_name)
    end)
end)
