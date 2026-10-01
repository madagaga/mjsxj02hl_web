-- Routes: GET /settings, POST /settings (bulk apply)
--
-- The client stages edits across any number of sections locally (OpenWrt-
-- style save/apply, see PROGRESS.md) and sends them all in one POST /settings
-- call, so the device restarts mjsxj02hl at most once per apply instead of
-- once per section -- avoids stacking up needless restarts when the user is
-- tweaking several settings pages before applying.
--
-- Generic INI<->JSON pass-through. All validation/defaults/clamping lives in
-- the client (www/app/js/schema.js, mirroring mjsxj02hl_application/configs.h)
-- -- see PROGRESS.md "Décisions actées". The server does not know about
-- individual field names, types or ranges; it only knows the "timezone" and
-- "action" special cases below because those aren't part of the INI file.

local cgi = require "api.cgi"
local fnc = require "functions"
local lip = require "LIP"
local paths = require "paths"

local M = {}

local TZ_DEFAULT = "UTC-3"

local function read_timezone()
    local content = fnc.file.get_contents(paths.timezone_file)
    content = fnc.string.trim(content or "", "\n")
    if fnc.string.is_empty(content) then return TZ_DEFAULT end
    return content
end

-- LIP.load() asserts the file exists; on a fresh device the settings file
-- may not exist yet, in which case we just start from an empty table (the
-- client fills in defaults for whatever section it's displaying).
local function load_settings()
    local settings_file = fnc.app.settings_file()
    if not fnc.file.is_file(settings_file) then return {} end
    return lip.load(settings_file) or {}
end

function M.get_settings(req, username)
    local settings = load_settings()
    settings.general = settings.general or {}
    settings.general.timezone = read_timezone()
    cgi.ok({ settings = settings })
end

-- body: { sections: { <name>: {...fields...}, ... } } -- one or more sections
-- at once. Writes them all into the INI, then restarts mjsxj02hl exactly once.
function M.apply(req, username)
    local body = req.json or {}
    local sections = body.sections
    if not sections or not next(sections) then
        return cgi.fail(400, "No sections to apply")
    end

    local settings = load_settings()
    local changed = {}

    for section, section_data in pairs(sections) do
        local clean = {}
        for k, v in pairs(section_data) do
            if k ~= "timezone" then clean[k] = v end
        end
        settings[section] = clean
        changed[section] = clean

        -- timezone lives in its own file, not the INI, only relevant to "general"
        if section == "general" and section_data.timezone ~= nil then
            local ok = fnc.file.put_contents(paths.timezone_file, tostring(section_data.timezone) .. "\n")
            if not ok then
                return cgi.fail(500, "Error writing timezone file!")
            end
        end
    end

    lip.save(fnc.app.settings_file(), settings)

    if not fnc.app.restart() then
        return cgi.fail(200, "Error restarting the MJSXJ02HL application! Please reboot your device manually.", { settings = changed })
    end
    cgi.ok({ settings = changed })
end

return M
