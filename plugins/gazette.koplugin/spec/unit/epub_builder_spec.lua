describe("Epub Builder", function()
      local EpubBuildDirector
      local Epub
      local output_dir
      setup(function()
            orig_path = package.path
            package.path = "plugins/gazette.koplugin/?.lua;" .. package.path
            require("commonrequire")
            output_dir = "/home/scarlett/"
            EpubBuildDirector = require("libs/gazette/epubbuilddirector")
            EpubError = require("libs/gazette/epuberror")
            Epub = require("libs/gazette/epub/epub")
            FeedFactory = require("feed/feedfactory")
            HttpError = require("libs/http/httperror")
            XHtmlItem = require("libs/gazette/epub/package/item/xhtmlitem")
            ResourceAdapter = require("libs/gazette/resources/webpageadapter")
            WebPage = require("libs/gazette/resources/webpage")
            HtmlDocument = require("libs/gazette/resources/htmldocument")
            Image = require("libs/gazette/resources/image")
            local ExampleContent = require("spec/unit/examplecontent")
            xhtml_example_content = ExampleContent.XHTML_EXAMPLE_CONTENT
            html_example_content_with_images = ExampleContent.HTML_EXAMPLE_WITH_IMAGES
            base_64_image_src = ExampleContent.BASE_64_IMAGE_SRC
      end)
      describe("Resources", function()
            describe("HtmlDocument", function()
                  it("should find the title", function()
                        local html = HtmlDocument:new{
                           html = html_example_content_with_images
                        }
                        assert.are.same(
                           "Guinea worm disease is close to being eradicated – how was this progress achieved? - Our World in Data",
                           html.title
                        )
                  end)
            end)
            describe("Image", function()
                  it("should throw error when base 64 string is used as URL", function()
                        local image_from_base_64 = Image:new{
                           url = base_64_image_src,
                        }
                        assert.are.same(false, image_from_base_64)
                  end)
            end)
            describe("WebPage", function()
                  it("should fetch content when only given URL", function()
                        local webpage = WebPage:new{
                           url = "https://www.gnupg.org/gph/en/manual.html",
                        }
                        assert.are_not.same(nil, webpage.html)
                  end)
                  it("should return an error when given invalid URL", function()
                        local webpage, err = WebPage:new{
                           url = "https://www.gnupg-not-a-website.com",
                        }
                        assert.are.same(false, webpage)
                        assert.are.same(HttpError.REQUEST_PAGE_NOT_FOUND, err)
                  end)
                  it("should build resources successfully", function()
                        local webpage = WebPage:new{
                           url = "https://ourworldindata.org/team",
                        }
                        webpage:build()
                        local has_resources = #webpage.resources >= 4 and true or false
                        assert.are.same(true, has_resources)
                  end)
            end)
      end)
      describe("EpubBuildDirector", function()
            it("should create a new EpubWriter when given valid path", function()
                  local build_director, err = EpubBuildDirector:new()
                  build_director:setDestination(output_dir .. "00_test_epub.epub")
                  assert.are_not.same(false, build_director)
            end)
            it("should throw an error when creating EpubWriter with invalid path", function()
                  local build_director, err = EpubBuildDirector:new()
                  local ok, err = build_director:setDestination("/home/not_a_directory/00_test_epub.epub")
                  assert.are.same(false, ok)
                  assert.are.same(EpubError.EPUBWRITER_INVALID_PATH, err)
            end)
            it("should build epub from XHtml item", function()
                  local item = XHtmlItem:new{
                     path = "content_1.xhtml",
                     content = xhtml_example_content
                  }
                  local epub = Epub:new()
                  epub:addItem(item)

                  local build_director, err = EpubBuildDirector:new()
                  build_director:setDestination(output_dir .. "00_test_epub.epub")
                  local ok, err = build_director:construct(epub)

                  assert.are.same(true, ok)
            end)
            it("should build EPUB when given a Webpage", function()
                  local webpage = WebPage:new{
                     url = "https://www.gnupg.org/gph/en/manual.html",
                     content = html_example_content_with_images
                  }
                  webpage:build()

                  local epub = Epub:new{}
                  epub:setTitle("GnuPGP Handbook " .. os.date("%Y-%m-%dT%H:%M:%SZ"))
                  epub:addFromList(ResourceAdapter:new(webpage))

                  local build_director, err = EpubBuildDirector:new()
                  build_director:setDestination(output_dir .. "11_test_epub_ "
                     .. os.date("%H:%M:%SZ").. ".epub")
                  local ok, err = build_director:construct(epub)

                  assert.are.same(true, ok)
            end)
            it("should build an epub with multiple resources", function()
                  local webpage_1 = WebPage:new{
                     url = "https://ourworldindata.org/much-better-awful-can-be-better"
                  }
                  webpage_1:build()

                  local webpage_2 = WebPage:new{
                     url = "https://www.nature.com/immersive/d41586-022-01898-3/index.html"
                  }
                  webpage_2:build()

                  local epub = Epub:new{}
                  epub:setTitle("Test with multiple resources " .. os.date("%Y-%m-%dT%H:%M:%SZ"))
                  epub:addFromList(ResourceAdapter:new(webpage_1))
                  epub:addFromList(ResourceAdapter:new(webpage_2))

                  local build_director, err = EpubBuildDirector:new()
                  build_director:setDestination(output_dir .. "gazette_multiple_resource_test- "
                     .. os.date("%H:%M:%SZ").. ".epub")
                  local ok, err = build_director:construct(epub)

                  assert.are.same(true, ok)
            end)
      end)
end)
