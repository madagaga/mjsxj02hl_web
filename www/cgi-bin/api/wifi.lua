-- Routes: GET /wifi, POST /wifi
-- Same behavior as legacy initial.lp/Wi-Fi.lp: write or delete
-- /etc/wpa_supplicant.conf, then unconditionally reboot. No auth required
-- when the file doesn't exist yet (first-boot wizard) -- see router.lua.

local cgi = require "api.cgi"
local fnc = require "functions"

local M = {}

local DEFAULT_SCAN_SSID = 1

function M.get_wifi(req)
    local wpa_file = fnc.app.wpa_supplicant_file()
    local current = { scan_ssid = DEFAULT_SCAN_SSID, ssid = "" }
    if fnc.file.is_file(wpa_file) then
        local content = fnc.file.read_wpa_supplicant(wpa_file)
        local network = content and content.network or {}
        current.scan_ssid = network.scan_ssid or DEFAULT_SCAN_SSID
        current.ssid = network.ssid or ""
    end
    -- never return psk
    cgi.ok({ wifi = current, configured = fnc.file.is_file(wpa_file) })
end

function M.post_wifi(req)
    local body = req.json or {}
    local wpa_file = fnc.app.wpa_supplicant_file()

    if body.action == "defaults" then
        os.remove(wpa_file)
    elseif body.action == "save" then
        local scan_ssid = body.scan_ssid
        if scan_ssid ~= 0 and scan_ssid ~= 1 then scan_ssid = DEFAULT_SCAN_SSID end
        local settings = {
            network = {
                scan_ssid = scan_ssid,
                ssid = body.ssid or "",
                psk = body.psk or "",
            },
        }
        local ok, err = fnc.file.save_wpa_supplicant(wpa_file, settings)
        if not ok then
            return cgi.fail(200, err or "Error saving Wi-Fi configuration!")
        end
    else
        return cgi.fail(400, "Unknown action")
    end

    if os.execute("reboot") then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "To apply changes, you need reboot the device.", { rebooting = false })
    end
end

return M
