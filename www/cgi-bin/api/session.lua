-- Session/auth: replaces cgilua.authentication.
-- Same underlying checks as the legacy app (passwd file + DES crypt, key
-- derived from wpa_supplicant.conf so a Wi-Fi change invalidates sessions),
-- but implemented directly instead of through CGILua.

local fnc = require "functions"
local md5 = require "md5"
local ldes = require "ldes"
local paths = require "paths"

local session = {}

local COOKIE_NAME = "session"

-- Same derivation as legacy auth.lua: hash of the wpa_supplicant.conf
-- contents. Changing Wi-Fi settings invalidates all existing sessions.
local function crypto_key()
    local content = fnc.file.get_contents(fnc.app.wpa_supplicant_file())
    return md5.sumhexa(content or "")
end

-- Checks username/password against /etc/passwd (same parsing/crypt as legacy).
-- Returns true, or false + human-readable error message.
function session.check_password(username, password)
    if fnc.string.is_empty(username) then return false, "Please, enter your username!" end
    if fnc.string.is_empty(password) then return false, "Please, enter your password!" end
    local file = io.open(paths.passwd_file, "r")
    if not file then return false, "Can't open file " .. paths.passwd_file .. "!" end
    for line in file:lines() do
        local parts = fnc.string.split(line, ":")
        if parts[1] == username then
            local hash = parts[2] or ""
            local salt = hash:sub(1, 2)
            file:close()
            if hash ~= "" and ldes.crypt(password, salt) == hash then
                return true
            end
            return false, "Wrong user/password combination!"
        end
    end
    file:close()
    return false, "Wrong user/password combination!"
end

-- Cookie is "<username>.<signature>", signature = md5(username .. key).
-- Not cryptographic-grade, but matches the trust model of the legacy
-- CGILua session (single-user LAN device, not a hardened multi-tenant service).
local function sign(username, key)
    return md5.sumhexa(username .. ":" .. key)
end

function session.issue(username)
    local token = username .. "." .. sign(username, crypto_key())
    return token
end

-- Returns the authenticated username for this request, or nil.
function session.username_from_cookie(cookie_value)
    if not cookie_value or cookie_value == "" then return nil end
    local username, signature = cookie_value:match("^(.*)%.([^.]+)$")
    if not username then return nil end
    if signature ~= sign(username, crypto_key()) then return nil end
    return username
end

function session.cookie_name()
    return COOKIE_NAME
end

return session
