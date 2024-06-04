--[[

       _       _                                      _           _          _
      | |     | |                                    | |         | |        | |
      | |_ ___| | ___  __ _ _ __ __ _ _ __ ___ ______| |__   ___ | |_ ______| |_   _  __ _
      | __/ _ \ |/ _ \/ _` | '__/ _` | '_ ` _ \______| '_ \ / _ \| __|______| | | | |/ _` |
      | ||  __/ |  __/ (_| | | | (_| | | | | | |     | |_) | (_) | |_       | | |_| | (_| |
       \__\___|_|\___|\__, |_|  \__,_|_| |_| |_|     |_.__/ \___/ \__|      |_|\__,_|\__,_|
                       __/ |
                      |___/

      Version 2.0-0
      Copyright (c) 2017-2024 Matthew Hesketh
      See COPING for details

]] local api = {}
local https = require('ssl.https')
local multipart = require('apps/cloudstorage/telegram-bot-lua/multipart-post')
local ltn12 = require('ltn12')
local json = require('rapidjson')
local logger = require('logger')

local config = { ['endpoint'] = 'https://api.telegram.org/bot' }

function api.configure(token, debug)
    if not token or type(token) ~= 'string' then
        token = nil
    end
    api.debug = debug and true or false
    api.token = assert(token, 'Please specify your bot API token you received from @BotFather!')
    repeat
        api.info = api.get_me()
    until api.info.result
    api.info = api.info.result
    api.info.name = api.info.first_name
    return api
end

function api.request(endpoint, parameters)
    assert(endpoint, 'You must specify an endpoint to make this request to!')
    parameters = parameters or {}
    for k, v in pairs(parameters) do
        parameters[k] = tostring(v)
    end
    if api.debug then
        local output = json.encode(parameters)
        logger.dbg(output)
    end
    parameters = next(parameters) == nil and {''} or parameters
    local response = {}
    local body, boundary = multipart.encode(parameters)
    local success, res = https.request({
        ['url'] = endpoint,
        ['method'] = 'POST',
        ['headers'] = {
            ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
            ['Content-Length'] = #body
        },
        ['source'] = ltn12.source.string(body),
        ['sink'] = ltn12.sink.table(response)
    })
    if not success then
        logger.err('Connection error [' .. res .. ']')
        return false, res
    end
    local jstr = table.concat(response)
    local jdat = json.decode(jstr)
    if not jdat then
        return false, res
    elseif not jdat.ok then
        local output = '\n' .. jdat.description .. ' [' .. jdat.error_code .. ']\n\nPayload: '
        output = output .. json.encode(parameters) .. '\n'
        logger.warn(output)
        return false, jdat
    end
    return jdat, res
end

function api.get_me()
    local success, res = api.request(config.endpoint .. api.token .. '/getMe')
    return success, res
end

function api.log_out()
    local success, res = api.request(config.endpoint .. api.token .. '/logOut')
    return success, res
end

function api.close()
    local success, res = api.request(config.endpoint .. api.token .. '/close')
    return success, res
end

function api.get_file(file_id) -- https://core.telegram.org/bots/api#getfile
    local success, res = api.request(config.endpoint .. api.token .. '/getFile', {
        ['file_id'] = file_id
    })
    return success, res
end


function api.get_updates(timeout, offset, limit, allowed_updates, use_beta_endpoint) -- https://core.telegram.org/bots/api#getupdates
    allowed_updates = type(allowed_updates) == 'table' and json.encode(allowed_updates) or allowed_updates
    local success, res = api.request(config.endpoint .. api.token .. '/getUpdates', {
        ['timeout'] = timeout,
        ['offset'] = offset,
        ['limit'] = limit,
        ['allowed_updates'] = allowed_updates
    })
    return success, res
end


return api
