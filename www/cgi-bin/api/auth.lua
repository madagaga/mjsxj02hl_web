-- Routes: POST /login, POST /logout, GET /session, GET /profile, POST /profile

local cgi = require "api.cgi"
local session = require "api.session"
local fnc = require "functions"

local M = {}

function M.login(req)
    local username = req.json and req.json.username
    local password = req.json and req.json.password
    local ok, err = session.check_password(username, password)
    if not ok then
        return cgi.fail(200, err)
    end
    cgi.set_cookie(session.cookie_name(), session.issue(username))
    cgi.ok({ username = username })
end

function M.logout(req)
    cgi.set_cookie(session.cookie_name(), "", { max_age = 0 })
    cgi.ok()
end

function M.get_session(req, username)
    cgi.ok({ username = username })
end

function M.get_profile(req, username)
    cgi.ok({ username = username })
end

-- Same validation order/messages as the legacy profile.lp, but the actual
-- password change is done without shell string interpolation.
function M.post_profile(req, username)
    local body = req.json or {}
    if fnc.string.is_empty(username) then
        return cgi.fail(200, "Please, enter your username!")
    end
    if fnc.string.is_empty(body.current_passwd) then
        return cgi.fail(200, "Please, enter your current password!")
    end
    local ok, passwd_error = session.check_password(username, body.current_passwd)
    if not ok then
        return cgi.fail(200, "Current password error: " .. passwd_error)
    end
    if fnc.string.is_empty(body.new_passwd) then
        return cgi.fail(200, "Please, enter a new password!")
    end
    if fnc.string.is_empty(body.confirm_passwd) then
        return cgi.fail(200, "Please, confirm a new password!")
    end
    if body.new_passwd ~= body.confirm_passwd then
        return cgi.fail(200, "The entered passwords do not match!")
    end

    -- Same effect as legacy `passwd -a des <user>` but without piping
    -- user-controlled *password* values through a shell string (they go over
    -- stdin instead). `username` still ends up on the popen command line
    -- (io.popen only takes a shell string, no argv form) so it's restricted
    -- to a safe charset first -- it comes from the session cookie, not
    -- directly from this request body, but defense in depth costs nothing.
    if not username:match("^[%w_%-]+$") then
        return cgi.fail(200, "Password change error!")
    end
    local handle = io.popen("passwd -a des " .. username .. " >/dev/null 2>&1", "w")
    if not handle then
        return cgi.fail(200, "Password change error!")
    end
    handle:write(body.new_passwd .. "\n" .. body.confirm_passwd .. "\n")
    local closed_ok = handle:close()
    if not closed_ok then
        return cgi.fail(200, "Password change error!")
    end
    cgi.ok()
end

return M
