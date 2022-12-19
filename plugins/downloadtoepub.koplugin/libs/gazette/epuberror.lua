local _ = require("gettext")
local T = require("ffi/util").template

local EpubError = {
    EPUB_INVALID_CONTENTS = _("Contents invalid"),
    EPUBWRITER_INVALID_PATH = _("The path couldn't be opened."),
    ITEMFACTORY_UNSUPPORTED_TYPE = _("Item type is not supported."),
    ITEMFACTORY_NONEXISTENT_CONSTRUCTOR = _("Item type is supported but ItemFactory doesn't have a constructor for it."),
    RESOURCE_WEBPAGE_INVALID_URL = _(""),
    ITEM_MISSNG_ID = _("Item missing id"),
    ITEM_MISSING_MEDIA_TYPE = _("Item missing media type"),
    ITEM_MISSING_PATH = _("Item missing path"),
    ITEM_NONSPECIFIC_ERROR = _("Something's wrong with your item. That's all I know"),
    IMAGE_UNSUPPORTED_FORMAT = _("Image format is not supported."),
    MANIFEST_BUILD_ERROR = _("Could not build manifest part for item."),
    MANIFEST_ITEM_ALREADY_EXISTS = _("Item already exists in manifest"),
    MANIFEST_ITEM_NIL = _("Can't add a nil item to the manifest."),
    SPINE_BUILD_ERROR = _("Could not build spine part for item."),
}

function EpubError:provideFromEpubWriter(epubwriter)

end

function EpubError:provideFromItem(item)
    if not item.media_type
    then
        return EpubError.ITEM_MISSING_MEDIA_TYPE
    elseif not item.path
    then
        return EpubError.ITEM_MISSING_PATH
    else
        return EpubError.ITEM_NONSPECIFIC_ERROR
    end
end

return EpubError
