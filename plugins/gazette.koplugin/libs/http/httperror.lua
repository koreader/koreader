local _ = require("gettext")
local T = require("ffi/util").template

local HttpError = {

}

HttpError.RESPONSE_NONSPECIFIC_ERROR = _("There was an error. That's all I know.")
HttpError.REQUEST_UNSUPPORTED_SCHEME = _("Scheme not supported.")
HttpError.REQUEST_INCOMPLETE = _("Request couldn't complete. Code %1.")
HttpError.REQUEST_PAGE_NOT_FOUND = _("Page not found.")
HttpError.RESPONSE_HAS_NO_CONTENT = _("No content found in response.")

function HttpError:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function HttpError:provideFromResponse(response)
    if not response:hasCompleted()
    then
        return T(HttpError.REQUEST_INCOMPLETE, response.code)
    elseif response.code == 404 or not response:isHostKnown()
    then
        return HttpError.REQUEST_PAGE_NOT_FOUND
    elseif not response:hasContent()
    then
        return HttpError.RESPONSE_HAS_NO_CONTENT
    end
    return HttpError.RESPONSE_NONSPECIFIC_ERROR
end

return HttpError
