# DR-CPanel

**پنل مدیریت تانل و پورت‌فوروارد برای مسیر ایران ↔ خارج — همه‌چیز در یک اسکریپت، بدون وابستگی به هیچ سرویس دیگری.**

<div dir="rtl">

DR-CPanel یک پنل کامل فارسی/انگلیسی است که همه‌ی راه‌های عبور ترافیک بین سرور ایران و سرور خارج را یک‌جا مدیریت می‌کند: تانل رمزنگاری‌شده‌ی WireGuard با ۶ ترنسپورت، تانل GRE با حالت IP-Spoof، موتور Xray (VLESS + Reality)، موتور Backhaul، فوروارد پورت با حجم/انقضا/لینک مصرف، تست‌های اتصال واقعی، مراقب خودکار، ربات تلگرام و پنل وب شیشه‌ای با انیمیشن.

</div>

## ✨ Features

### 🔐 Encrypted tunnels (WireGuard core)
- **6 transports per tunnel** — UDP, TCP, WebSocket, WSS, KCP, QUIC — a gost v3 carrier moves the WireGuard packets through whatever the path allows; switchable live, per tunnel
- **Reverse & Direct** — the kharej dials Iran (no foreign IP needed, one-line join link) or Iran dials out; both directions, same wizard
- Per-tunnel performance presets (Balanced / Turbo / Throughput / Gaming), auto-MTU probe, MSS clamping
- Auto-heal watchdog with downtime stats, boot persistence, transport recommendation from real measurements

### ⚡ GRE tunnels + IP-Spoof
- Kernel-level L3 tunnels: **raw GRE (protocol 47)** or **GRE over UDP (FOU)** for UDP-only paths
- **IP-Spoof** — the signature anti-DPI trick: the outer packets on the wire carry random-looking fake IPs instead of the real server IPs (kernel double-link construction, uRPF handled automatically, per-tunnel toggle)
- Same one-line join-link flow as WireGuard; the static links are built on both sides the moment the kharej fetches its link

### 🧬 Xray engine (VLESS + Reality)
- Install and manage **Xray-core** from the panel: VLESS inbounds with **Reality** TLS-camouflage (real SNI destinations, automatic x25519 keys and short-ids)
- Full inbound lifecycle: add / remove / list, UUID per user, runs as its own systemd service
- Chain it with any tunnel above — publish Reality on the clean foreign IP while the panel lives in Iran

### 🔁 Backhaul engine
- Industry-standard reverse-tunnel engine (TCP / WebSocket / UDP / TCP-mux transports) installed and wired in minutes
- Server config generated for the kharej, client service on Iran, systemd per tunnel, ready-made join material

### 🌐 DNS resolver
- Built-in **DNS-Spoof resolver** (UDP :53): override table (`domain → IP`, `domain → block`, wildcards) + everything else forwarded to clean public resolvers — clients bypass DNS hijacking
- Managed from its own panel tab, the API or the CLI

### 🔀 Port forwarding
- Classic DNAT forwards: single ports, lists and ranges (`8899,2044`, `2000-2010`), tcp/udp/both
- Per-forward **traffic quota** (day/week/month resets), **expiry dates**, automatic cut-off, public **usage page** per user (`/sub/<token>`)
- **Reverse forwards** — ports on the kharej that reach services on the Iran server through the tunnel
- Per-tunnel security: IP allow-lists, per-IP connection limits, new-connection rate limits

### 📊 Connection testing
- **Connection test**: latency / jitter / loss to public resolvers + Cloudflare download speed + UDP-egress check + per-tunnel health + preset recommendation
- **Two-server test**: one link the kharej runs — real ICMP + TCP-echo + UDP-echo between both servers, table printed on both sides, report lands in the panel
- **Link test**: direct-vs-tunnel probes with a verdict and a transport recommendation

### 🛡 Operations
- Web panel (dark glass UI, FA/EN switch, animated): live counters, 24 h traffic chart, search, health checks, audit log, TOTP 2FA with recovery codes, login rate-limiting
- Telegram bot (`/status /tunnels /traffic /report`), daily report, nightly backup to Telegram
- Watchdogs for forwards, WireGuard handshakes and GRE links (auto-heal)
- Backup / restore (panel + CLI), offline package for servers without GitHub access, one-command update with automatic rollback
- Performance presets (BBR, buffers, conntrack) applied per tunnel or system-wide
- `dr-cpanel doctor` — the first stop when a tunnel will not build

## 🚀 Quick start

On the **Iran server** (root):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
```

The menu walks you through everything:

```
0) Connection Test     which paths actually work between the two servers
1) Setup Iran          reverse / direct / forward + GRE, Xray, Backhaul wizards
2) Setup Kharej        join an existing tunnel with one link
3) Manage              tunnels, GRE, forwards, reverse forwards, status, security
4) Backup & Restore
5) Web Panel           install the glass web UI (HTTPS, 2FA)
6) Optimize            BBR, buffers, conntrack presets
7) Telegram Bot
8) Update              with automatic rollback
9) Uninstall
```

Then install the web panel (menu 5) and open `https://SERVER_IP:8443`.

On the **kharej server**, run the one-line join link the panel prints — the kharej side is set up automatically:

```bash
bash <(curl -fsSLk https://IRAN_IP:8443/join/<token>)
```

## 🧭 How a tunnel works

```
users ──► IRAN :443 ──► tunnel ──► KHAREJ :443 (real service)
                │        (WireGuard over UDP/TCP/WS/WSS/KCP/QUIC
                │         or GRE / GRE-over-UDP, optionally IP-spoofed
                │         or a Backhaul reverse tunnel, or Xray Reality)
                └── panel, quotas, tests, watchdog all live here
```

## 📋 Requirements

- Ubuntu / Debian (also works on RHEL-family), root
- Two servers: one in Iran (panel side), one abroad (service side)
- The web panel needs `python3`; tunnels need `curl` and `iptables` (auto-installed)

## 📝 Notes

- The panel is served on `:8443` with a self-signed certificate by default — bring your own domain + Let's Encrypt from menu 5
- The join link contains the kharej side's private key — treat it like a password
- IP-Spoof needs the path to tolerate spoofed sources (most VPS providers do; strict-uRPF paths will not)

## License

MIT — see [LICENSE](LICENSE).
