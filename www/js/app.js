import { createApp, reactive } from "../vendor/petite-vue.es.js";
import { api } from "./api.js";
import { SETTINGS_SCHEMA, WIFI_SCHEMA, withDefaults, validate, getDefaults } from "./schema.js";

// Section titles: kept separate from schema.js since these are UI labels,
// not part of the data contract with the server.
const SECTION_TITLES = {
    general: "General", osd: "OSD", video: "Video", audio: "Audio",
    speaker: "Speaker", alarm: "Alarm", rtsp: "RTSP server", mqtt: "MQTT",
    night: "Night vision", logger: "Debugging", paths: "Advanced paths",
};
const SETTINGS_SECTIONS = Object.keys(SETTINGS_SCHEMA);

function parseRoute() {
    return location.hash.replace(/^#\/?/, "") || "home";
}

// Root app scope (mounted on #app). Child elements use v-scope="X()" to pull
// in per-page state; those factory functions are looked up on this root
// object by petite-vue's scope chain, no globals needed.
//
// Wrapped in reactive() explicitly (rather than handing createApp a plain
// object) so that `root` -- the same reference every method below closes
// over to reach shared state -- IS the reactive proxy from the start.
// Mutating a plain object's properties directly does not go through a
// Proxy's set trap, so effects/templates depending on it would silently
// never re-run; confirmed by hand (root.authenticated = true after login
// updated the in-memory object but never re-rendered the view) before this
// fix, in a local smoke test against a stub API server.
const root = reactive({
    // --- global/shared state ---
    booting: true,
    authenticated: false,
    username: "",
    route: parseRoute(),
    sectionTitles: SECTION_TITLES,
    settingsSections: SETTINGS_SECTIONS,

    // OpenWrt-style save/apply for settings: editing a section only stages
    // it here (no network call, no restart); the pending-changes bar lets
    // the user apply everything staged across any number of sections in one
    // shot, so mjsxj02hl restarts once per apply instead of once per section.
    // Keys are pre-seeded to `null` (rather than added/removed) so a plain
    // property-value change is what SettingsPage.load() depends on below --
    // simpler to reason about than relying on reactivity around keys that
    // don't exist yet.
    pending: Object.fromEntries(SETTINGS_SECTIONS.map((s) => [s, null])),
    applying: false,
    applyMessage: "",
    applyError: "",
    // Bumped by applyAll()/discardAll() so any mounted SettingsPage's
    // v-effect="load()" (which reads this) re-runs and refreshes its view,
    // even if that page isn't the one whose pending entry just changed.
    reloadTick: 0,

    get pendingSections() {
        return SETTINGS_SECTIONS.filter((s) => root.pending[s]);
    },

    async applyAll() {
        const sections = {};
        for (const s of root.pendingSections) sections[s] = root.pending[s];
        if (!Object.keys(sections).length) return;
        root.applying = true;
        root.applyError = "";
        const res = await api.settingsApply(sections);
        root.applying = false;
        if (!res.ok) { root.applyError = res.error || "Error applying settings"; return; }
        for (const s of Object.keys(sections)) root.pending[s] = null;
        root.applyMessage = "Settings applied successfully!";
        root.reloadTick++;
    },

    discardAll() {
        for (const s of SETTINGS_SECTIONS) root.pending[s] = null;
        root.applyMessage = "";
        root.applyError = "";
        root.reloadTick++;
    },

    navigate(route) {
        location.hash = "#/" + route;
        document.querySelectorAll(".navbar details[open]").forEach((d) => { d.open = false; });
    },

    async init() {
        window.addEventListener("hashchange", () => { root.route = parseRoute(); });
        const res = await api.session();
        root.authenticated = !!res.ok;
        root.username = res.username || "";
        root.booting = false;
    },

    async logout() {
        await api.logout();
        root.authenticated = false;
        root.username = "";
        root.navigate("home");
    },

    // --- login form ---
    Login() {
        return {
            username: "",
            password: "",
            error: "",
            busy: false,
            async submit() {
                this.busy = true;
                this.error = "";
                const res = await api.login(this.username, this.password);
                this.busy = false;
                if (!res.ok) { this.error = res.error || "Login failed"; return; }
                root.authenticated = true;
                root.username = res.username;
                root.navigate("home");
            },
        };
    },

    // --- home / live snapshot ---
    Home() {
        return {
            refreshing: false,
            src: "/cgi-bin/api.lua/image",
            timer: null,
            toggle() {
                this.refreshing = !this.refreshing;
                if (this.refreshing) {
                    this.timer = setInterval(() => {
                        this.src = "/cgi-bin/api.lua/image?random=" + Date.now();
                    }, 1000);
                } else {
                    clearInterval(this.timer);
                }
            },
        };
    },

    // --- generic settings section (one instance per section) ---
    // OpenWrt-style: "Save" only stages the section into root.pending (no
    // network call, no restart); the global bar's "Apply" commits everything
    // staged in one request. "Discard" drops this section's staged edit and
    // reverts the form to the last value the server actually reported.
    SettingsPage(section) {
        const fields = SETTINGS_SCHEMA[section];
        return {
            section,
            fields,
            values: getDefaults(fields),
            serverValues: null,
            message: "",
            error: "",
            async load() {
                void root.reloadTick; // re-run this effect after applyAll()/discardAll()
                const staged = root.pending[section];
                if (staged) {
                    this.values = withDefaults(fields, staged);
                    return;
                }
                this.error = "";
                const res = await api.settingsGet();
                if (!res.ok) { this.error = res.error || "Failed to load settings"; return; }
                this.serverValues = (res.settings || {})[section];
                this.values = withDefaults(fields, this.serverValues);
            },
            save() {
                root.pending[section] = validate(fields, this.values);
                this.message = "Change staged -- click Apply in the bar above to save it.";
                this.error = "";
            },
            resetToDefaults() {
                this.values = getDefaults(fields);
                this.save();
            },
            discard() {
                root.pending[section] = null;
                this.values = withDefaults(fields, this.serverValues);
                this.message = "";
                this.error = "";
            },
        };
    },

    // --- profile ---
    Profile() {
        return {
            username: root.username,
            current_passwd: "",
            new_passwd: "",
            confirm_passwd: "",
            message: "",
            error: "",
            busy: false,
            async save() {
                this.busy = true;
                this.message = "";
                this.error = "";
                const res = await api.changePassword(this.current_passwd, this.new_passwd, this.confirm_passwd);
                this.busy = false;
                if (!res.ok) { this.error = res.error; return; }
                this.message = "Password changed successfully!";
                this.current_passwd = this.new_passwd = this.confirm_passwd = "";
            },
        };
    },

    // --- Wi-Fi ---
    Wifi() {
        return {
            fields: WIFI_SCHEMA,
            values: getDefaults(WIFI_SCHEMA),
            configured: false,
            message: "",
            error: "",
            rebooting: false,
            async load() {
                const res = await api.wifiGet();
                if (!res.ok) { this.error = res.error; return; }
                this.configured = res.configured;
                this.values = withDefaults(WIFI_SCHEMA, res.wifi);
            },
            async save() {
                const clean = validate(WIFI_SCHEMA, this.values);
                const res = await api.wifiSave(clean.ssid, clean.psk, clean.scan_ssid);
                this.applyRebootResult(res);
            },
            async resetToDefaults() {
                const res = await api.wifiDefaults();
                this.applyRebootResult(res);
            },
            applyRebootResult(res) {
                if (res.rebooting) {
                    this.rebooting = true;
                    this.message = "The device is being rebooted...";
                } else {
                    this.error = res.error || "To apply changes, you need reboot the device.";
                }
            },
        };
    },

    // --- system: autorun ---
    SystemAutorun() {
        return {
            content: "",
            message: "",
            error: "",
            async load() {
                const res = await api.autorunGet();
                if (!res.ok) { this.error = res.error; return; }
                this.content = res.content;
            },
            async save() {
                const res = await api.autorunSave(this.content);
                if (!res.ok) { this.error = res.error; return; }
                this.content = res.content;
                this.message = "Autorun script saved successfully!";
            },
            async resetToDefaults() {
                const res = await api.autorunDefaults();
                if (!res.ok) { this.error = res.error; return; }
                this.content = res.content;
                this.message = "Autorun script reset to factory settings!";
            },
        };
    },

    // --- system: reboot / factory reset (same confirm-dialog shape) ---
    ConfirmAction(actionFn, prompt) {
        return {
            prompt,
            confirming: false,
            rebooting: false,
            error: "",
            confirm() { this.confirming = true; },
            cancel() { root.navigate("home"); },
            async proceed() {
                const res = await actionFn();
                if (res.rebooting) {
                    this.rebooting = true;
                } else {
                    this.error = res.error || "Error!";
                }
            },
        };
    },
    SystemReboot() { return root.ConfirmAction(api.reboot, "Do you want to reboot device?"); },
    SystemFactoryReset() { return root.ConfirmAction(api.factoryReset, "Do you want to reset your device to factory settings?"); },

    // --- system: backup/restore, bootloader, firmware (upload pages) ---
    SystemBackup() {
        return {
            message: "", error: "", downloadUrl: "", progress: 0, busy: false,
            async create() {
                const res = await api.backupCreate();
                if (!res.ok) { this.error = res.error; return; }
                this.downloadUrl = res.download_url;
                this.message = "Backup file was created successfully.";
            },
            async restore(file) {
                this.busy = true; this.error = ""; this.message = "";
                const res = await api.backupRestore(file, (p) => { this.progress = p; });
                this.busy = false;
                if (!res.ok) { this.error = res.error; return; }
                this.message = "Restoring the backup copy of the settings was successful! Rebooting...";
            },
        };
    },
    SystemBootloader() {
        return {
            message: "", error: "", downloadUrl: "", progress: 0, busy: false,
            async download() {
                const res = await api.bootloaderDownload();
                if (!res.ok) { this.error = res.error; return; }
                this.downloadUrl = res.download_url;
                this.message = "Bootloader file was created successfully.";
            },
            async upgrade(file) {
                this.busy = true; this.error = ""; this.message = "";
                const res = await api.bootloaderUpgrade(file, (p) => { this.progress = p; });
                this.busy = false;
                if (!res.ok) { this.error = res.error; return; }
                this.message = "Bootloader is successfully upgraded! Rebooting...";
            },
        };
    },
    SystemFirmware() {
        return {
            message: "", error: "", progress: 0, busy: false,
            sdcardPresent: true,
            async load() {
                const res = await api.systemInfo();
                if (res.ok) this.sdcardPresent = res.sdcard_present;
            },
            async upload(file) {
                this.busy = true; this.error = ""; this.message = "";
                const res = await api.firmwareUpload(file, (p) => { this.progress = p; });
                this.busy = false;
                if (!res.ok) { this.error = res.error; return; }
                this.message = "Firmware staged on the SD card. Turn off the device, hold the reset button, "
                    + "wait for the white LED, and the device will reboot automatically into flashing mode.";
            },
        };
    },
});

createApp(root).mount("#app");
root.init();
