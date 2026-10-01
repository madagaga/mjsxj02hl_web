local functions = {
    app = {},
    file = require "functions.file",
    string = require "functions.string",
    table = require "functions.table",
    number = require "functions.number",
}
package.loaded[...] = functions.app

local paths = require "paths"

-- File of mjsxj02hl application settings
functions.app.settings_file = function()
    return paths.app_conf
end

-- Path of wpa_supplicant.conf file
functions.app.wpa_supplicant_file = function()
    return paths.wpa_supplicant_conf
end

-- Restart mjsxj02hl application
functions.app.restart = function()
    -- Kill application
    os.execute(paths.killall .. " mjsxj02hl")
    -- Waiting for completion
    while os.execute(paths.killall .. " -0 mjsxj02hl") do
        functions.app.sleep(1)
    end
    -- Run application
    return os.execute(paths.mjsxj02hl .. " & " .. paths.sleep .. " 0.1")
end

-- Flashing the selected partition
functions.app.flash_partition = function(filename, partition)
    if functions.string.is_string(filename) and functions.string.is_string(partition) then
        if functions.file.exists(filename) and functions.file.exists(partition) then
            if os.execute(paths.flash_eraseall .. " " .. partition) then
                if os.execute(paths.sync) then
                    if os.execute(paths.flashcp .. " -v " .. filename .. " " .. partition) then
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
        if os.execute(paths.sleep .. " " .. n) then
            return true
        end
    end
    return false
end

return functions.app
