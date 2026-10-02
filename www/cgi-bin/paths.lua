-- Single place for every filesystem path and external-binary name the API
-- layer touches on the device. Centralized specifically so a path/PATH bug
-- (like the two we hit: wrong shebang interpreter, wrong config file path,
-- "mjsxj02hl" not found because its CGI environment's PATH doesn't include
-- /backk/bin) is a one-line fix here instead of a hunt across every file
-- that calls os.execute/io.popen.
--
-- Binaries are given as ABSOLUTE paths wherever we've actually hit a PATH
-- resolution failure for them (currently just mjsxj02hl, confirmed broken:
-- the CGI process's PATH does not include /backk/bin). The rest are left as
-- bare names, resolved via PATH, because busybox applets (cat/killall/sync/
-- reboot/passwd/flash_eraseall/flashcp) have not been observed to fail --
-- but if one does, flip its entry here to an absolute path, same pattern.

local paths = {}

-- Binaries
paths.mjsxj02hl = "/backk/bin/mjsxj02hl" -- confirmed: not on the CGI env's PATH
paths.cat = "cat"
paths.killall = "killall"
paths.sync = "sync"
paths.reboot = "reboot"
paths.passwd = "passwd"
paths.flash_eraseall = "flash_eraseall"
paths.flashcp = "flashcp"
paths.sleep = "sleep"
paths.devmem = "devmem"

-- Config files
paths.app_conf = "/configs/mjsxj02hl.conf" -- confirmed: NOT /usr/app/share/... (that's read-only squashfs)
paths.wpa_supplicant_conf = "/etc/wpa_supplicant.conf"
paths.timezone_file = "/configs/TZ"
paths.autorun_file = "/configs/run.sh"
paths.passwd_file = "/etc/passwd"
paths.version_file = "/usr/app/share/.version"

-- Device nodes (system/backup+restore, system/bootloader)
paths.mtd_configs_block = "/dev/mtdblock6" -- read side (cat ... > backup file)
paths.mtd_configs = "/dev/mtd6"            -- write side (flash_eraseall/flashcp)
paths.mtd_bootloader_block = "/dev/mtdblock0"
paths.mtd_bootloader = "/dev/mtd0"
paths.sdcard_device = "/dev/mmcblk0"

-- /tmp staging files
paths.tmp_image = "/tmp/image.jpg"
paths.tmp_backup = "/tmp/configs_backup.bin"
paths.tmp_bootloader = "/tmp/bootloader.bin"

-- SD card targets
paths.firmware_dest = "/mnt/mmc/demo_hlc6.bin"
-- If this file is present, U-Boot would reflash the BOOTLOADER itself on
-- next boot instead of just kernel+rootfs+app+kback -- the firmware upload
-- flow refuses to proceed if it exists. See PROGRESS.md (cross-session note,
-- 2026-10-01) for the full U-Boot trigger mechanism this guards against.
paths.sdcard_boot_trigger = "/mnt/mmc/demo_boot.bin"

-- U-Boot SD-update trigger register (survives a software `reboot`, not a
-- power cut). Writing 1 to bit0 tells U-Boot to look for demo_hlc6.bin on
-- the SD card at next boot, same as holding the physical reset button.
paths.fw_trigger_register = "0x120f0048"

return paths
