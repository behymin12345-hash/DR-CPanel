# DR-CPanel

![Version](https://img.shields.io/badge/version-2.7.0-8b5cf6) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-Linux-blue) ![Telegram](https://img.shields.io/badge/Telegram-@DR_Gojo_Satoruu-26a5e4)

Menu-driven **port-forward tunnel manager** (iptables DNAT) with a built-in **galaxy-styled web panel**.
Run it on the Iran server: users connect to it and traffic is forwarded to the foreign node. Nothing is needed on the foreign server.

## Screenshots

| Dashboard | Tunnels | User quota |
|---|---|---|
| ![Dashboard](screenshots/dashboard.png) | ![Tunnels](screenshots/tunnels.png) | ![Quota](screenshots/quota.png) |
| **Login** | **Light theme (EN)** | **User usage page** |
| ![Login](screenshots/login.png) | ![Light](screenshots/light-theme.png) | ![Sub](screenshots/sub-page.png) |

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
```

Run as **root**. After installing, open the menu any time with:

```bash
dr-cpanel
```

## Features

### Tunnels & forwarding
- Add / list / remove port forwards (TCP, UDP or both), **several listen ports at once** (`8899,2044`)
- **Multiple foreign servers with grouping** — organize tunnels per node
- **WireGuard encrypted transport** between Iran and each foreign node (`10.66.x.x` link, keys generated automatically) + a script for the foreign side
- Transport test (verify the WireGuard link is up end-to-end)
- Live traffic counters for every forward
- Connection test (TCP connect time and ping to the foreign node)

### Quotas & users
- Per-forward **traffic quota** (the port is cut automatically when the quota is reached)
- **User usage link** (`/sub/<token>`) so each user can see their own usage — with its own styled page
- Import hand-made iptables rules into the panel

### Security
- Per-tunnel **allowed IPs** (comma separated, CIDR supported)
- **Max simultaneous connections per IP** and **max new connections per minute per IP**
- One-click network optimize (**BBR** + TCP buffers)

### Web panel (v2.7 galaxy UI)
- Galaxy neon lighting: aurora glow, starfield background, glass cards with gradient borders
- **Dark + light themes**, **8 accent colors + custom color picker**
- **FA / EN** language switch, fully **responsive on mobile**
- Sliding tab indicator, animated number counters, boot loading screen
- **Tunnel search** (name / port / IP) and **click-to-copy** destination
- Per-port security editor, quota management, live meters
- Domain + HTTPS (Let's Encrypt) or self-signed certificate
- GitHub & Telegram links in the footer

### System
- Starts automatically after reboot (systemd, both tunnels and web panel)
- Backup & restore of all settings
- Clean uninstall
- Self-update: `dr-cpanel update`

## Requirements

- Linux with `iptables` (installed automatically if missing: Ubuntu / Debian / CentOS / Rocky / Alma)
- `python3` for the web panel (installed automatically if missing)
- Root access
- If `ufw` is active, allow each listen port: `ufw allow <port>/tcp`

## Commands

| Command | What it does |
|---|---|
| `dr-cpanel` | Open the interactive menu |
| `dr-cpanel apply` | Re-apply all saved forwards (used by systemd at boot) |
| `dr-cpanel list` | Show all forwards with live counters |
| `dr-cpanel tunnel add IP [UDP_PORT] [MTU]` | Add a foreign node (WireGuard link) |
| `dr-cpanel tunnel script IP` | Print the setup script for the foreign node |
| `dr-cpanel tunnel use IP` / `direct IP` | Route traffic through the tunnel / directly |
| `dr-cpanel tunnel sync` | Sync all WireGuard links |
| `dr-cpanel tunnel del IP` | Remove a foreign node |
| `dr-cpanel update` | Update to the latest version (settings kept) |

## Web panel

Open from the menu: **9) Web panel → 1) Install / update**

- Default port: `8443` (you choose it on first install), default URL: `https://SERVER_IP:8443`
- A random admin password is generated on first install (shown once, changeable from the menu)
- HTTPS uses a self-signed certificate by default → the browser warns **once**, choose *Advanced → Proceed*
- For a trusted certificate: **9) Web panel → 7) Domain + HTTPS (Let's Encrypt)** (the domain's A record must point to this server)
- Panel settings are stored in `/etc/dr-cpanel` together with everything else

## Update

```bash
dr-cpanel update
```

or run the install command again. **All forwards, tunnels, quotas and settings in `/etc/dr-cpanel` are kept** — the update only replaces the program and the web panel files.

## Uninstall

Menu → **10) Uninstall**

## Contact

Telegram: [@DR_Gojo_Satoruu](https://t.me/DR_Gojo_Satoruu)
GitHub: [behymin12345-hash/DR-CPanel](https://github.com/behymin12345-hash/DR-CPanel)

## License

MIT

---

# راهنمای فارسی

**DR-CPanel** یک مدیر تونل پورت‌فوروارد (با iptables) همراه با منوی ترمینال و **پنل وب با تم کهکشانی** است.
روی **سرور ایران** نصب می‌شود. کاربرها به آن وصل می‌شوند و ترافیک به سرور خارج فوروارد می‌شود. روی سرور خارج هیچ چیزی لازم نیست.

## نصب

با کاربر root این دستور را بزن:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
```

بعد از نصب، هر وقت خواستی منو را باز کنی فقط بنویس: `dr-cpanel`

## قابلیت‌ها

### تونل و فوروارد
- افزودن، نمایش و حذف فوروارد (TCP / UDP / هر دو) با **چند پورت هم‌زمان** (`8899,2044`)
- **چند سرور خارج با گروه‌بندی** — تونل‌ها را بر اساس نود سازمان‌دهی کن
- **ترنسپورت رمزنگاری‌شده WireGuard** بین ایران و هر سرور خارج (لینک `10.66.x.x`، ساخت خودکار کلیدها) به‌همراه اسکریپت آماده برای سمت خارج
- تست ترنسپورت (اطمینان از برقراری لینک WireGuard از دو طرف)
- شمارنده‌ی ترافیک زنده برای هر فوروارد
- تست اتصال (زمان اتصال TCP و پینگ به سرور خارج)

### کوتا و کاربران
- **محدودیت حجم** برای هر فوروارد (با رسیدن به سقف، پورت خودکار قطع می‌شود)
- **لینک مصرف کاربر** (`/sub/<token>`) برای دیدن مصرف خودش — با صفحه‌ی اختصاصی و استایل‌دار
- وارد کردن رول‌های دستی iptables به پنل

### امنیت
- **IPهای مجاز** برای هر تونل (با کاما، پشتیبانی از CIDR)
- **حداکثر اتصال هم‌زمان per IP** و **حداکثر اتصال جدید در دقیقه per IP**
- بهینه‌سازی شبکه با یک کلیک (**BBR** و بافرهای TCP)

### پنل وب (رابط کهکشانی نسخه 2.7)
- نورپردازی نئون کهکشانی: هاله‌ی آورورا، پس‌زمینه‌ی ستاره‌ای، کارت‌های شیشه‌ای با حاشیه‌ی گرادیانی
- **تم تیره + روشن**، **۸ رنگ اصلی + انتخاب رنگ دلخواه**
- سوییچ **فارسی / انگلیسی**، کاملاً **واکنش‌گرا روی موبایل**
- نشانگر تب لغزان، شمارنده‌های عددی متحرک، صفحه‌ی لودینگ شروع
- **جستجو در تونل‌ها** (نام / پورت / IP) و **کلیک برای کپی** مقصد
- ویرایشگر امنیت هر پورت، مدیریت کوتا، نمایشگرهای زنده
- دامنه + HTTPS (Let's Encrypt) یا گواهی self-signed
- لینک GitHub و تلگرام در فوتر صفحه

### سیستم
- اجرای خودکار بعد از ریبوت (systemd، هم تونل‌ها هم پنل وب)
- بکاپ و ریستور کامل تنظیمات
- حذف کامل
- آپدیت خودش: `dr-cpanel update`

## پیش‌نیازها

- لینوکس با `iptables` (در صورت نبود خودکار نصب می‌شود: Ubuntu / Debian / CentOS / Rocky / Alma)
- `python3` برای پنل وب (در صورت نبود خودکار نصب می‌شود)
- دسترسی root
- اگر `ufw` فعال است، هر پورت را باز کن: `ufw allow <port>/tcp`

## دستورات

| دستور | کار |
|---|---|
| `dr-cpanel` | باز کردن منوی تعاملی |
| `dr-cpanel apply` | اعمال دوباره‌ی همه‌ی فورواردها (موقع بوت توسط systemd) |
| `dr-cpanel list` | نمایش همه‌ی فورواردها با شمارنده‌ی زنده |
| `dr-cpanel tunnel add IP [UDP_PORT] [MTU]` | افزودن سرور خارج (لینک WireGuard) |
| `dr-cpanel tunnel script IP` | نمایش اسکریپت نصب برای سمت سرور خارج |
| `dr-cpanel tunnel use IP` / `direct IP` | عبور ترافیک از تونل / مستقیم |
| `dr-cpanel tunnel sync` | همگام‌سازی همه‌ی لینک‌های WireGuard |
| `dr-cpanel tunnel del IP` | حذف سرور خارج |
| `dr-cpanel update` | آپدیت به آخرین نسخه (تنظیمات حفظ می‌شود) |

## پنل وب

از منو: **9) Web panel → 1) Install / update**

- پورت پیش‌فرض: `8443` (بار اول خودت انتخاب می‌کنی)، آدرس: `https://IP_سرور:8443`
- بار اول یک رمز تصادفی ساخته می‌شود (یک بار نمایش داده می‌شود؛ از منو قابل تغییر است)
- HTTPS با گواهی self-signed است → مرورگر **یک بار** هشدار می‌دهد، *Advanced → Proceed* را بزن
- برای گواهی معتبر: **9) Web panel → 7) Domain + HTTPS (Let's Encrypt)** (رکورد A دامنه باید به این سرور اشاره کند)

## آپدیت

```bash
dr-cpanel update
```

یا دستور نصب را دوباره اجرا کن. **همه‌ی فورواردها، تونل‌ها، کوتاها و تنظیمات در `/etc/dr-cpanel` حفظ می‌شوند** — آپدیت فقط برنامه و فایل‌های پنل وب را عوض می‌کند.

## حذف

از منو گزینه‌ی **10** (Uninstall)

## ارتباط با ما

تلگرام: [@DR_Gojo_Satoruu](https://t.me/DR_Gojo_Satoruu)
گیت‌هاب: [behymin12345-hash/DR-CPanel](https://github.com/behymin12345-hash/DR-CPanel)
