project = 'KOReader'
description = 'Multi-platform ebook reader'
full_description = 'An ebook reader application supports PDF, DJVU, EPUB, FB2 and many more formats, running on Kindle, Kobo, PocketBook, Ubuntu Touch and Android devices.'
title = 'KOReader Documentation'
dir = 'html'
style = '!fixed'
use_markdown_titles = true
topics = {
    '../README.md',
    './Collaborating_with_Git.md',
    './DataStore.md',
    './Development_guide.md',
    './Events.md',
    './Hacking.md',
    './Porting.md',
    './Unit_tests.md',
}
package = ''
format = 'markdown'
sort_modules = true
file = {
    '../frontend',
    '../plugins',
    '../base/ffi',
    '../platform/android/luajit-launcher/assets',
    exclude = {'../base/ffi/sha2.lua',
        '../base/ffi/qrencode.lua',
        '../plugins/exporter.koplugin/template/slt2.lua',
        '../plugins/newsdownloader.koplugin/lib/handler.lua',
        '../plugins/newsdownloader.koplugin/lib/xml.lua',
    },
}
