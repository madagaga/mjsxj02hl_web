local functions = {
    app = {},
    file = require "functions.file",
    string = require "functions.string",
    table = require "functions.table",
    number = require "functions.number",
}
package.loaded[...] = functions.app

-- File of mjsxj02hl application settings
functions.app.settings_file = function()
    return "/usr/app/share/mjsxj02hl.conf"
end

-- Path of wpa_supplicant.conf file
functions.app.wpa_supplicant_file = function()
    return "/etc/wpa_supplicant.conf"
end

-- Restart mjsxj02hl application
functions.app.restart = function()
    -- Kill application
    os.execute("killall mjsxj02hl")
    -- Waiting for completion
    while os.execute("killall -0 mjsxj02hl") do
        functions.app.sleep(1)
    end
    -- Run application
    return os.execute("mjsxj02hl & sleep 0.1")
end

-- Flashing the selected partition
functions.app.flash_partition = function(filename, partition)
    if functions.string.is_string(filename) and functions.string.is_string(partition) then
        if functions.file.exists(filename) and functions.file.exists(partition) then
            if os.execute("flash_eraseall " .. partition) then
                if os.execute("sync") then
                    if os.execute("flashcp -v " .. filename .. " " .. partition) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Sleep N seconds
functions.app.sleep = function(n)
    if functions.number.is_number(n) then
        if os.execute("sleep " .. n) then
            return true
        end
    end
    return false
end

return functions.app
