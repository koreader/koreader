describe("Epub", function()
        local Epub
        local EpubError
        local XHtmlItem
        local Image
        local ItemFactory
        local xhtml_example_content
        setup(function()
                orig_path = package.path
                package.path = "plugins/gazette.koplugin/?.lua;" .. package.path
                require("commonrequire")
                EpubError = require("libs/gazette/epuberror")
                Epub = require("libs/gazette/epub/epub")
                XHtmlItem = require("libs/gazette/epub/package/item/xhtmlitem")
                Image = require("libs/gazette/epub/package/item/image")
                ItemFactory = require("libs/gazette/factories/itemfactory")
                local ExampleContent = require("spec/unit/examplecontent")
                xhtml_example_content = ExampleContent.XHTML_EXAMPLE_CONTENT
        end)
        describe("Manifest", function()
                it("should build from a list of items", function()
                        local item_one = XHtmlItem:new{
                            path = "random/path/to/content.xhtml"
                        }
                        local item_two = XHtmlItem:new{
                            path = "another_random/path/to/content.xhtml"
                        }
                        local Manifest = require("libs/gazette/epub/package/manifest")
                        local manifest = Manifest:new{}
                        manifest:addItem(item_one)
                        manifest:addItem(item_two)
                        local nav = manifest.items[manifest:findItemLocationByProperties("nav")]
                        local expected_xml = string.format(
                            [[%s%s%s%s%s%s%s]],
                            "\n",
                            nav:getManifestPart(),
                            "\n",
                            item_one:getManifestPart(),
                            "\n",
                            item_two:getManifestPart(),
                            "\n"
                        )
                        assert.are.same(expected_xml, manifest:build())
                end)
                it("should not add the same item twice", function()
                        local item = XHtmlItem:new{
                            path = "random/path/to/content.xhtml"
                        }
                        local Manifest = require("libs/gazette/epub/package/manifest")
                        local manifest = Manifest:new{}
                        manifest:addItem(item)
                        manifest:addItem(item)
                        local nav = manifest.items[manifest:findItemLocationByProperties("nav")]
                        local expected_xml = string.format(
                            [[%s%s%s%s%s]],
                            "\n",
                            nav:getManifestPart(),
                            "\n",
                            item:getManifestPart(),
                            "\n"
                        )
                        assert.are.same(expected_xml, manifest:build())
                end)
        end)
        describe("XHtmlItem", function()
                it("should output manifest part", function()
                        local xhtml_content = XHtmlItem:new{
                            path = "random/path/to/content.xhtml",
                            content = xhtml_example_content
                        }
                        local manifest = xhtml_content:getManifestPart()
                        local manifest_to_match = string.format(
                            [[<item id="%s" href="%s" media-type="%s"/>]],
                            xhtml_content.id,
                            xhtml_content.path,
                            "application/xhtml+xml"
                        )
                        assert.are.same(manifest_to_match, manifest)
                end)
                it("should show error message when path isn't set", function()
                        local xhtml_content, err = XHtmlItem:new{}
                        assert.are.same(false, xhtml_content)
                        assert.are.same(EpubError.ITEM_MISSING_PATH, err)
                end)
        end)
        describe("Image", function()
                it("should match the image type when given a path", function()
                        local image, err = Image:new{
                            path = "https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail-150x79.png"
                        }
                        assert.are.same("image/png", image.media_type)
                end)
                it("should show error when image type not supported", function()
                        local image, err = Image:new{
                            path = "https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail-150x79.xyz"
                        }
                        assert.are.same(false, image)
                        assert.are.same(EpubError.IMAGE_UNSUPPORTED_FORMAT, err)
                end)
        end)
        describe("ItemFactory", function()
                it("should make the correct type of item when given supported type", function()
                        local image = ItemFactory:makeItem(
                            "https://ourworldindata.org/uploads/2021/06/Clean-Water-thumbnail-150x79.png",
                            ""
                        )
                        assert.are.same("image/png", image.media_type)
                        local xhtml, err = ItemFactory:makeItem(
                            "content.xhtml",
                            ""
                        )
                        assert.are.same("application/xhtml+xml", xhtml.media_type)
                end)
                it("should show error when given unsupported type", function()
                        local mp3, err = ItemFactory:makeItem(
                            "audiofile.mp3",
                            ""
                        )
                        assert.are.same(EpubError.ITEMFACTORY_UNSUPPORTED_TYPE, err)
                end)
        end)
end)
