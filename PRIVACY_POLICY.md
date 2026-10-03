# Privacy Policy

**Yala** (personal fork: [GiridharSalana/yala](https://github.com/GiridharSalana/yala))  
Last updated: October 03, 2026

I am committed to protecting your privacy. This Privacy Policy explains how Yala ("App") handles your information when you use the App to manage your OpenWrt/LuCI routers. This repository builds the app for **personal installation from GitHub Releases only** (not distributed on app stores).

---

## 1. Local Network Data & Local-First Architecture

### a. Local Router Credentials & Configuration Data

- The App requires your router's IP address, port, username, and password to establish direct connections with your OpenWrt router on your local Wi-Fi or VPN network.
- All router credentials are encrypted and stored locally on your device using hardware-backed secure storage (via `flutter_secure_storage` / KeyStore).
- Credentials and network layout data are used **exclusively** for direct HTTP/HTTPS and JSON-RPC communication between your mobile device and your OpenWrt router.
- I do **not** collect, transmit, upload, or store your router credentials, IP addresses, network topology, or router configurations on any external server or developer database.

### b. Local Network Access Permission

- To discover, monitor, and manage OpenWrt routers on modern Android versions (Android 15+ / API 35+ / API 37), the App requests the `ACCESS_LOCAL_NETWORK` runtime permission.
- This permission is used strictly to establish socket and HTTP/HTTPS connections to local gateway IP addresses (such as `192.168.1.1` or `10.0.0.1`).

---

## 2. Personal GitHub Builds & Third-Party Services

- **100% Free & Ad-Free**: Contains zero advertisements, does not collect Advertising IDs (`AD_ID`), and does not integrate third-party ad networks.
- **No In-App Purchases**: Fully open-source under the GNU General Public License v3.0 (GPLv3) with unlimited router profiles.
- **Zero Telemetry or Analytics**: Contains no background tracking, crash telemetry, or third-party analytics SDKs.
- **No store distribution**: This fork is not published on Google Play, F-Droid, or similar channels.

---

## 3. Data Sharing and Disclosure

- **Zero Router Data Sharing**: Router passwords, IP addresses, UCI configurations, and connected device logs are **never shared** with any third party.
- **Zero Third-Party SDKs**: No analytics SDKs, advertising networks, or third-party data brokers are integrated into the App.

---

## 4. Security

- Router passwords and session tokens (`sysauth`) remain stored securely in device hardware-backed storage.
- The App supports HTTPS protocol connections, custom ports, and SSL verification options to secure local network and VPN traffic.

---

## 5. Children's Privacy (Age 3+ Compliance)

- **Rated Age 3+ (Suitable for All Ages)**: Yala is listed and rated **Age 3+** on the Google Play Store, making it suitable for users of all ages, including children under 13.
- **Zero Personal Data Collection**: The App operates with a local-first architecture and does not collect, store, or transmit any personal information, personal identifiers, device IDs, location data, or network details from children or any other users.
- **Ad-Free & Family Safe**: The App displays zero advertisements and includes no analytics or user tracking, providing a safe, privacy-focused experience for all family members.

---

## 6. Play Console Data Safety Compliance

This Privacy Policy matches the declarations in the Google Play Console Data Safety form:

- **Local Data Only**: Router credentials and network data remain strictly on the user's local device.
- **100% Ad-Free**: No Advertising IDs (`AD_ID`) or ad tracking metrics are collected or processed.
- **Zero In-App Purchases**: No billing data or payment metrics are collected.

---

## 7. Contact & Official Policy Links

If you have questions, concerns, or requests regarding this Privacy Policy, please contact me:

- **Privacy Inquiries**: <yala+privacy@nightcode.co.in>
- **General Support**: <yala+support@nightcode.co.in>
- **Website Privacy Policy**: [https://nightcode.co.in/privacy-policy.html](https://nightcode.co.in/privacy-policy.html)
- **Terms & Conditions**: [https://nightcode.co.in/terms.html](https://nightcode.co.in/terms.html)
- **GitHub Repository**: [https://github.com/GiridharSalana/yala](https://github.com/GiridharSalana/yala)
