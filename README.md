# DR-CPanel

Menu-driven **port-forward tunnel manager** (iptables DNAT) with a built-in **web panel**.
Run it on the Iran server: users connect to it and traffic is forwarded to the foreign node. Nothing is needed on the foreign server.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
```

Run as **root**. After installing, open the menu any time with:

```bash
dr-cpanel
```

## Features

- Add / list / remove port forwards (TCP, UDP or both)
- Live traffic counters for every forward
- Per-forward traffic quota (the port is cut automatically when the quota is reached)
- User usage link (`/sub/<token>`) so each user can see their own usage
- Web panel: dark UI, tab bar, domain + HTTPS support, FA/EN language switch, accent colors
- Connection test (TCP connect time and ping to the foreign node)
- Network optimize (BBR + TCP buffers)
- Backup & restore of all settings
- Import hand-made iptables rules into the panel
- Starts automatically after reboot (systemd)
- Clean uninstall

## Requirements

- Linux with `iptables` (installed automatically if missing: Ubuntu / Debian / CentOS / Rocky / Alma)
- Root access
- If `ufw` is active, allow each listen port: `ufw allow <port>/tcp`

## Commands

| Command | What it does |
|---|---|
| `dr-cpanel` | Open the interactive menu |
| `dr-cpanel apply` | Re-apply all saved forwards (used by systemd at boot) |
| `dr-cpanel list` | Show all forwards |

## Update

Run the install command again. Your forwards and settings in `/etc/dr-cpanel` are kept.

## Uninstall

Menu → **10) Uninstall**

## Contact

Telegram: [@DR_Gojo_Satoruu](https://t.me/DR_Gojo_Satoruu)

## License

MIT

---

# راهنمای فارسی

**DR-CPanel** یک مدیر تونل پورت‌فوروارد (با iptables) همراه با منوی ترمینال و پنل وب است.
روی **سرور ایران** نصب می‌شود. کاربرها به آن وصل می‌شوند و ترافیک به سرور خارج فوروارد می‌شود. روی سرور خارج هیچ چیزی لازم نیست.

## نصب

با کاربر root این دستور را بزن:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
```

بعد از نصب، هر وقت خواستی منو را باز کنی فقط بنویس: `dr-cpanel`

## قابلیت‌ها

- افزودن، نمایش و حذف فوروارد (TCP / UDP / هر دو)
- شمارنده‌ی ترافیک زنده برای هر فوروارد
- محدودیت حجم برای هر فوروارد (با رسیدن به سقف، پورت خودکار قطع می‌شود)
- لینک مصرف کاربر برای دیدن مصرف خودش
- پنل وب با تم تیره، دامنه و HTTPS، تغییر زبان فارسی/انگلیسی و رنگ دلخواه
- تست اتصال (زمان اتصال TCP و پینگ)
- بهینه‌سازی شبکه (BBR و بافرها)
- بکاپ و ریستور تنظیمات
- وارد کردن رول‌های دستی iptables به پنل
- اجرای خودکار بعد از ریبوت
- حذف کامل

## آپدیت

دستور نصب را دوباره اجرا کن. فوروارد‌ها و تنظیمات شما در `/etc/dr-cpanel` حفظ می‌شود.

## حذف

از منو گزینه‌ی **10** (Uninstall)
