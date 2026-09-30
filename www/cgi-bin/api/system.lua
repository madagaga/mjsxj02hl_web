-- Routes: GET /system/info, GET/POST /system/autorun, POST /system/reboot,
-- POST /system/factory_reset, POST /system/backup, POST /system/restore,
-- POST /system/bootloader/download, POST /system/bootloader/upgrade,
-- POST /system/firmware
--
-- Same side effects/sizes as the legacy system/*.lp pages. Uploads stream
-- straight to disk via cgi.receive_single_file_upload -- see cgi.lua for why
-- (12 MB firmware image vs. a device with a couple MB of free RAM).

local cgi = require "api.cgi"
local fnc = require "functions"

local M = {}

local AUTORUN_FILE = "/configs/run.sh"
local AUTORUN_DEFAULT = "#!/bin/sh\n\n# Launching the watchdog\nwatchdog.sh &"

local BACKUP_TMP = "/tmp/configs_backup.bin"
local BACKUP_SIZE = 393216 -- 384 KiB
local BOOTLOADER_TMP = "/tmp/bootloader.bin"
local BOOTLOADER_SIZE = 262144 -- 256 KiB
local FIRMWARE_DEST = "/mnt/mmc/demo_hlc6.bin"
local FIRMWARE_SIZE = 12058688

local function reboot_response()
    if os.execute("reboot") then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "To apply changes, you need reboot the device.", { rebooting = false })
    end
end

-- GET /system/info --------------------------------------------------------

function M.get_info(req)
    local version = fnc.file.get_contents("/usr/app/share/.version")
    version = fnc.string.trim(version or "", "\n")
    if fnc.string.is_empty(version) then version = "Unknown" end
    cgi.ok({
        version = version,
        sdcard_present = fnc.file.exists("/dev/mmcblk0"),
    })
end

-- autorun -------------------------------------------------------------------

function M.get_autorun(req)
    local content = fnc.file.get_contents(AUTORUN_FILE)
    content = fnc.string.trim(content or "", "\n")
    if fnc.string.is_empty(content) then content = AUTORUN_DEFAULT end
    cgi.ok({ content = content })
end

-- No restart/reboot here, matching legacy: a run.sh change only takes effect
-- on the next manual reboot.
function M.post_autorun(req)
    local body = req.json or {}
    local content = AUTORUN_DEFAULT
    if body.action == "save" then
        content = body.content or AUTORUN_DEFAULT
    elseif body.action ~= "defaults" then
        return cgi.fail(400, "Unknown action")
    end
    local ok, err = fnc.file.put_contents(AUTORUN_FILE, content .. "\n")
    if not ok then
        return cgi.fail(200, err or "Error saving autorun script!")
    end
    cgi.ok({ content = content })
end

-- reboot / factory reset -----------------------------------------------------

function M.post_reboot(req)
    reboot_response()
end

-- No reboot fallback on failure here: the factory-reset binary itself
-- reboots the device on success, matching the legacy page exactly.
function M.post_factory_reset(req)
    if os.execute("mjsxj02hl --factory-reset") then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "Factory reset error!")
    end
end

-- backup / restore (mtd6, "configs" partition) -------------------------------

function M.post_backup(req)
    if not os.execute("cat /dev/mtdblock6 > " .. BACKUP_TMP) then
        return cgi.fail(200, "Error creating a backup file!")
    end
    cgi.ok({ size = BACKUP_SIZE, download_url = "/tmp/configs_backup.bin" })
end

function M.post_restore(req)
    local upload, err = cgi.receive_single_file_upload(BACKUP_TMP, BACKUP_SIZE + 4096)
    if not upload then
        return cgi.fail(200, err or "No backup file selected!")
    end
    if upload.size ~= BACKUP_SIZE then
        os.remove(BACKUP_TMP)
        return cgi.fail(200, "Invalid size of the backup file!")
    end
    local flashed = fnc.app.flash_partition(BACKUP_TMP, "/dev/mtd6")
    os.remove(BACKUP_TMP)
    if not flashed then
        return cgi.fail(200, "Error restoring a backup copy of the settings!")
    end
    reboot_response()
end

-- bootloader (mtd0) -----------------------------------------------------------

function M.post_bootloader_download(req)
    if not os.execute("cat /dev/mtdblock0 > " .. BOOTLOADER_TMP) then
        return cgi.fail(200, "Error creating a bootloader file!")
    end
    cgi.ok({ size = BOOTLOADER_SIZE, download_url = "/tmp/bootloader.bin" })
end

function M.post_bootloader_upgrade(req)
    local upload, err = cgi.receive_single_file_upload(BOOTLOADER_TMP, BOOTLOADER_SIZE + 4096)
    if not upload then
        return cgi.fail(200, err or "No bootloader file selected!")
    end
    if upload.size ~= BOOTLOADER_SIZE then
        os.remove(BOOTLOADER_TMP)
        return cgi.fail(200, "Invalid size of the bootloader file!")
    end
    local flashed = fnc.app.flash_partition(BOOTLOADER_TMP, "/dev/mtd0")
    os.remove(BOOTLOADER_TMP)
    if not flashed then
        return cgi.fail(200, "Bootloader update error!")
    end
    reboot_response()
end

-- firmware (staged on SD card, no auto-flash/reboot -- matches legacy) -------

function M.post_firmware(req)
    if not fnc.file.exists("/dev/mmcblk0") then
        return cgi.fail(200, "To update the firmware, you need a SD card!")
    end
    local upload, err = cgi.receive_single_file_upload(FIRMWARE_DEST, FIRMWARE_SIZE + 65536)
    if not upload then
        return cgi.fail(200, err or "No firmware file selected!")
    end
    if upload.size ~= FIRMWARE_SIZE then
        os.remove(FIRMWARE_DEST)
        return cgi.fail(200, "Invalid size of the firmware file!")
    end
    -- Deliberately no flash/reboot here: same as legacy, the device's own
    -- bootloader picks this up on the next manual reset-button boot.
    cgi.ok({ staged = true })
end

return M
