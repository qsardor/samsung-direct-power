# Samsung Direct Power

> Hardware-level 0W Direct Power delivery and AMOLED WebUI Governor for Samsung devices.

<p align="left">
  <img src="https://img.shields.io/badge/KernelSU--Next-Module-blue?style=flat-square" height="20"/>
  <img src="https://img.shields.io/badge/Version-v1.0-emerald?style=flat-square" height="20"/>
  <img src="https://img.shields.io/badge/License-MIT-black?style=flat-square" height="20"/>
</p>

<p align="center">
  <img src="docs/dashboard.png" alt="Samsung Direct Power AMOLED WebUI" width="340"/>
</p>

---

## The Problem & Empirical Discovery

Standard Android "slate mode" hacks (`batt_slate_mode=1`) shut off the charger buck converter (`MAX77705_MODE_0_ALL_OFF`), discharging internal battery cells at **-1.77A** during heavy gaming.

**Samsung Direct Power** enforces true hardware power isolation on Samsung Galaxy devices equipped with Maxim PMICs (e.g., MAX77705 / MAX77720):
- **`batt_slate_mode=0`**: Keeps charger buck converter active (`MAX77705_MODE_4_BUCK_ON`).
- **`batt_full_capacity=50`**: Forces kernel charger driver to `SEC_BAT_CHG_MODE_CHARGING_OFF`.
- **Result:** Motherboard runs directly off USB-C input power with **0W net battery cell load** and zero battery heat during extended gaming.

> [!TIP]
> For in-depth circuit analysis, PMIC register states, 15-minute thermal graphs, differential cache benchmarks, and the AI pair-programming anti-regression playbook, read the [Engineering & Architecture Master Report](docs/ARCHITECTURE.md).

---

## 15-Minute Heavy Gaming Benchmark (SM-N986N)

Empirical telemetry measured during continuous high-load *Call of Duty Mobile* gameplay on Samsung Galaxy Note 20 Ultra 5G (Snapdragon 865+ / SM8250 Kona):

| Metric | Direct Power Mode | Normal Fast Charging | Delta / Headroom |
| :--- | :--- | :--- | :--- |
| **Duration** | 15 min continuous | 15 min continuous | Identical load |
| **Start / End Battery %** | **84% → 84% (0% drop)** | 84% → 85% (+1%) | **Zero cell cycle wear** |
| **Net Battery Current** | **-40.7 mA** (~0.16W avg load) | **+120.6 mA** (pulsing to +1740 mA) | **Isolated from battery** |
| **Peak Battery Temp** | **41.0 °C** (Avg: 38.9 °C) | **44.0 °C** (Avg: 41.8 °C) | **-3.0 °C Cooler** |
| **CPU Prime Core Clock** | **3091 MHz (3.09 GHz unthrottled)** | **1977 MHz (Throttled)** | **+1.11 GHz sustained headroom** |
| **Adreno 650 GPU Clock** | **670 MHz (Maximum sustained)** | **441 MHz (Thermal throttling)** | **+229 MHz sustained clock** |

---

## Visual Architecture & Interface

<p align="center">
  <img src="docs/apps.png" width="300" alt="Direct Power Game Library"/>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="docs/logs.png" width="300" alt="Hardware Event Logs Modal"/>
</p>

### Key Capabilities

- **Human-Readable Power Routing:**
  - Replaces cryptic PMIC register states with clean, high-signal diagnostics:
    - **`DIRECT TO SOC`** — Battery isolated (0W load, pure AC supply to board).
    - **`CHARGING`** — Normal fast charging into battery.
    - **`BATTERY ONLY`** — Operating purely on battery cell when unplugged.
- **Dynamic Kernel ADC Voltage Probe:**
  - Dynamically reads real physical input voltage from kernel ADC (`/sys/class/power_supply/battery/vbyp_voltage`) and charging protocol (`PDIC_APDO`, `TA`, `AFC`, `USB`). Zero hardcoded text strings.
- **Samsung One UI Settings Awareness & Notification Guard:**
  - Continuously monitors whether "Fast Charging" or "Super Fast Charging" is toggled OFF in Samsung Battery Settings.
  - Automatically posts a native Android status bar notification and displays an amber WebUI banner with 1-tap deep links directly to Samsung's Battery Settings page (`POWER_USAGE_SUMMARY`). Remains completely silent when Fast Charging is active.
- **Direct Power Game Library (`AppHelper.dex`):**
  - Native 7.4KB DEX executing via `app_process` with heuristic detection of installed games and emulators (Egg NS, Winlator, Mobox, PPSSPP, etc.).
  - Pre-indexed during module installation with instant 0ms WebUI rendering.
  - Integrated filter pills for Games, Enabled, and All Apps with 1-tap manual package entry (`+ Add`).
- **Zero-Binder Sysfs Display State Watchdog:**
  - Reads display power directly from kernel DRM driver (`/sys/class/drm/card0-DSI-1/dpms`) in **0.5ms** (~13x–20x faster than Android `dumpsys power`).
  - Immediately disengages Direct Power and restores full normal charging the moment the screen turns off or locks, preventing unwanted 0W idling on desks.
- **Smart Process Pre-Filtering (0% Idle CPU Overhead):**
  - Inspects `/proc` via fast-path `pidof` before triggering window manager inspection. Skips heavy dumpsys entirely when no whitelisted game is in memory.
- **Adaptive Standby Power Protection:**
  - When the USB-C charger is disconnected, Direct Power automatically disengages and hardware registers return to standard 100% capacity.
- **Dual-Control Architecture (WebUI & Headless CLI):**
  - Designed with parity: Human users enjoy the dark AMOLED WebUI with 1-tap controls and KernelSU Action button, while AI pair-programming agents and automation scripts have dedicated, high-speed CLI access (`directpower json`) and standalone [`directpower.sh`](directpower.sh).
- **Non-Intrusive Modal Logs:**
  - Real-time hardware transition logs in an on-demand modal with 500-line circular buffer and 1-tap clipboard copy.

---

## Quick Start (Installation)

### Prerequisites
- Samsung device running One UI (Snapdragon or Exynos with Maxim MAX77705/MAX77720 PMIC).
- Root access via **KernelSU**, **KernelSU-Next**, or **APatch**.

### Flash via KernelSU-Next Manager
1. Download `Samsung_Direct_Power_v1.0.zip` from [Releases](https://github.com/qsardor/samsung-direct-power/releases).
2. Open KernelSU-Next Manager -> **Modules** -> **Install**.
3. Select the ZIP and flash.
4. Open the module card and tap the **WebUI** button (browser icon).

### Standalone Execution (Zero-Bloat Single-File)
If you prefer not to install any modules, background daemons, or WebUI, you can run [`directpower.sh`](directpower.sh) directly via Termux or ADB with zero dependencies:

```bash
# Instant bare-metal control (Root required)
su -c ./directpower.sh on       # Force Direct Power (0W battery draw)
su -c ./directpower.sh off      # Restore Normal Charging
su -c ./directpower.sh toggle   # 1-Tap Toggle state
su -c ./directpower.sh status   # Instant hardware diagnostics (~1ms)
su -c ./directpower.sh json     # Telemetry JSON for scripts
```

---

## CLI & AI Agent Endpoints (Debugging Only)

> [!NOTE]
> **For End-Users:** You do NOT need the CLI. Your entire experience is **100% WebUI-driven** directly from the KernelSU-Next Manager. Simply tap the WebUI icon to toggle Direct Power, search apps, and turn on Direct Power for whatever games or apps you choose.
>
> **For AI Agents & Automation:** During debugging and pair-programming with AI assistants, the agent cannot operate a human touch screen or browser WebUI as a person does. The CLI binary (`directpower`) is included strictly for AI agent observability, programmatic hardware switches, and high-speed JSON telemetry.

```bash
# Hardware Control
directpower toggle        # 1-Tap toggle Direct Power ON / OFF
directpower on            # Force Direct Power (0W load)
directpower off           # Force Normal Fast Charging
directpower auto          # Engage Smart Governor
directpower status        # Display human-readable hardware diagnostics
directpower json          # High-speed telemetry JSON endpoint (~15ms)

# Daemon Lifecycle
directpower start         # Start background governor daemon
directpower stop          # Stop background governor daemon
directpower restart       # Terminate stale instances and restart daemon

# Whitelist Management
directpower getwhitelist  # List monitored package names
directpower addpkg <pkg>  # Add package to whitelist (pure POSIX fast-path)
directpower delpkg <pkg>  # Remove package from whitelist
directpower refreshapps   # Re-scan installed apps and update cached icons

# Logs
directpower getlogs       # Tail hardware transition logs
directpower clearlogs     # Truncate log buffer
```

---

## Repository Structure

```
.
├── action.sh                 # KernelSU Manager Action Terminal toggle
├── apphelper.dex             # Native Android PackageManager DEX helper (6.3 KB)
├── direct_power_daemon.sh    # 24/7 background governor & thermal/game watchdog
├── directpower.sh            # Standalone zero-bloat single-file CLI tool (0 dependencies)
├── module.prop               # KernelSU module manifest
├── service.sh                # Late-start boot service entrypoint
├── src/
│   └── AppHelper.java        # Source code for Android app & icon extractor
├── system/
│   └── bin/
│       └── directpower       # CLI & JSON API backend
├── webroot/
│   ├── icon.png              # Module emblem
│   ├── index.html            # Dark AMOLED WebUI dashboard (ksu.exec bridge)
│   ├── apps.json             # Cached package metadata
│   └── icons/                # Cached application PNG icons
└── docs/                     # Documentation assets and screenshots
    ├── ARCHITECTURE.md       # Engineering & Architecture Master Report (Physics, Benchmarks, Anti-Regression)
    └── *.png                 # Interface screenshots
```

---

## Hardware Testing & Community Feedback

> [!NOTE]
> During the development and hardware calibration of this module, only the **Samsung Galaxy Note 20 Ultra 5G (SM-N986N, Snapdragon 865+)** was physically available for bare-metal testing.
>
> While the architecture is strictly designed to be universal across Samsung One UI devices (utilizing standard AOSP `app_process` execution, standard `PackageManager` APIs, and universal Samsung battery driver sysfs interfaces), physical testing on other models (e.g., Galaxy S21/S22/S23/S24 series, Z Fold/Flip, or Exynos chipsets) has not yet been conducted in our lab.
>
> If you test this module on other Samsung Galaxy models, please submit feedback, diagnostic logs, or issue reports via [GitHub Issues](https://github.com/qsardor/samsung-direct-power/issues). Validated reports and telemetry will be actively used to upgrade and expand compatibility.

---

## Credits & Attribution

Created by Antigravity & Q.S@RDOR

---

## License

This project is licensed under the [MIT License](LICENSE).
