# Yala

<div align="center">
  <img src="assets/images/app_logo_transparent.png" width="120" alt="Yala logo" />
  <h2>OpenWrt & LuCI router manager</h2>

  <p>
    <strong>Personal Android fork</strong> maintained by
    <a href="https://github.com/GiridharSalana">@GiridharSalana</a>.
    Based on <a href="https://github.com/nightcodex7/yala">nightcodex7/yala</a>
    (GPL-3.0). Install signed APKs from
    <a href="https://github.com/GiridharSalana/yala/releases">GitHub Releases</a>
    — not on Play Store or F-Droid.
  </p>

  [![Release](https://img.shields.io/github/v/release/GiridharSalana/yala?style=for-the-badge&logo=github&label=Release)](https://github.com/GiridharSalana/yala/releases/latest)
  [![Downloads](https://img.shields.io/github/downloads/GiridharSalana/yala/total.svg?style=for-the-badge&logo=github&color=blue&label=Downloads)](https://github.com/GiridharSalana/yala/releases)
  [![CI](https://img.shields.io/github/actions/workflow/status/GiridharSalana/yala/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/GiridharSalana/yala/actions/workflows/ci.yml)
  [![Android](https://img.shields.io/badge/Android-8.0%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/GiridharSalana/yala/releases/latest)
  [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](LICENSE)
  [![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07--25.x-1589F0?style=for-the-badge&logo=openwrt&logoColor=white)](https://openwrt.org)

  <br><br>

  <a href="https://github.com/GiridharSalana/yala/releases/latest">
    <img src="store-badges/github.webp" alt="Download latest APK on GitHub Releases" height="60" />
  </a>

  <p><sub>Upstream project &amp; iOS builds:
  <a href="https://github.com/nightcodex7/yala">nightcodex7/yala</a></sub></p>

  <br>

  <h3>Dashboard Preview (Light & Dark Theme)</h3>
  <p>
    <img src="assets/screenshots/1_dashboard-light.jpeg" width="340" alt="Dashboard Light Mode" />
    &nbsp;&nbsp;&nbsp;&nbsp;
    <img src="assets/screenshots/2_dashboard-dark.jpeg" width="340" alt="Dashboard Dark Mode" />
  </p>
</div>

<br>

**Yala** is an open-source mobile client for managing OpenWrt routers. It connects directly to your router using LuCI JSON-RPC, ubus, and standard OpenWrt system services, allowing you to monitor real-time bandwidth, manage connected devices, run network diagnostics, configure wireless radios, inspect storage, and update packages from your phone or tablet.

### This fork vs upstream

| | **This repo** (`GiridharSalana/yala`) | **Upstream** (`nightcodex7/yala`) |
|---|----------------------------------------|-----------------------------------|
| **Purpose** | Personal builds for my own routers | Community / store releases |
| **Android package** | `com.giridharsalana.yala` | Upstream application ID |
| **Install** | [GitHub Releases](https://github.com/GiridharSalana/yala/releases) (CI-signed APK) | GitHub, F-Droid, Play Store, etc. |
| **Extras here** | Splash auto-login, wireless tab badge, fork branding & update checks | Canonical feature set |

> [!IMPORTANT]
> Bug reports and feature ideas for **Yala itself** are best filed on [nightcodex7/yala](https://github.com/nightcodex7/yala/issues). Use this repo for fork-specific build or packaging issues only.

---

## Supported Devices & Scope

**What I build and install from this repo:** Android phones and tablets (Android 8.0+), including Chromebooks via the Android runtime.

The codebase still includes iOS targets from upstream, but **this fork does not publish iOS IPAs**. For iOS beta builds, use [upstream releases](https://github.com/nightcodex7/yala/releases).

- **Smartphones & tablets:** Responsive layouts for phones, tablets, and foldables.
- **Chromebooks:** Supported through the ChromeOS Android runtime.

> [!NOTE]
> Native desktop OS builds (Windows, macOS, Linux) are out of scope; ChromeOS Android apps are supported.

---

## Key Features

### Multi-Router Management & Secure Vault

- **Multiple Router Profiles:** Save and switch between multiple OpenWrt routers with isolated credentials.
- **Hardware-Backed Vault:** Router IP addresses, credentials, and session tokens are encrypted locally using native secure storage (`flutter_secure_storage` with Android KeyStore and iOS Keychain).
- **Resilient Authentication Stack:** Automatic fallback chain supporting LuCI JSON-RPC (`/cgi-bin/luci/rpc/auth`), ubus JSON-RPC (`session.login`), and redirect-aware CGI form authentication (`sysauth` cookies and `stok` tokens).
- **HTTPS & Custom Ports:** Connect over HTTP or HTTPS with custom port configurations and optional self-signed SSL certificate acceptance for local home networks.

### Network Diagnostics Suite

- **Router-Side Ping:** Send ICMP ECHO_REQUEST packets directly from the router to any target IP or hostname with packet count selection, IPv6 toggle, and live min/avg/max latency calculation.
- **Visual Traceroute:** Trace network hops from the router with customizable hop limits and IPv6 support.
- **DNS Lookup / NSLookup:** Test domain name resolution against default upstream resolvers or custom DNS servers.
- **Routes, ARP & Conntrack:** Inspect kernel routing tables, active ARP neighbor caches, and live network connection tracking entries.
- **One-Tap Diagnostic Export:** Generate and copy clean, formatted diagnostic summaries for easy troubleshooting and sharing.

### Dashboard & Real-Time Vitals

- **Animated Gauges:** Live visual gauges for CPU load, RAM usage, Swap space, and flash root (`/`) filesystem capacity.
- **Real-Time Throughput Graph:** Smooth live chart displaying router network transfer rates (Rx/Tx) with customizable polling intervals.
- **Interface Status Cards:** Overview cards for WAN, LAN, and WWAN showing IP addresses, MACs, protocols, and WAN public IP verification.
- **Quick Actions:** Instant shortcuts to reboot the router, access network diagnostics, or inspect connected clients.

### Connected Clients & Lease Management

- **Unified Client List:** Merges active DHCP leases, ARP neighbor entries, and wireless stations into a single clear view.
- **Device Details:** Displays hostname, assigned IP, MAC address, vendor OUI lookup, connected SSID, and radio band badges.
- **IPv6 Management:** Cleanly displays deduplicated IPv6 address lists with expandable views for multiple private or link-local addresses.
- **Static DHCP Leases:** View, add, edit, and delete static IP reservations with immediate router synchronization.

### Wireless Networks & Guest Wi-Fi

- **Multi-Band Monitoring:** Monitor 2.4 GHz, 5 GHz, and 6 GHz radios with channel, frequency, transmit power, and channel width details.
- **Connected Stations:** Live station list per radio showing connected devices, signal strength (dBm), and bitrate metrics.
- **Wi-Fi Access Control:** Enforce MAC address allowlists or denylists with direct router UCI synchronization.
- **One-Click Guest Wi-Fi:** Provision guest Wi-Fi SSIDs with automatic AP client isolation (`ap_isolate=1`) and dedicated firewall zone isolation.
- **Wi-Fi QR Code Sharing:** Generate on-screen QR codes to help family and visitors connect without typing passwords.

### Dual Package Managers (OPKG & APK)

- **Smart Engine Detection:** Automatically detects and switches between `opkg` (OpenWrt 19.07–23.05) and modern `apk` (OpenWrt 24.10+ and 25.x snapshots).
- **Package Management:** Search repository feeds, update package lists, and install or remove packages directly.
- **LuCI App Companion Finder:** Discover, install, and manage installed vs available LuCI web extension modules (`luci-app-*`).

### Parental Controls & Timed Access

- **Device Profiling:** Group household devices under customizable profiles.
- **Automated Access Windows:** Enforce firewall blocking rules during scheduled restriction hours (such as study or bedtime) and restore access automatically.
- **Domain Filtering & Overrides:** Filter specific domains per profile or toggle instant unrestricted bypass overrides when needed.

### System Services, Cron & Dynamic DNS (DDNS)

- **Services Control:** View active `procd` daemons and `/etc/init.d/` startup scripts; start, stop, restart, enable, or disable services remotely.
- **Cron Scheduler:** View, add, edit, or delete scheduled crontab jobs (`/etc/crontabs/root`).
- **Dynamic DNS:** Monitor DDNS sync status, trigger forced IP updates, and view service status.
- **Optional SSH Service:** Connect via SSH for advanced router maintenance and SoC thermal sensor monitoring.

### Storage, Partitions & Backup/Restore

- **Storage Breakdown:** Inspect disk space usage across root `/`, `/overlay`, `/tmp`, and mounted external USB drives.
- **Pre-Restore Validation:** Validates gzip headers (`0x1F 0x8B`) and `tar` archive structures before uploading to prevent corrupt backup restores.
- **Preserved File Viewer:** Inspect files marked for retention during sysupgrade operations (`sysupgrade -l`).
- **MTD Partition Dumper:** Save binary `mtdblock` partition images directly from `/proc/mtd`.
- **System Maintenance:** Trigger remote system reboot or clean factory reset (`firstboot -y`).

### Safety Guardrails & Atomic Rollbacks

- **Self-Device Guard:** Automatically detects the managing phone's local IP and MAC address to prevent accidental self-lockouts during access rule changes.
- **Atomic UCI Rollback:** Automatically executes `uci revert` across target configuration files if an intermediate multi-step RPC request fails.

### Adaptive Design, Theming & Localization

- **Material 3 & Material You:** Dynamic wallpaper-extracted color palettes on supported Android devices, along with the signature Yala Amber theme.
- **Theme Modes:** Full Light and Dark mode support.
- **Localization:** Available in English, German, Spanish, French, Indonesian, Portuguese, Brazilian Portuguese, Russian, and Chinese.
- **Tablet & Foldable Optimization:** Responsive two-column and three-column layouts designed for tablets, foldables, and Chromebooks.

---

## Screenshots

<div align="center">
  <p><b>Explore full resolution screenshots of Yala features:</b></p>
</div>

<table>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Login Screen</b><br/><br/>
      <img src="assets/screenshots/3_login_page.jpeg" width="165" height="350" alt="Login Screen"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Dashboard (Light)</b><br/><br/>
      <img src="assets/screenshots/1_dashboard-light.jpeg" width="165" height="350" alt="Dashboard Light Mode"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Dashboard (Dark)</b><br/><br/>
      <img src="assets/screenshots/2_dashboard-dark.jpeg" width="165" height="350" alt="Dashboard Dark Mode"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>System Vitals</b><br/><br/>
      <img src="assets/screenshots/4_dashboard-2.jpeg" width="165" height="350" alt="System Vitals"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Network Cards</b><br/><br/>
      <img src="assets/screenshots/5_dashboard-3.jpeg" width="165" height="350" alt="Network Cards"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Connected Clients</b><br/><br/>
      <img src="assets/screenshots/6_clients.jpeg" width="165" height="350" alt="Connected Clients"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Interfaces</b><br/><br/>
      <img src="assets/screenshots/7_interfaces.jpeg" width="165" height="350" alt="Interfaces"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Interface Details</b><br/><br/>
      <img src="assets/screenshots/8_interfaces-1.jpeg" width="165" height="350" alt="Interface Details"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Wireless Radios</b><br/><br/>
      <img src="assets/screenshots/9_wireless.jpeg" width="165" height="350" alt="Wireless Radios"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>System Info</b><br/><br/>
      <img src="assets/screenshots/10_system.jpeg" width="165" height="350" alt="System Info"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Storage Monitor</b><br/><br/>
      <img src="assets/screenshots/11_storage.jpeg" width="165" height="350" alt="Storage Monitor"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Real-Time Charts</b><br/><br/>
      <img src="assets/screenshots/12_realtime_charts.jpeg" width="165" height="350" alt="Real-Time Charts"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>DHCP & DNS</b><br/><br/>
      <img src="assets/screenshots/13_dhcp_dns.jpeg" width="165" height="350" alt="DHCP & DNS"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Firewall Rules</b><br/><br/>
      <img src="assets/screenshots/14_firewall.jpeg" width="165" height="350" alt="Firewall Rules"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Port Forwarding</b><br/><br/>
      <img src="assets/screenshots/15_firewall-1.jpeg" width="165" height="350" alt="Port Forwarding"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Services & System</b><br/><br/>
      <img src="assets/screenshots/16_services_system.jpeg" width="165" height="350" alt="Services & System"/>
    </td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top">
      <b>Parental Controls</b><br/><br/>
      <img src="assets/screenshots/17_parental_controls.jpeg" width="165" height="350" alt="Parental Controls"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Parental Rules</b><br/><br/>
      <img src="assets/screenshots/18_parental_controls-1.jpeg" width="165" height="350" alt="Parental Rules"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Settings (PlayStore)</b><br/><br/>
      <img src="assets/screenshots/20-settings-playstore.jpeg" width="165" height="350" alt="Settings PlayStore"/>
    </td>
    <td width="25%" align="center" valign="top">
      <b>Settings (Community)</b><br/><br/>
      <img src="assets/screenshots/20-settings-community.jpeg" width="165" height="350" alt="Settings Community"/>
    </td>
  </tr>
  <tr>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Tools & More Menu</b><br/><br/>
      <img src="assets/screenshots/21-more.jpeg" width="165" height="350" alt="Tools & More Menu"/>
    </td>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Network Diagnostics</b><br/><br/>
      <img src="assets/screenshots/19_diagnostic.jpeg" width="165" height="350" alt="Network Diagnostics"/>
    </td>
  </tr>
  <tr>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>Package Manager (Tablet)</b><br/><br/>
      <img src="assets/screenshots/19_packagemanager.png" width="340" style="max-width: 100%; height: auto;" alt="Package Manager Tablet"/>
    </td>
    <td colspan="2" width="50%" align="center" valign="top">
      <b>About & App Info (Tablet)</b><br/><br/>
      <img src="assets/screenshots/22-about.png" width="340" style="max-width: 100%; height: auto;" alt="About & App Info Tablet"/>
    </td>
  </tr>
</table>

<br>

<details>
  <summary><b>Show More Tablet & Large Screen Screenshots (8 Views)</b></summary>
  <br>
  <p>Yala automatically adapts its layout on tablets, iPads, foldables, and Chromebooks to take full advantage of wider screens:</p>
  <table>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Multi-Router Profiles & Quick Switch</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_1.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Login & Profiles"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>Connected Clients & Device Details</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_2.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Connected Clients"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Network Interfaces & DSA Switch Topology</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_3.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Network Interfaces"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>Wireless Overview & Multi-Radio Management</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_4.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Wireless Management"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Device Management & Modules Menu</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_5.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Device Management Menu"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>DHCP & DNS Management</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_6.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet DHCP and DNS"/>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center" valign="top">
        <b>Services, Init Scripts, Cron & Dynamic DNS</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_7.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Services and System"/>
      </td>
      <td width="50%" align="center" valign="top">
        <b>App Settings & Customization</b><br/><br/>
        <img src="assets/screenshots/Tab/tab_8.png" width="480" style="max-width: 100%; height: auto;" alt="Tablet Settings"/>
      </td>
    </tr>
  </table>
</details>

<br>

<div align="center">
  <p><i>Browse <a href="assets/screenshots/">assets/screenshots/</a> to view the full resolution collection of screenshots.</i></p>
</div>

---

## Repository Structure

```
yala/
├── .github/                   # CI & Release workflow (validate + tag releases)
├── android/                   # Android native platform code & signing configs
├── assets/                    # Static app assets
│   ├── icons/                 # App launcher icons
│   ├── images/                # Brand graphics & logos
│   ├── mock/                  # Mock diagnostic data for review modes
│   └── screenshots/           # Full app screenshots (including Tab/ tablet gallery)
├── fastlane/                  # Google Play Store release metadata & changelogs
├── fdroid-metadata/           # F-Droid build metadata
├── ios/                       # iOS/iPadOS platform runner & build configurations
├── lib/                       # Main Flutter codebase
│   ├── config/                # Design tokens, themes, app routes, and constants
│   ├── design/                # LuciTheme, breakpoints, responsive layouts & typography
│   ├── l10n/                  # Multi-language localization resources
│   ├── models/                # Data models (Client, Interface, Router, etc.)
│   ├── modules/               # Feature modules (Diagnostics, Package Manager, Parental Controls, etc.)
│   ├── screens/               # Core screens (Dashboard, Clients, Interfaces, Login, Settings, More)
│   ├── services/              # API communication layer, JSON-RPC client, SSH service, secure vault
│   ├── state/                 # State management engine (Riverpod controllers)
│   ├── utils/                 # Security guardrails, HTTP client managers, platform utilities
│   ├── widgets/               # Reusable UI widgets, animated gauges, throughput charts, topology map
│   └── main.dart              # Application entry point
├── store-badges/              # App store and release download badges
├── test/                      # Unit, widget, and integration test suite
├── pubspec.yaml               # Flutter package specification & dependencies
├── CHANGELOG.md               # Version history & sync logs
├── CONTRIBUTING.md            # Guidelines for open-source contributors
├── LICENSE                    # GNU General Public License v3.0 (GPLv3)
├── PRIVACY_POLICY.md          # Privacy policy disclosure
└── README.md                  # Project documentation
```

---

## Router Requirements & Setup

Yala connects directly to your OpenWrt router over HTTP or HTTPS. To ensure full compatibility with all dashboard and monitoring features, install the standard LuCI and RPC modules on your router.

### For OpenWrt 19.07 to 23.05 (OPKG)

SSH into your router and run:

```bash
opkg update
opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status
/etc/init.d/rpcd restart
```

### For OpenWrt 24.10, 25.x & Snapshots (APK)

OpenWrt 24.10 and newer versions use the `apk` package manager:

```bash
apk update
apk add rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status
/etc/init.d/rpcd restart
```

> [!TIP]
> If your router already has standard LuCI web interface installed, most of these modules (`rpcd-mod-luci`, `luci-mod-status`) are usually already present. Yala automatically detects the available endpoints on your router.

---

## Security & Privacy Highlights

- **Zero Telemetry or Analytics:** No user tracking, no crash telemetry, and no third-party analytics SDKs are bundled into the application.
- **Local Credential Storage:** Router IP addresses, credentials, and session tokens are encrypted locally on your device inside hardware-backed storage (Android KeyStore / iOS Keychain).
- **Self-Device Protection:** Prevents you from accidentally blocking your own phone while configuring firewall rules or MAC filtering.
- **Atomic UCI Rollback:** If a multi-step configuration change fails midway, changes are automatically reverted (`uci revert`) to avoid breaking your router setup.
- **Secure Encrypted Connections:** Supports HTTPS endpoints and custom ports, with an optional self-signed certificate toggle for local subnets.

---

## Building & Running

### Prerequisites

- **Flutter SDK:** 3.47.x (matches [CI](.github/workflows/ci.yml))
- **Dart SDK:** bundled with Flutter
- **JDK:** OpenJDK 21 (CI) or 17+
- **Android Studio / Android SDK:** API 35+ for release builds

### Quick Local Run

```bash
# 1. Clone repository
git clone https://github.com/GiridharSalana/yala.git
cd yala

# 2. Install dependencies
flutter pub get

# 3. Analyze code quality
flutter analyze

# 4. Run test suite
flutter test

# 5. Run application on connected device
flutter run
```

### Building release APKs (community flavor)

```bash
flutter build apk --split-per-abi --release \
  --flavor community \
  --dart-define=FLAVOR=community \
  --dart-define=OFFICIAL_BUILD=true
```

Outputs per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`). CI also builds a universal APK and AAB on release tags.

---

## Continuous Integration & Releases

This is a **personal fork**: builds are for my own devices only. I install APKs from **[GitHub Releases](https://github.com/GiridharSalana/yala/releases)** — not published to Play Store, F-Droid, or any other store.

**GitHub Actions** on this repo:

| Workflow | Trigger | What it does |
|----------|---------|----------------|
| [**CI & Release**](.github/workflows/ci.yml) | PRs & pushes to `main` | Format, analyze, test |
| Same workflow | Push tag `v*` or manual dispatch | Build signed APKs/AAB and attach to [Releases](https://github.com/GiridharSalana/yala/releases) |

Pushes to `main` alone do **not** create a release — tag or run the workflow manually with a version (e.g. `v2.2.5+231`).

**Versioning:**

| Part | Rule |
|------|------|
| **`X.Y.Z`** | Match upstream’s **latest [GitHub release](https://github.com/nightcodex7/yala/releases)** (e.g. **2.2.5**), not unreleased bumps on `main`. |
| **`+N`** | This fork’s Android `versionCode` — **must increase** every APK you ship (e.g. last was `+230` → next `+231`). Independent of upstream’s `+225`. |

Example after syncing upstream **v2.2.5**: `version: 2.2.5+231` in `pubspec.yaml`.

**To create a release:**
1. Set `X.Y.Z` to upstream’s latest release; bump **`+N`** by 1, commit, push `main`.
2. **Tag push (recommended):** `git tag 'v2.2.5+231' && git push origin 'v2.2.5+231'` — tag must match `pubspec.yaml` (Release workflow listens for `v*`).
3. **Manual:** Actions → **CI & Release** → **Run workflow** → set **version** to the same tag (e.g. `v2.2.5+231`).

**GitHub Actions secrets** (repo → Settings → Secrets and variables → Actions):

| Secret | Value |
|--------|--------|
| `ANDROID_KEYSTORE_BASE64` | Base64 of `upload-keystore.jks` (repo root) |
| `ANDROID_KEY_PROPERTIES_BASE64` | Base64 of `android/key.properties` |

Use the same layout as [android/key.properties.example](android/key.properties.example): `storeFile=../upload-keystore.jks` so local builds and CI match.

```bash
# macOS — create or refresh secrets on your fork
gh secret set ANDROID_KEYSTORE_BASE64 -R GiridharSalana/yala < <(base64 -i upload-keystore.jks)
gh secret set ANDROID_KEY_PROPERTIES_BASE64 -R GiridharSalana/yala < <(base64 -i android/key.properties)
```

After a release finishes, download **`app-arm64-v8a-release.apk`** (most phones) or **`app-universal-release.apk`** from the release page.

---

## Contributing

This repository is a **personal fork**, not a second upstream. For changes to Yala features, please contribute to [nightcodex7/yala](https://github.com/nightcodex7/yala) (see their [CONTRIBUTING.md](https://github.com/nightcodex7/yala/blob/main/CONTRIBUTING.md)).

Fork-specific notes (syncing upstream, local builds) are in [CONTRIBUTING.md](CONTRIBUTING.md). Open an [issue](https://github.com/GiridharSalana/yala/issues) here only for problems with **this fork’s** builds, package ID, or CI.

---

## Origin, Attribution & Licensing

> [!IMPORTANT]
> **Yala** is an independent, standalone project originally based on [`cogwheel0/luci-mobile`](https://github.com/cogwheel0/luci-mobile), created and authored by **cogwheel0**.
>
> Since diverging from the original codebase, Yala has been extensively refactored, modernized, and expanded by **@nightcodex7** with new capabilities including dual package managers (`apk` / `opkg`), a complete network diagnostics suite, tablet & foldable responsive layouts, hardware thermal monitoring, atomic rollbacks, and multi-language support.
>
> This fork (`GiridharSalana/yala`) is for **personal use only**: package ID `com.giridharsalana.yala`, builds via GitHub Actions, APKs installed from GitHub Releases. It adds minor UX improvements (auto-login on launch, wireless interface badge).
>
> The complete codebase — including original upstream code and all subsequent modifications — is licensed under the [GNU General Public License v3.0 (GPL-3.0-or-later)](LICENSE).
>
> Sincere thanks to:
> - **cogwheel0** — for creating the original foundation for mobile LuCI management
> - **@nightcodex7** — for extensive refactoring, modernization, and feature expansion

> [!NOTE]
> **Licensing Historical Correction:**  
> Early releases of this project were inadvertently published with an Apache-2.0 identifier. That has since been completely corrected. The project is strictly licensed under GPL-3.0-or-later in accordance with the original project's copyleft terms.

### Copyright

- Original work Copyright (C) 2025–2026 [cogwheel0](https://github.com/cogwheel0).
- Yala modifications Copyright (C) 2026 [@nightcodex7](https://github.com/nightcodex7).
- This fork Copyright (C) 2026 [GiridharSalana](https://github.com/GiridharSalana).

---

## Upstream sync

Track [nightcodex7/yala](https://github.com/nightcodex7/yala) and merge periodically:

```bash
git remote add upstream https://github.com/nightcodex7/yala.git   # once
git fetch upstream
git checkout main && git pull origin main
git merge upstream/main
```

After resolving conflicts, **keep fork identity**: `com.giridharsalana.yala`, [`lib/config/app_config.dart`](lib/config/app_config.dart) (repo URLs & maintainer), [`.github/workflows/ci.yml`](.github/workflows/ci.yml), and splash/login behavior. Set `pubspec.yaml` per the versioning table, run `dart analyze` and `flutter test`, push `main`, and tag `vX.Y.Z+N` to match.

**Quick links:** [Upstream repo](https://github.com/nightcodex7/yala) · [Upstream releases](https://github.com/nightcodex7/yala/releases) · [Privacy policy](PRIVACY_POLICY.md) · [License](LICENSE)