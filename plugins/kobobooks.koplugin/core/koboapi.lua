local ffiUtil = require("ffi/util")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local sha2 = require "ffi/sha2"
local socket = require("socket")
local socketurl = require("socket.url")
local socketutil = require("socketutil")
local util = require("util")

local KOBO_AFFILIATE = "Kobo"
local KOBO_APPLICATION_VERSION = "4.38.23171"
local KOBO_DEFAULT_PLATFORM_ID = "00000000-0000-0000-0000-000000000373"
local KOBO_DISPLAY_PROFILE = "Android"
local KOBO_DEVICE_MODEL = "Kobo Aura ONE"
local KOBO_DEVICE_OS = "3.0.35+"
local KOBO_DEVICE_OS_VERSION = "NA"

-- Most of these can be obtained from https://storeapi.kobo.com/v1/initialization, but if the URLs
-- change then likely the APIs change too, so we use hardcoding.
local API_URL_ACTIVATE = "https://auth.kobobooks.com/ActivateOnWeb"
local API_URL_ACTIVATION_CHECK = "https://auth.kobobooks.com"
local API_URL_AUTH_DEVICE = "https://storeapi.kobo.com/v1/auth/device"
local API_URL_AUTH_REFRESH = "https://storeapi.kobo.com/v1/auth/refresh"
local API_URL_LIBRARY_SYNC = "https://storeapi.kobo.com/v1/library/sync"
local API_URL_WISHLIST = "https://storeapi.kobo.com/v1/user/wishlist"

local KoboApi = {
}

local KoboApiState = {
    access_token = "",
    device_id = "",
	library_sync_token = "",
    refresh_token = "",
    serial_number = "",
    user_id = "",
    user_key = "",
}

-- This should be in socket.url.
local function parse_query_string(query)
    local arguments = {}
    for key, value in query:gmatch("([^&=]+)=([^&=]*)&?") do
		key = util.urlDecode(key)
		value = util.urlDecode(value)
        if arguments[key] == nil then
            arguments[key] = {value}
        else
            table.insert(arguments[key], value)
        end
    end
    return arguments
end

local function generateRandomHexDigitString(length)
	local characters = "0123456789abcdef"
	local id = ""
	for i = 1, length do
		local index = math.random(#characters)
		id = id .. characters:sub(index, index)
	end
	return id
end

local function areAuthenticationSettingsSet()
	return string.len(KoboApiState.device_id) > 0 and string.len(KoboApiState.access_token) > 0 and string.len(KoboApiState.refresh_token) > 0
end

local function getErrorMessageFromApiResponse(json_response)
	if json_response == nil or json_response["ResponseStatus"] == nil or json_response["ResponseStatus"]["Message"] == nil then
		return ""
	else
		return json_response["ResponseStatus"]["Message"]
	end
end

local function makeJsonPostRequest(url, post_data, additional_headers)
	local json_post_data = json.encode(post_data)

	local headers = {
		["Content-Type"]   = "application/json",
		["Content-Length"] = string.len(json_post_data),
	}
	if additional_headers ~= nil then
		for key in pairs(additional_headers) do
			headers[key] = additional_headers[key]
		end
	end

    local sink = {}
    local request = {
        url     = url,
        method  = "POST",
		headers = headers,
        source  = ltn12.source.string(json_post_data),
        sink    = ltn12.sink.table(sink),
    }

    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local result_response = table.concat(sink)
    local _, json_response = pcall(json.decode, result_response)
	return code, status, json_response
end

local function callJsonApiInternal(url, http_method, body, additional_headers)
	local headers = {
		["Authorization"] = "Bearer " .. KoboApiState.access_token,
		["Content-Type"]  = "application/json",
	}

	if additional_headers ~= nil then
		for key in pairs(additional_headers) do
			headers[key] = additional_headers[key]
		end
	end

    local sink = {}
    local request = {
        url     = url,
        method  = http_method,
        headers = headers,
        sink    = ltn12.sink.table(sink),
    }

	if body ~= nil then
		local json_body = json.encode(body)
		request.headers["Content-Length"] = string.len(json_body)
		request.source = ltn12.source.string(json_body)
	end

    socketutil:set_timeout()
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local json_response = table.concat(sink)
    local _, response = pcall(json.decode, json_response)
	return code, response, headers
end


local function callJsonApi(url, http_method, body, additional_headers)
	local code, response, headers = callJsonApiInternal(url, http_method, body, additional_headers)
	if code == 401 and response ~= nil and response["ResponseStatus"] ~= nil and response["ResponseStatus"]["ErrorCode"] == "ExpiredToken" then
		if KoboApi:refreshAuthentication() then
			code, response, headers = callJsonApiInternal(url, http_method, body, additional_headers)
		end
	end

	return code, response, headers
end

function KoboApi:setApiSettings(settings)
	for key in pairs(settings) do
		if KoboApiState[key] ~= nil then
			KoboApiState[key] = settings[key]
		end
	end
end

-- Return a copy.
function KoboApi:getApiSettings()
	local settings = {}
	for key in pairs(KoboApiState) do
		settings[key] = KoboApiState[key]
	end
	return settings
end

function KoboApi:isLoggedIn()
	return #KoboApiState.user_id > 0 and #KoboApiState.user_key > 0
end

function KoboApi:refreshAuthentication()
	local post_data = {
		["AppVersion"] = KOBO_APPLICATION_VERSION,
		["ClientKey"] = sha2.bin_to_base64(KOBO_DEFAULT_PLATFORM_ID),
		["PlatformId"] = KOBO_DEFAULT_PLATFORM_ID,
		["RefreshToken"] = KoboApiState.refresh_token,
	}

	local additional_headers = {
		["Authorization"]  = "Bearer " .. KoboApiState.access_token,
	}

	local code, status, json_response = makeJsonPostRequest(API_URL_AUTH_REFRESH, post_data, additional_headers)
	if json_response[ "TokenType" ] ~= "Bearer" then
		logger.warn("KoboApi: authentication refresh returned with an unsupported token type: ", json_response[ "TokenType" ])
		return false
	end

	KoboApiState.access_token = json_response[ "AccessToken" ]
	KoboApiState.refresh_token = json_response[ "RefreshToken" ]
	if not areAuthenticationSettingsSet() then
		logger.warn("KoboApi: authentication settings are not set after authentication refresh." )
		return false
	end

	return true
end

function KoboApi:waitTillActivation(activation_check_url)
	while true do
		local code, status, json_response = makeJsonPostRequest(activation_check_url, {})
		if code ~= 200 then
			logger.err("KoboApi: activation check returned with HTTP response code " .. code .. ".")
			return nil, nil
		end

		if json_response == nil then
			logger.err("KoboApi: error checking the activation's status. The response is not JSON.")
			return nil, nil
		end

		if json_response["Status"] == "Complete" then
			-- RedirectUrl looks like this:
			-- kobo://UserAuthenticated?returnUrl=https%3A%2F%2Fwww.kobo.com%2Fww%2Fen%2F&userKey=...&userId=...&email=...
			local redirect_url = json_response["RedirectUrl"]
			local parsed = socketurl.parse(redirect_url)
			local parsed_queries = parse_query_string(parsed.query)
			if parsed_queries["userId"] == nil and #parsed_queries["userId"] ~= 1 then
				logger.err("KoboApi: the redirect URL does not contain the user ID.")
				return nil, nil
			end
			if parsed_queries["userKey"] == nil and #parsed_queries["userKey"] ~= 1 then
				logger.err("KoboApi: the redirect URL does not contain the user key.")
				return nil, nil
			end
			return parsed_queries["userId"][1], parsed_queries["userKey"][1]
		end

		ffiUtil.sleep(5)
	end
end

function KoboApi:activateOnWeb()
	KoboApiState.access_token = ""
	KoboApiState.device_id = generateRandomHexDigitString(64)
	KoboApiState.library_sync_token = ""
	KoboApiState.refresh_token = ""
	KoboApiState.serial_number = generateRandomHexDigitString(32)
	KoboApiState.user_id = ""
	KoboApiState.user_key = ""

	local query =
	    "?pwspid=" .. util.urlEncode(KOBO_DEFAULT_PLATFORM_ID) ..
		"&wsa=" .. util.urlEncode(KOBO_AFFILIATE) ..
		"&pwsdid=" .. util.urlEncode(KoboApiState.device_id) ..
		"&pwsav=" .. util.urlEncode(KOBO_APPLICATION_VERSION) ..
		"&pwsdm=" .. util.urlEncode(KOBO_DEFAULT_PLATFORM_ID) .. -- In the Android app this is the device model but Nickel sends the platform ID...
		"&pwspos=" .. util.urlEncode(KOBO_DEVICE_OS) ..
		"&pwspov=" .. util.urlEncode(KOBO_DEVICE_OS_VERSION)

    local sink = {}
    local request = {
        url    = API_URL_ACTIVATE .. query,
        method = "GET",
        sink   = ltn12.sink.table(sink),
    }

    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local response_body = table.concat(sink)

	if code ~= 200 then
		logger.err("KoboApi: activation returned with HTTP response code " .. code .. ".")
		return nil, nil
	end

	local activation_check_path = response_body:match('data%-poll%-endpoint="([^"]+)"')
	if activation_check_path == nil then
		logger.err("KoboApi: can't find the activation poll endpoint in the response. The page format might have changed.")
		return nil, nil
	end
	-- NOTE: activation_check_path should be HTML unescaped here but currently it does not contain anything special, so this will work for now.
	local activation_check_url = API_URL_ACTIVATION_CHECK .. activation_check_path

	local activation_code = response_body:match("qrcodegenerator/generate.+%%26code%%3D(%d+)")
	if activation_code == nil then
		logger.err("KoboApi: can't find the activation code in the response. The page format might have changed.")
		return nil, nil
	end

	return activation_check_url, activation_code
end

function KoboApi:authenticateDevice(user_id, user_key)
	if #KoboApiState.device_id == 0 then
		logger.err("KoboApi: device ID is empty, cannot start device authentication.")
		return false
	end
	if #KoboApiState.serial_number == 0 then
		logger.err("KoboApi: serial number is empty, cannot start device authentication.")
		return false
	end
	if #user_id == 0 then
		logger.err("KoboApi: user ID is empty, cannot start device authentication.")
		return false
	end
	if #user_key == 0 then
		logger.err("KoboApi: user key is empty, cannot start device authentication.")
		return false
	end

	local post_data = {
		["AffiliateName"] = KOBO_AFFILIATE,
		["AppVersion"] = KOBO_APPLICATION_VERSION,
		["ClientKey"] = sha2.bin_to_base64(KOBO_DEFAULT_PLATFORM_ID),
		["DeviceId"] = KoboApiState.device_id,
		["PlatformId"] = KOBO_DEFAULT_PLATFORM_ID,
		["SerialNumber"] = KoboApiState.serial_number,
		["UserKey"] = user_key,
	}

	local code, status, json_response = makeJsonPostRequest(API_URL_AUTH_DEVICE, post_data)

	if code ~= 200 then
		logger.err("KoboApi: device authentication returned with HTTP response code " .. code .. ".")
		return false
	end

	if json_response["TokenType"] ~= "Bearer" then
		logger.err("KoboApi: device authentication returned with an unsupported token type: \"" .. json_response["TokenType"] .. "\".")
		return false
	end

	KoboApiState.access_token = json_response["AccessToken"]
	KoboApiState.refresh_token = json_response["RefreshToken"]
	if not areAuthenticationSettingsSet() then
		logger.err("KoboApi: authentication settings are not set after device authentication.")
	end

	KoboApiState.user_id = user_id
	KoboApiState.user_key = json_response["UserKey"]
	return true
end

function KoboApi:getWishlist()
    local items = {}
    local current_page_index = 0

    while true do
		-- 100 is the default if PageSize is not specified
		local url = API_URL_WISHLIST .. "?PageIndex=" .. current_page_index .. "&PageSize=100"

		local code, response = callJsonApi(url, "GET")
		if code ~= 200 then
			logger.err("KoboApi: failed to GET user/wishlist. HTTP response code: " .. code .. ", message: ", getErrorMessageFromApiResponse(response))
			return nil
		end

		for _, item in ipairs(response["Items"]) do
        	table.insert(items, item)
		end

        current_page_index = current_page_index + 1
        if current_page_index >= response["TotalPageCount"] then
            break
        end
    end

    return items
end

function KoboApi:getLibrarySync()
    local items = {}

    while true do
		local additional_headers = nil
		if #KoboApiState.library_sync_token > 0 then
			additional_headers = {
				["x-kobo-synctoken"] = KoboApiState.library_sync_token
			}
		end

		local url = API_URL_LIBRARY_SYNC .. "?Filter=ALL&DownloadUrlFilter=Generic,Android&PrioritizeRecentReads=true"
		local code, response, response_headers = callJsonApi(url, "GET", nil, additional_headers)
		if code ~= 200 then
			logger.err("KoboApi: failed to GET library/sync. HTTP response code: " .. code .. ", message: ", getErrorMessageFromApiResponse(response))
			return nil
		end

		for _, item in ipairs(response) do
        	table.insert(items, item)
		end

		if response_headers ~= nil and response_headers["x-kobo-synctoken"] ~= nil then
			KoboApiState.library_sync_token = response_headers["x-kobo-synctoken"]
		end

		if response_headers == nil or response_headers["x-kobo-sync"] == nil or response_headers["x-kobo-sync"] ~= "continue" then
			break
		end
    end

    return items
end

function KoboApi:download(url, file_path)
	-- We could simply use automatic redirection here and get the content keys separately from
	-- https://storeapi.kobo.com/v1/products/books/{product_id}/access but Nickel also does it this way.
	socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
	local code, headers, status = socket.skip(1, http.request {
		url  = url,
		sink = ltn12.sink.file(io.open(file_path, "w")),
		redirect = false, -- do not handle redirect automatically
	})
	socketutil:reset_timeout()

	-- If this is a redirection then the first response contains the link to the content keys.
	local content_keys = nil
	if code == 302 then -- redirected
		local redirect_url = headers["location"]
		if redirect_url == nil then
			return false, content_keys, code, headers, status
		end

		-- Get the content keys.
		if headers["link"] ~= nil then
			-- Example link format (see the standard at https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Link):
			-- <https://storedownloads.kobo.com/download/key?downloadToken=...>; rel="http://storedownloads.kobo.com/content/relations/keys"
			local content_keys_url = string.gsub(headers["link"], "<([^>]+)>.*", "%1")

			local sink = {}
			local request = {
				url  = content_keys_url,
				sink = ltn12.sink.table(sink),
			}

			socketutil:set_timeout()
			code, headers, status = socket.skip(1, http.request(request))
			socketutil:reset_timeout()
			if code ~= 200 then
				return false, content_keys, code, headers, status
			end
			local json_response = table.concat(sink)
			local _, response = pcall(json.decode, json_response)
			content_keys = response["Keys"]
		end

		socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
		code, headers, status = socket.skip(1, http.request {
			url  = redirect_url,
			sink = ltn12.sink.file(io.open(file_path, "w")),
		})
		socketutil:reset_timeout()
	end

	return code == 200, content_keys, code, headers, status
end

return KoboApi