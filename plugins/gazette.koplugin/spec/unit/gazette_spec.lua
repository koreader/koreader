describe("Gazette", function()
      local Gazette
      local html_example_with_images
      local image_elements_example
      setup(function()
            orig_path = package.path
            package.path = "plugins/gazette.koplugin/?.lua;" .. package.path
            require("commonrequire")
            Gazette = require("gazette")
            local ExampleContent = require("spec/unit/examplecontent")
            html_example_with_images = ExampleContent.HTML_EXAMPLE_WITH_IMAGES
            image_elements_example = ExampleContent.IMAGE_ELEMENT_TESTS
      end)
      describe("Gazette", function()

      end)
end)
