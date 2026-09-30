-- Route: GET /image (replaces get_image.cgi)
-- Same command/contract as legacy, but reachable only with a valid session
-- -- the legacy get_image.cgi had no auth check at all (see PROGRESS.md
-- "Décisions actées": fixed, not reproduced as-is).

local cgi = require "api.cgi"
local fnc = require "functions"

local M = {}

local TMP_IMAGE = "/tmp/image.jpg"

function M.get_image(req, username)
    local handle = io.popen("mjsxj02hl --get-image " .. TMP_IMAGE .. " 2>&1")
    local message = handle and handle:read("*a") or ""
    local ok = handle ~= nil and handle:close()

    if ok then
        local data = fnc.file.get_contents(TMP_IMAGE)
        os.remove(TMP_IMAGE)
        cgi.send_raw(200, "image/jpeg", data or "")
    else
        cgi.send_raw(200, "text/html", "<h1>" .. (message or "") .. "</h1>")
    end
end

return M
