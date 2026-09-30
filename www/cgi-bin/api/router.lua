-- Dispatches "METHOD PATH" to a handler. Replaces app.lua's routing
-- (file-based page resolution) with a small explicit route table, since
-- there's no longer a .lp file per page to resolve.

local cgi = require "api.cgi"
local session = require "api.session"
local fnc = require "functions"

local auth = require "api.auth"
local wifi = require "api.wifi"
local settings = require "api.settings"
local system = require "api.system"
local image = require "api.image"

local router = {}

-- Routes reachable without a session cookie. "wifi" is special-cased below:
-- only actually public before wpa_supplicant.conf exists (first-boot wizard).
local PUBLIC_ROUTES = {
    ["POST /login"] = true,
    ["GET /wifi"] = true,
    ["POST /wifi"] = true,
}

-- Exact-path routes (no parameters).
local ROUTES = {
    ["POST /login"] = function(req, username) return auth.login(req) end,
    ["POST /logout"] = function(req, username) return auth.logout(req) end,
    ["GET /session"] = function(req, username) return auth.get_session(req, username) end,
    ["GET /profile"] = function(req, username) return auth.get_profile(req, username) end,
    ["POST /profile"] = function(req, username) return auth.post_profile(req, username) end,

    ["GET /wifi"] = function(req, username) return wifi.get_wifi(req) end,
    ["POST /wifi"] = function(req, username) return wifi.post_wifi(req) end,

    ["GET /settings"] = function(req, username) return settings.get_settings(req, username) end,
    ["POST /settings"] = function(req, username) return settings.apply(req, username) end,

    ["GET /system/info"] = function(req, username) return system.get_info(req) end,
    ["GET /system/autorun"] = function(req, username) return system.get_autorun(req) end,
    ["POST /system/autorun"] = function(req, username) return system.post_autorun(req) end,
    ["POST /system/reboot"] = function(req, username) return system.post_reboot(req) end,
    ["POST /system/factory_reset"] = function(req, username) return system.post_factory_reset(req) end,
    ["POST /system/backup"] = function(req, username) return system.post_backup(req) end,
    ["POST /system/restore"] = function(req, username) return system.post_restore(req) end,
    ["POST /system/bootloader/download"] = function(req, username) return system.post_bootloader_download(req) end,
    ["POST /system/bootloader/upgrade"] = function(req, username) return system.post_bootloader_upgrade(req) end,
    ["POST /system/firmware"] = function(req, username) return system.post_firmware(req) end,

    ["GET /image"] = function(req, username) return image.get_image(req, username) end,
}

local function split_path(path)
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end
    return segments
end

function router.handle()
    local req = cgi.request()
    local method = req.method
    local segments = split_path(req.path)
    local normalized_path = "/" .. table.concat(segments, "/")
    local key = method .. " " .. normalized_path

    local wifi_configured = fnc.file.is_file(fnc.app.wpa_supplicant_file())
    local is_public = PUBLIC_ROUTES[key] and (segments[1] ~= "wifi" or not wifi_configured)

    local username
    if not is_public then
        username = session.username_from_cookie(req.cookies[session.cookie_name()])
        if not username then
            return cgi.fail(401, "Not authenticated")
        end
    end

    local handler = ROUTES[key]
    if handler then
        return handler(req, username)
    end

    return cgi.fail(404, "Unknown route: " .. key)
end

return router
