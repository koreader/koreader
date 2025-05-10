local crypto = require("ffi/crypto")
local ffi = require("ffi")
local sha2 = require "ffi/sha2"
local ZipReader = require "ffi/zipreader"
local ZipWriter = require "ffi/zipwriter"

local KoboDrm = {
}

local function decrypt(content, content_key_base_64, device_id_user_id_key)
    local content_key = sha2.base64_to_bin(content_key_base_64)

    local content_key_cipher = crypto.get_aes_ecb_cipher(#device_id_user_id_key)
    local decrypted_content_key, decrypted_content_key_length = crypto.evp_decrypt(content_key_cipher, content_key, device_id_user_id_key)
    decrypted_content_key = ffi.string(decrypted_content_key, decrypted_content_key_length)

    local content_cipher = crypto.get_aes_ecb_cipher(#decrypted_content_key)
    local decrypted_content, decrypted_content_length = crypto.evp_decrypt(content_cipher, content, decrypted_content_key)
    decrypted_content = crypto.pkcs7_unpad(decrypted_content, decrypted_content_length, crypto.get_cipher_block_size(content_cipher))

    return decrypted_content
end

function KoboDrm:removeKoboDrm(device_id, user_id, content_keys, input_file_path, output_file_path)
    local device_id_user_id = device_id .. user_id
    local key = sha2.sha256(device_id_user_id)
    local device_id_user_id_key = sha2.hex2bin(key.sub(key, 33))

    local zip_reader = ZipReader:new()
    local zip_reader_open_succeeded, _ = zip_reader:open(input_file_path)
    if not zip_reader_open_succeeded then
        return false
    end

    local zip_writer = ZipWriter:new()
    local zip_writer_open_succeeded, _ = zip_writer:open(output_file_path)
    if not zip_writer_open_succeeded then
        zip_reader:close()
        return false
    end

    for _, zip_entry in ipairs(zip_reader.files) do
        local content = zip_reader:read_file(zip_entry)
        local name = zip_entry.file_name:gsub("\\", "/")
        local content_key = content_keys[name]
        if content_key ~= nil then
            content = decrypt(content, content_key, device_id_user_id_key)
            if content == nil then
                zip_reader:close()
                zip_writer:close()
                return false
            end
        end

        zip_writer:add(zip_entry.file_name, content)
    end

    zip_reader:close()
    zip_writer:close()
    return true
end

return KoboDrm
