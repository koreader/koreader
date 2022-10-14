local _ = require("gettext")
local T = require("ffi/util").template

local EpubError = {

}

EpubError.EPUB_INVALID_CONTENTS = _("Contents invalid")
EpubError.EPUBWRITER_INVALID_PATH = _("The path couldn't be opened.")
EpubError.ITEMFACTORY_UNSUPPORTED_TYPE = _("Item type is not supported.")
EpubError.ITEMFACTORY_NONEXISTENT_CONSTRUCTOR = _("Item type is supported but ItemFactory doesn't have a constructor for it.")
EpubError.RESOURCE_WEBPAGE_INVALID_URL = _("")
EpubError.ITEM_MISSNG_ID = _("Item missing id")
EpubError.ITEM_MISSING_MEDIA_TYPE = _("Item missing media type")
EpubError.ITEM_MISSING_PATH = _("Item missing path")
EpubError.ITEM_NONSPECIFIC_ERROR = _("Something's wrong with your item. That's all I know")
EpubError.IMAGE_UNSUPPORTED_FORMAT = _("Image format is not supported.")
EpubError.MANIFEST_BUILD_ERROR = _("Could not build manifest part for item.")
EpubError.MANIFEST_ITEM_ALREADY_EXISTS = _("Item already exists in manifest")
EpubError.MANIFEST_ITEM_NIL = _("Can't add a nil item to the manifest.")
EpubError.SPINE_BUILD_ERROR = _("Could not build spine part for item.")

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
