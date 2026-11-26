# Privacy Policy

PingTools Network Utilities has no accounts, no advertising and no analytics SDKs. The app does not collect, store or transmit personal data to the project maintainers.

## Data processed on the device

- Recent tool inputs (hostnames, IP addresses, ports), saved Wake-on-LAN devices, the selected language and the appearance theme are stored locally in app-private storage. They never leave the device and are removed when you clear the app's data.
- Network results (ping replies, routes, scan results) are displayed in memory and are not persisted.

## Third-party network requests

The app makes network requests only when a feature needs them:

| Feature | Destination | Purpose |
| --- | --- | --- |
| Public IP / Geo Ping | `ipwho.is`, `ipapi.co` (fallback) | Resolve the public IP and its city-level location, ISP and ASN. These services receive the request IP address as part of any HTTP request. |
| WHOIS | IANA and registry WHOIS servers on TCP port 43 | Look up domain/IP registration records. |
| DNS Lookup | The resolver you select (or the system resolver) | Perform the DNS query you requested. |
| HTTP Inspector | The URL you enter | Read HTTP status and headers. |
| Ping, Traceroute, Port/Subnet scan | The host you enter | Perform the network measurement you requested. |
| Update check / download | `api.github.com`, `github.com` | Read the latest release metadata and, only after you tap Download, fetch the APK and its SHA-256 checksum. |

The maintainers do not operate any server and receive no data from these requests.

## Permissions

- **Internet / network state**: required for all network tools and the optional update check.
- **Wi-Fi state and nearby Wi-Fi devices / location**: used only to display the connected Wi-Fi SSID, BSSID and signal details. Location/nearby-Wi-Fi access is requested at runtime and can be denied; the rest of the app still works.
- **Install unknown apps**: used only when you choose to install an update. Android requires you to grant this per-app permission in system settings; the app opens that screen for you and never installs anything silently.

## Contact

Open an issue at <https://github.com/pinchiu/pingtools-network-utilities/issues>.
