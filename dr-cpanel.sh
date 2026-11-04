#!/usr/bin/env bash
# DR-CPanel - menu-driven port-forward tunnel manager (iptables DNAT) + web panel
# v2.4.1: added "dr-cpanel update" command; v2.4.0: FA/EN language switch, accent colors, animated loading screen; v2.3.0: new web panel UI (dark, tab bar, segmented meters, effects); v2.2.1: fixed login typing bug
# v2.2: per-forward traffic quota, user usage link (/sub/<token>), domain + HTTPS
# Run this on the Iran server. Users connect to it, traffic is forwarded
# to the foreign node. Nothing is needed on the foreign server.
#
# Usage:  sudo bash dr-cpanel.sh        (interactive menu)
#         dr-cpanel apply | list | update   (non-interactive; apply is used by systemd)

set -u

VERSION="2.4.1"
CONF_DIR="/etc/dr-cpanel"
BLK="$CONF_DIR/blocked"             # ports cut off by their quota (written by the web panel)
CONF="$CONF_DIR/rules.conf"          # lines: name|proto|listen_port|dest_ip|dest_port
DEF_IP_FILE="$CONF_DIR/default_ip"
BIN="/usr/local/bin/dr-cpanel"
UNIT="/etc/systemd/system/dr-cpanel.service"
SYSCTL_FWD="/etc/sysctl.d/99-dr-cpanel-forward.conf"
SYSCTL_OPT="/etc/sysctl.d/99-dr-cpanel-optimize.conf"

C_RST=$'\e[0m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'
C_CYN=$'\e[36m'; C_BLD=$'\e[1m'

ok()   { echo "  ${C_GRN}✔${C_RST} $*"; }
err()  { echo "  ${C_RED}✘${C_RST} $*"; }
warn() { echo "  ${C_YEL}!${C_RST} $*"; }
info() { echo "  ${C_CYN}•${C_RST} $*"; }
pause(){ echo; read -rp "  Press Enter to continue..." _; }
confirm(){ local a; read -rp "  $1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }; }

ensure_deps() {
  command -v iptables >/dev/null 2>&1 && return 0
  warn "iptables not found, installing..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq iptables
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y iptables
  elif command -v yum >/dev/null 2>&1; then
    yum install -y iptables
  fi
  command -v iptables >/dev/null 2>&1 || { err "Could not install iptables."; exit 1; }
}

valid_port() { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
valid_ip() {
  local re='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  [[ $1 =~ $re ]] || return 1
  local i; for i in 1 2 3 4; do (( BASH_REMATCH[i] <= 255 )) || return 1; done
}
proto_list() { case "$1" in both) echo "tcp udp";; *) echo "$1";; esac; }
proto_num()  { case "$1" in tcp) echo 6;; udp) echo 17;; esac; }
hb() {
  awk -v b="$1" 'BEGIN{split("B KB MB GB TB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf "%.1f %s",b,u[i]}'
}

banner() {
  clear 2>/dev/null || true
  echo "${C_CYN}${C_BLD}"
  echo "  ┌──────────────────────────────────────────────────┐"
  printf "  │  DR-CPanel v%-6s  Port-Forward Tunnel Manager   │\n" "$VERSION"
  echo "  │  Run on the Iran server · nothing needed abroad  │"
  echo "  │  by @DR_Gojo_Satoruu  (t.me/DR_Gojo_Satoruu)     │"
  echo "  └──────────────────────────────────────────────────┘${C_RST}"
  echo
}

# ---------------------------------------------------------------- core ----

apply_rules() {
  sysctl -q -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  local spec t chain parent
  for spec in "nat PREROUTING DRC_PRE" "nat POSTROUTING DRC_POST" "filter FORWARD DRC_FWD"; do
    set -- $spec; t=$1; parent=$2; chain=$3
    iptables -t "$t" -N "$chain" 2>/dev/null || true
    iptables -t "$t" -F "$chain"
    iptables -t "$t" -C "$parent" -j "$chain" 2>/dev/null || iptables -t "$t" -I "$parent" 1 -j "$chain"
  done
  [[ -s $CONF ]] || return 0
  local name proto lport ip dport p act
  while IFS='|' read -r name proto lport ip dport; do
    [[ -z $name ]] && continue
    act=ACCEPT; [[ -s $BLK ]] && grep -qx "$lport" "$BLK" && act=DROP
    for p in $(proto_list "$proto"); do
      iptables -t nat    -A DRC_PRE  -p "$p" --dport "$lport" -j DNAT --to-destination "$ip:$dport"
      iptables -t nat    -A DRC_POST -p "$p" -d "$ip" --dport "$dport" -j MASQUERADE
      iptables -t filter -A DRC_FWD  -p "$p" -d "$ip" --dport "$dport" -m comment --comment "drc:$lport" -j "$act"
      iptables -t filter -A DRC_FWD  -p "$p" -s "$ip" --sport "$dport" -m comment --comment "drc:$lport" -j "$act"
    done
  done < "$CONF"
}

ensure_boot() {
  mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
  echo "net.ipv4.ip_forward=1" > "$SYSCTL_FWD"
  local self; self=$(readlink -f "$0" 2>/dev/null || echo "$0")
  if [[ $self != "$BIN" && -f $self ]]; then
    install -m 755 "$self" "$BIN" 2>/dev/null || cp "$self" "$BIN"
  fi
  command -v systemctl >/dev/null 2>&1 || return 0
  cat > "$UNIT" <<EOF
[Unit]
Description=DR-CPanel port forwards
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN apply

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable dr-cpanel.service >/dev/null 2>&1
}

counters() {   # echo "<packets> <bytes>" for a rule
  local p out pk=0 by=0
  for p in $(proto_list "$1"); do
    out=$(iptables -t nat -nvxL DRC_PRE 2>/dev/null | awk -v p="$p" -v n="$(proto_num "$p")" -v d="dpt:$2 " \
      '($4==p||$4==n) && index($0,d){a+=$1;b+=$2} END{print a+0, b+0}')
    pk=$(( pk + ${out% *} )); by=$(( by + ${out#* } ))
  done
  echo "$pk $by"
}

tcp_time() {   # echo connect time in ms, or "fail"
  local s e
  s=$(date +%s%N)
  if timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null </dev/null; then
    e=$(date +%s%N); echo $(( (e - s) / 1000000 ))
  else
    echo fail
  fi
}

# ------------------------------------------------------ migration ---------

migrate_legacy() {   # one-time upgrade from the old FWPanel
  local old="/etc/fw""panel" o="FW""P_"
  [[ -d $old ]] || return 0
  if [[ ! -s $CONF && -s $old/rules.conf ]]; then
    mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
    cp "$old/rules.conf" "$CONF"
    [[ -f $old/default_ip ]] && cp "$old/default_ip" "$DEF_IP_FILE"
  fi
  local spec t parent chain
  for spec in "nat PREROUTING ${o}PRE" "nat POSTROUTING ${o}POST" "filter FORWARD ${o}FWD"; do
    set -- $spec; t=$1; parent=$2; chain=$3
    iptables -t "$t" -D "$parent" -j "$chain" 2>/dev/null
    iptables -t "$t" -F "$chain" 2>/dev/null
    iptables -t "$t" -X "$chain" 2>/dev/null
  done
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now fw"panel.service" >/dev/null 2>&1
    rm -f "/etc/systemd/system/fw""panel.service"; systemctl daemon-reload >/dev/null 2>&1
  fi
  rm -f "/usr/local/bin/fw""panel" "/etc/sysctl.d/99-fw""panel-forward.conf"
  mv "$old" "$old.migrated"
  apply_rules; ensure_boot
  ok "Migrated from FWPanel to DR-CPanel (old settings kept in $old.migrated)."
}

# ------------------------------------------------------- web panel --------

WEB_DIR="/usr/local/lib/dr-cpanel"
WEB_PY="$WEB_DIR/web.py"
WEB_UI="$WEB_DIR/index.html"
WEB_UNIT="/etc/systemd/system/dr-cpanel-web.service"
WEB_CFG="$CONF_DIR/web.json"

web_write_files() {
  mkdir -p "$WEB_DIR"
  cat > "$WEB_PY" <<'PYEOF'
#!/usr/bin/env python3
import json, os, re, ssl, subprocess, hashlib, hmac, secrets, socket, threading, time, ipaddress, sys
import shutil, tarfile, io, base64, urllib.request, collections, html
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http.cookies import SimpleCookie

D = "/etc/dr-cpanel"; CONF = D + "/rules.conf"; WEB = D + "/web.json"; DEF = D + "/default_ip"
BIN = "/usr/local/bin/dr-cpanel"; UI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
CERT = D + "/web.crt"; KEY = D + "/web.key"; LOGF = "/var/log/dr-cpanel.log"
LOCK = threading.Lock(); CLOCK = threading.Lock(); SESS = {}; FAILS = {}
LOGS = collections.deque(maxlen=300); HEALTH = {}; SYS = {}

# ------------------------------------------------------------ config / log
def cfg():
    try: return json.load(open(WEB))
    except Exception: return {"port": 8443, "tls": False}

def save(c):
    os.makedirs(D, exist_ok=True)
    with open(WEB, "w") as f: json.dump(c, f)
    os.chmod(WEB, 0o600)

def upd(**kw):
    with CLOCK:
        c = cfg(); c.update(kw); save(c)

def log(level, msg):
    LOGS.append({"t": time.time(), "l": level, "m": msg})
    try:
        with open(LOGF, "a") as f: f.write("%s [%s] %s\n" % (time.strftime("%F %T"), level, msg))
    except Exception: pass

def tg_send(text):
    c = cfg()
    if not (c.get("tg_token") and c.get("tg_chat")): return "Telegram is not configured"
    try:
        u = "%s/bot%s/sendMessage" % (c.get("tg_api") or "https://api.telegram.org", c["tg_token"])
        u = u.replace("//bot", "/bot")
        req = urllib.request.Request(u, data=json.dumps({"chat_id": c["tg_chat"], "text": text}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=10).read(); return None
    except Exception as e: return "%s" % type(e).__name__

def notify(text):
    def run():
        e = tg_send(text)
        if e and e != "Telegram is not configured": log("warn", "Telegram send failed: " + e)
    threading.Thread(target=run, daemon=True).start()

def mkhash(pw, salt): return hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 200000).hex()

# ------------------------------------------------------------------ rules
def read_rules():
    out = []
    try:
        for l in open(CONF):
            p = l.rstrip("\n").split("|")
            if len(p) == 5: out.append(dict(name=p[0], proto=p[1], lport=int(p[2]), ip=p[3], dport=int(p[4])))
    except FileNotFoundError: pass
    return out

def write_rules(rs):
    os.makedirs(D, exist_ok=True)
    with open(CONF + ".tmp", "w") as f:
        for r in rs: f.write("%s|%s|%d|%s|%d\n" % (r["name"], r["proto"], r["lport"], r["ip"], r["dport"]))
    quota_tick()
    os.replace(CONF + ".tmp", CONF)
    subprocess.run([BIN, "apply"], timeout=20)
    quota_rebase()

def counters():
    c = {}
    try: out = subprocess.run(["iptables", "-t", "nat", "-nvxL", "DRC_PRE"], capture_output=True, text=True, timeout=5).stdout
    except Exception: return c
    for l in out.splitlines():
        f = l.split(); m = re.search(r"dpt:(\d+)", l)
        if len(f) > 3 and m and f[0].isdigit():
            k = ({"6": "tcp", "17": "udp"}.get(f[3], f[3]), int(m.group(1)))
            a = c.setdefault(k, [0, 0]); a[0] += int(f[0]); a[1] += int(f[1])
    return c

def tcp_ms(ip, port):
    s = time.time()
    try:
        socket.create_connection((ip, port), 4).close()
        return int((time.time() - s) * 1000)
    except Exception: return None

def validate(d):
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", str(d.get("name") or ""))
    proto = d.get("proto", "tcp")
    if proto not in ("tcp", "udp", "both"): raise ValueError("Invalid protocol")
    try: lport = int(d.get("lport")); dport = int(d.get("dport") or lport)
    except Exception: raise ValueError("Invalid port")
    if not (1 <= lport <= 65535 and 1 <= dport <= 65535): raise ValueError("Port out of range")
    try: ip = str(ipaddress.IPv4Address(str(d.get("ip")).strip()))
    except Exception: raise ValueError("Invalid IP")
    if lport == cfg().get("port"): raise ValueError("This port is used by the web panel")
    for r in read_rules():
        if r["lport"] == lport and (r["proto"] == proto or "both" in (r["proto"], proto)): raise ValueError("A forward on this port already exists")
    return dict(name=name or "fw%d" % lport, proto=proto, lport=lport, ip=ip, dport=dport)

# -------------------------------------------------------- system sampling
def sysval(k):
    try: return open("/proc/sys/" + k.replace(".", "/")).read().strip()
    except Exception: return "?"

def sampler():
    prev = None
    while True:
        try:
            v = list(map(int, open("/proc/stat").readline().split()[1:])); idle = v[3] + v[4]; tot = sum(v)
            cpu = SYS.get("cpu", 0)
            if prev and tot > prev[1]: cpu = round(100 * (1 - (idle - prev[0]) / (tot - prev[1])), 1)
            prev = (idle, tot)
            mi = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo") if ":" in l}
            du = shutil.disk_usage("/"); rx = tx = 0
            for l in list(open("/proc/net/dev"))[2:]:
                n, d = l.split(":", 1); f = d.split()
                if n.strip() != "lo": rx += int(f[0]); tx += int(f[8])
            SYS.update(cpu=cpu, ram_total=mi["MemTotal"] * 1024, ram_used=(mi["MemTotal"] - mi.get("MemAvailable", 0)) * 1024,
                       disk_total=du.total, disk_used=du.used, rx=rx, tx=tx, t=time.time(), load=os.getloadavg()[0],
                       up=int(float(open("/proc/uptime").read().split()[0])))
        except Exception: pass
        time.sleep(3)

# ------------------------------------------------------ monitor / watchdog
def probe(r):
    return r, tcp_ms(r["ip"], r["dport"])

def monitor():
    time.sleep(5)
    while True:
        try:
            rs = [r for r in read_rules() if r["proto"] != "udp"]
            keys = {"%d/%s" % (r["lport"], r["proto"]) for r in rs}
            for k in list(HEALTH):
                if k not in keys: HEALTH.pop(k)
            with ThreadPoolExecutor(8) as ex:
                for r, ms in ex.map(probe, rs):
                    k = "%d/%s" % (r["lport"], r["proto"]); now = time.time()
                    h = HEALTH.setdefault(k, dict(ok=None, ms=None, since=now, hist=collections.deque(maxlen=40), fails=0))
                    h["hist"].append(ms); h["ms"] = ms
                    if ms is not None:
                        h["fails"] = 0
                        if h["ok"] is not True:
                            if h["ok"] is False:
                                log("info", "%s is back up (%d ms)" % (r["name"], ms)); notify("🟢 %s (:%d → %s:%d) is back up" % (r["name"], r["lport"], r["ip"], r["dport"]))
                            h["ok"] = True; h["since"] = now
                    else:
                        h["fails"] += 1
                        if h["fails"] >= 2 and h["ok"] is not False:
                            h["ok"] = False; h["since"] = now
                            log("warn", "%s is DOWN: %s:%d unreachable" % (r["name"], r["ip"], r["dport"]))
                            notify("🔴 %s (:%d → %s:%d) is DOWN" % (r["name"], r["lport"], r["ip"], r["dport"]))
            watchdog()
            c = cfg(); cpu = SYS.get("cpu", 0); ram = 100 * SYS.get("ram_used", 0) / max(SYS.get("ram_total", 1), 1)
            if (cpu > 90 or ram > 92) and time.time() - c.get("_lastres", 0) > 1800:
                upd(_lastres=time.time()); log("warn", "High resource use: CPU %.0f%% RAM %.0f%%" % (cpu, ram)); notify("⚠️ High resource use: CPU %.0f%% · RAM %.0f%%" % (cpu, ram))
        except Exception as e: log("warn", "monitor error: %s" % type(e).__name__)
        time.sleep(15)

def watchdog():
    exp = sum(2 if r["proto"] == "both" else 1 for r in read_rules())
    try: out = subprocess.run(["iptables", "-t", "nat", "-S", "DRC_PRE"], capture_output=True, text=True, timeout=5).stdout
    except Exception: return
    got = sum(1 for l in out.splitlines() if l.startswith("-A DRC_PRE"))
    if got != exp:
        subprocess.run([BIN, "apply"], timeout=20)
        log("warn", "Watchdog: forwarding rules were missing (%d/%d) and have been restored" % (got, exp))
        notify("♻️ Watchdog restored forwarding rules (%d/%d)" % (got, exp))

# ------------------------------------------------------------ views / ops
def state():
    c = counters(); rs = []; qd = jload(QUOTA); sb = jload(SUBF); bk = blocked()
    for r in read_rules():
        pk = by = 0
        for p in (["tcp", "udp"] if r["proto"] == "both" else [r["proto"]]):
            a = c.get((p, r["lport"]), [0, 0]); pk += a[0]; by += a[1]
        h = HEALTH.get("%d/%s" % (r["lport"], r["proto"]))
        st = "unknown" if not h or h["ok"] is None else ("up" if h["ok"] else "down")
        e = qd.get(str(r["lport"]), {}); by = int(e.get("used", by))
        rs.append(dict(r, packets=pk, bytes=by, limit=int(e.get("limit", 0)), blocked=str(r["lport"]) in bk, sub=str(r["lport"]) in sb, status=st, ms=h["ms"] if h else None,
                       hist=list(h["hist"]) if h else [], since=h["since"] if h else None))
    return {"rules": rs, "host": socket.gethostname(), "sys": dict(SYS), "ip_forward": sysval("net.ipv4.ip_forward") == "1",
            "cc": sysval("net.ipv4.tcp_congestion_control"), "now": time.time(), "ver": "__DR_VERSION__"}

def health_check():
    items = []
    def add(lv, m, fix=""): items.append(dict(level=lv, msg=m, fix=fix))
    add("ok" if sysval("net.ipv4.ip_forward") == "1" else "err", "IP forwarding " + ("is on" if sysval("net.ipv4.ip_forward") == "1" else "is OFF"), "sysctl -w net.ipv4.ip_forward=1")
    try: ch = subprocess.run(["iptables", "-t", "nat", "-nL", "DRC_PRE"], capture_output=True, timeout=5).returncode == 0
    except Exception: ch = False
    add("ok" if ch else "err", "Forwarding chain " + ("exists" if ch else "is missing"), "dr-cpanel apply")
    try:
        en = subprocess.run(["systemctl", "is-enabled", "dr-cpanel.service"], capture_output=True, text=True, timeout=5).stdout.strip()
        add("ok" if en == "enabled" else "warn", "Boot service: " + (en or "unknown"), "dr-cpanel  (add any forward to re-install the service)")
    except Exception: pass
    try:
        u = subprocess.run(["ufw", "status"], capture_output=True, text=True, timeout=5).stdout
        if "Status: active" in u: add("warn", "ufw is active: every listen port must be allowed", "ufw allow <port>/tcp")
    except Exception: pass
    try:
        cc = int(open("/proc/sys/net/netfilter/nf_conntrack_count").read()); cm = int(open("/proc/sys/net/netfilter/nf_conntrack_max").read())
        add("ok" if cc < cm * 0.8 else "warn", "Connection tracking: %d / %d" % (cc, cm), "Menu 5 (Optimize) raises nf_conntrack_max")
    except Exception: pass
    add("ok" if sysval("net.ipv4.tcp_congestion_control") == "bbr" else "warn", "TCP congestion control: " + sysval("net.ipv4.tcp_congestion_control"), "Menu 5 (Optimize) enables BBR")
    if SYS.get("disk_total") and SYS["disk_used"] / SYS["disk_total"] > 0.9: add("warn", "Disk is over 90% full")
    for r in read_rules():
        h = HEALTH.get("%d/%s" % (r["lport"], r["proto"]))
        if r["proto"] == "udp": add("ok", "%s: UDP cannot be probed" % r["name"])
        elif not h or h["ok"] is None: add("warn", "%s: not probed yet" % r["name"])
        elif h["ok"]: add("ok", "%s: destination answers (%d ms)" % (r["name"], h["ms"] or 0))
        else: add("err", "%s: %s:%d does not answer" % (r["name"], r["ip"], r["dport"]), "Check the inbound on the foreign server and its firewall")
    return items

def make_backup():
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:gz") as t:
        for n in ("rules.conf", "default_ip", "quota.json", "sub.json", "web.json", "web.crt", "web.key"):
            if os.path.exists(D + "/" + n): t.add(D + "/" + n, arcname=n)
    return b.getvalue()

def restore(data):
    n = 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
        for m in t.getmembers():
            if m.name in ("rules.conf", "default_ip", "quota.json", "sub.json") and m.isfile() and m.size < 1000000:
                open(D + "/" + m.name, "wb").write(t.extractfile(m).read()); n += 1
    if not n: raise ValueError("No forwards found in this file")
    subprocess.run([BIN, "apply"], timeout=20)

# ------------------------------------------------- quota / sub link / domain
QUOTA = D + "/quota.json"; BLKF = D + "/blocked"; SUBF = D + "/sub.json"
QLOCK = threading.Lock(); MISS = {}; HSTS_H = ()
HOOK = "/etc/letsencrypt/renewal-hooks/deploy/dr-cpanel-web.sh"

def jload(p):
    try: return json.load(open(p))
    except Exception: return {}

def jsave(p, d):
    with open(p + ".tmp", "w") as f: json.dump(d, f)
    os.chmod(p + ".tmp", 0o600); os.replace(p + ".tmp", p)

def blocked():
    try: return {l.strip() for l in open(BLKF) if l.strip()}
    except Exception: return set()

def hbytes(n):
    u = ["B", "KB", "MB", "GB", "TB", "PB"]; i = 0; n = float(n or 0)
    while n >= 1024 and i < 5: n /= 1024; i += 1
    return ("%.2f" % n).rstrip("0").rstrip(".") + " " + u[i] if i else "%d B" % n

def fwd_bytes():
    # bytes forwarded per rule, both directions; every FWD rule carries a "drc:<port>" comment
    out = {}
    try: t = subprocess.run(["iptables", "-t", "filter", "-nvxL", "DRC_FWD"], capture_output=True, text=True, timeout=5).stdout
    except Exception: return None
    for l in t.splitlines():
        m = re.search(r"drc:(\d+)", l); f = l.split()
        if m and len(f) > 1 and f[1].isdigit(): out[m.group(1)] = out.get(m.group(1), 0) + int(f[1])
    return out

def quota_tick():
    with QLOCK:
        cur = fwd_bytes()
        if cur is None: return
        q = jload(QUOTA); old = blocked(); new = set(); names = {}
        for r in read_rules(): names[str(r["lport"])] = r["name"]
        for k in list(q):
            if k not in names: q.pop(k)
        for k in names:
            e = q.setdefault(k, {"limit": 0, "used": 0, "last": 0}); c = cur.get(k, 0)
            d = c - e["last"] if c >= e["last"] else c
            if d > 0 and k not in old: e["used"] += d
            e["last"] = c
            if e["limit"] and e["used"] >= e["limit"]: new.add(k)
        if new != old:
            with open(BLKF, "w") as f: f.write("".join(k + "\n" for k in sorted(new)))
            subprocess.run([BIN, "apply"], timeout=20)
            for e in q.values(): e["last"] = 0
            for k in new - old:
                log("warn", "%s (:%s) used up its quota and is cut off" % (names[k], k)); notify("⛔ %s (:%s) حجمش تمام شد و قطع شد" % (names[k], k))
            for k in old - new: log("info", "%s (:%s) is back online" % (names.get(k, "?"), k))
        jsave(QUOTA, q)

def quota_rebase():
    with QLOCK:
        q = jload(QUOTA)
        for e in q.values(): e["last"] = 0
        jsave(QUOTA, q)

def quota_loop():
    time.sleep(2)
    while True:
        try: quota_tick()
        except Exception as e: log("warn", "quota error: %s" % type(e).__name__)
        time.sleep(3)

def quota_set(lport, limit=None, reset=False):
    quota_tick()
    with QLOCK:
        q = jload(QUOTA); e = q.setdefault(str(lport), {"limit": 0, "used": 0, "last": 0})
        if limit is not None: e["limit"] = max(0, int(limit))
        if reset: e["used"] = 0
        jsave(QUOTA, q)
    quota_tick()

def forget(lport):
    k = str(lport)
    with QLOCK:
        q = jload(QUOTA); q.pop(k, None); jsave(QUOTA, q)
        s = jload(SUBF); s.pop(k, None); jsave(SUBF, s)
        b = blocked()
        if k in b:
            b.discard(k); open(BLKF, "w").write("".join(x + "\n" for x in sorted(b)))

def sub_html(name, used, lim, left, pct, off):
    tone = "er" if off else ("wa" if lim and pct >= 90 else "ok")
    st = "حجم تمام شده — سرویس قطع است" if off else ("حجم رو به پایان است" if tone == "wa" else "سرویس فعال است")
    page = """<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><meta http-equiv="refresh" content="60"><title>وضعیت حجم</title><style>
:root{color-scheme:dark;--bg:#070707;--card:#111;--line:#ffffff18;--tx:#fafafa;--mu:#8e8e8e;--ok:#22c55e;--wa:#f59e0b;--er:#ef4444}
@media(prefers-color-scheme:light){:root{color-scheme:light;--bg:#f2f2f2;--card:#fff;--line:#0000001a;--tx:#0a0a0a;--mu:#6b6b6b}}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--tx);font:15px/1.6 -apple-system,"Segoe UI",Tahoma,sans-serif;padding:16px}
.c{width:100%;max-width:420px;background:var(--card);border:1px solid var(--line);border-radius:20px;padding:26px}.ok{--t:var(--ok)}.wa{--t:var(--wa)}.er{--t:var(--er)}
h1{margin:0;font-size:18px}small{color:var(--mu)}.st{display:flex;gap:8px;align-items:center;margin:16px 0;font-size:14px}.st i{width:9px;height:9px;border-radius:50%;background:var(--t)}
.bar{height:10px;border-radius:99px;background:var(--line);overflow:hidden;direction:ltr}.bar b{display:block;height:100%;background:var(--t)}
.g{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:18px;text-align:center}.g div{border:1px solid var(--line);border-radius:12px;padding:12px 4px}
.g span{display:block;color:var(--mu);font-size:12px;margin-bottom:4px}.g b{font-size:15px;direction:ltr;display:inline-block}footer{margin-top:16px;color:var(--mu);font-size:12px;text-align:center}
</style></head><body data-t="dark"><main class="c @TONE@"><h1>@NAME@</h1><small>وضعیت مصرف حجم</small><div class="st"><i></i>@ST@</div>@BAR@
<div class="g"><div><span>مصرف‌شده</span><b>@USED@</b></div><div><span>کل حجم</span><b>@LIM@</b></div><div><span>باقی‌مانده</span><b>@LEFT@</b></div></div>
<footer>آخرین بروزرسانی: @TIME@ · هر ۶۰ ثانیه خودکار تازه می‌شود</footer></main></body></html>"""
    rep = {"@TONE@": tone, "@NAME@": html.escape(name), "@ST@": st, "@USED@": hbytes(used),
           "@LIM@": hbytes(lim) if lim else "نامحدود", "@LEFT@": hbytes(left) if lim else "—",
           "@BAR@": '<div class="bar"><b style="width:%d%%"></b></div>' % pct if lim else "", "@TIME@": time.strftime("%F %H:%M")}
    for k, v in rep.items(): page = page.replace(k, v)
    return page

def restart_later():
    threading.Timer(1.5, lambda: subprocess.run(["systemctl", "restart", "dr-cpanel-web"])).start()

def do_domain(domain, email="", restart=True):
    domain = str(domain).strip().lower(); email = str(email).strip()
    if not re.fullmatch(r"(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", domain): raise ValueError("Invalid domain")
    if email and not re.fullmatch(r"[^@\s]{1,64}@[^@\s]{1,190}", email): raise ValueError("Invalid email")
    if not shutil.which("certbot"):
        for pm in (["apt-get", "install", "-y", "-qq", "certbot"], ["dnf", "install", "-y", "certbot"], ["yum", "install", "-y", "certbot"]):
            if shutil.which(pm[0]):
                subprocess.run(pm, capture_output=True, timeout=300); break
        if not shutil.which("certbot"): raise ValueError("certbot is missing and could not be installed (server has no access to package mirrors?)")
    s = socket.socket()
    try: s.bind(("0.0.0.0", 80))
    except OSError: raise ValueError("Port 80 is busy: Let's Encrypt needs it for a moment")
    finally: s.close()
    os.makedirs(os.path.dirname(HOOK), exist_ok=True)
    with open(HOOK, "w") as f: f.write("#!/bin/sh\n[ -f /etc/dr-cpanel/web.json ] && grep -q '\"cert\": \"/etc/letsencrypt' /etc/dr-cpanel/web.json && systemctl restart dr-cpanel-web\nexit 0\n")
    os.chmod(HOOK, 0o755)
    cmd = ["certbot", "certonly", "--standalone", "--preferred-challenges", "http", "--non-interactive", "--agree-tos", "-d", domain]
    cmd += ["-m", email] if email else ["--register-unsafely-without-email"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
    live = "/etc/letsencrypt/live/%s/" % domain
    if r.returncode or not os.path.exists(live + "fullchain.pem"):
        raise ValueError("certbot failed (does the domain point to this server?): " + (r.stdout + r.stderr).strip()[-300:])
    upd(domain=domain, email=email, cert=live + "fullchain.pem", key=live + "privkey.pem", tls=True)
    log("info", "Domain %s set with a Let's Encrypt certificate" % domain)
    if restart: restart_later()

def do_nodomain():
    upd(domain="", email="", cert="", key=""); log("info", "Domain removed, back to the self-signed certificate"); restart_later()

def do_cert(cert, key):
    cert = str(cert).strip(); key = str(key).strip()
    if "BEGIN CERTIFICATE" not in cert or "PRIVATE KEY" not in key: raise ValueError("Certificate and key must be PEM text")
    tc, tk = CERT + ".new", KEY + ".new"
    open(tc, "w").write(cert + "\n"); open(tk, "w").write(key + "\n"); os.chmod(tk, 0o600)
    try:
        x = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); x.load_cert_chain(tc, tk)
    except Exception:
        os.remove(tc); os.remove(tk); raise ValueError("Certificate and key are invalid or do not match")
    os.replace(tc, CERT); os.replace(tk, KEY); upd(tls=True, cert="", key="")
    log("info", "Own certificate installed"); restart_later()

# ------------------------------------------------------------------- http
class H(BaseHTTPRequestHandler):
    server_version = "DR-CPanel"
    def log_message(self, *a): pass

    def out(self, code, body, ctype="application/json", extra=()):
        b = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        for k, v in (("Content-Type", ctype), ("Content-Length", str(len(b))), ("Cache-Control", "no-store"),
                     ("X-Frame-Options", "DENY"), ("X-Content-Type-Options", "nosniff"), ("Referrer-Policy", "no-referrer"),
                     ("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:")) + tuple(extra) + HSTS_H:
            self.send_header(k, v)
        self.end_headers(); self.wfile.write(b)

    def token(self):
        try: return SimpleCookie(self.headers.get("Cookie", ""))["drc"].value
        except Exception: return None

    def authed(self):
        t = self.token(); e = SESS.get(t)
        if e and e > time.time(): return True
        SESS.pop(t, None); return False

    def body(self, limit=4096):
        if "application/json" not in self.headers.get("Content-Type", ""): raise ValueError("Bad request")
        n = int(self.headers.get("Content-Length") or 0)
        if n > limit: raise ValueError("Too large")
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        try: self.get()
        except Exception: self.out(500, {"error": "Server error"})

    def get(self):
        p = self.path.split("?")[0]
        if p == "/": return self.out(200, open(UI, "rb").read(), "text/html; charset=utf-8")
        if p.startswith("/sub/"): return self.sub_public(p)
        if not p.startswith("/api/"): return self.out(404, {"error": "not found"})
        if not self.authed(): return self.out(401, {"error": "auth"})
        if p == "/api/state": return self.out(200, state())
        if p == "/api/logs": return self.out(200, list(LOGS)[::-1])
        if p == "/api/health": return self.out(200, health_check())
        if p == "/api/sub":
            m = re.search(r"lport=(\d+)", self.path); k = m.group(1) if m else ""
            if k not in {str(r["lport"]) for r in read_rules()}: return self.out(404, {"error": "No such rule"})
            t = jload(SUBF).get(k, ""); return self.out(200, {"token": t, "path": "/sub/" + t if t else ""})
        if p == "/api/settings":
            c = cfg(); return self.out(200, {"domain": c.get("domain", ""), "tg_chat": c.get("tg_chat", ""), "tg_api": c.get("tg_api", ""), "has_token": bool(c.get("tg_token")), "port": c.get("port"), "tls": c.get("tls")})
        if p == "/api/backup":
            return self.out(200, make_backup(), "application/gzip", [("Content-Disposition", 'attachment; filename="dr-cpanel-backup-%s.tar.gz"' % time.strftime("%Y%m%d-%H%M%S"))])
        self.out(404, {"error": "not found"})

    def sub_public(self, p):
        ip = self.client_address[0]; now = time.time()
        if len(MISS) > 5000: MISS.clear()
        MISS[ip] = [t for t in MISS.get(ip, []) if t > now - 60]
        if len(MISS[ip]) > 30: return self.out(429, {"error": "Too many requests"})
        tok = p[5:]; js = tok.endswith(".json")
        if js: tok = tok[:-5]
        hit = None
        if re.fullmatch(r"[0-9a-f]{48}", tok):
            for k, v in jload(SUBF).items():
                if hmac.compare_digest(str(v), tok): hit = k
        r = next((x for x in read_rules() if str(x["lport"]) == hit), None) if hit else None
        if not r:
            MISS[ip].append(now); return self.out(404, {"error": "not found"})
        e = jload(QUOTA).get(hit, {}); used = int(e.get("used", 0)); lim = int(e.get("limit", 0))
        left = max(0, lim - used) if lim else 0; pct = min(100, int(100 * used / lim)) if lim else 0; off = hit in blocked()
        ex = [("X-Robots-Tag", "noindex, nofollow"), ("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'")]
        if js: return self.out(200, {"name": r["name"], "used": used, "limit": lim, "left": left, "percent": pct, "offline": off, "unlimited": not lim}, extra=ex)
        return self.out(200, sub_html(r["name"], used, lim, left, pct, off).encode(), "text/html; charset=utf-8", ex)

    def do_DELETE(self):
        m = re.fullmatch(r"/api/rules/(\d+)", self.path)
        if not (m and self.authed()): return self.out(401, {"error": "auth"})
        with LOCK:
            rs = read_rules(); i = int(m.group(1)) - 1
            if not 0 <= i < len(rs): return self.out(404, {"error": "No such rule"})
            r = rs.pop(i); write_rules(rs); forget(r["lport"])
        log("info", "Removed forward %s (:%d)" % (r["name"], r["lport"]))
        self.out(200, {"ok": True})

    def do_POST(self):
        try:
            if self.path == "/api/login": return self.login(self.body())
            if not self.authed(): return self.out(401, {"error": "auth"})
            d = self.body(3000000 if self.path == "/api/restore" else 20000 if self.path == "/api/cert" else 4096)
            if self.path == "/api/logout":
                SESS.pop(self.token(), None)
                return self.out(200, {"ok": True}, extra=[("Set-Cookie", "drc=; Max-Age=0; Path=/")])
            if self.path == "/api/rules":
                with LOCK:
                    r = validate(d); rs = read_rules(); rs.append(r); write_rules(rs)
                    open(DEF, "w").write(r["ip"])
                log("info", "Added forward %s :%d → %s:%d (%s)" % (r["name"], r["lport"], r["ip"], r["dport"], r["proto"]))
                return self.out(200, {"ok": True})
            if self.path in ("/api/quota", "/api/sub"):
                k = str(int(d.get("lport", 0)))
                if k not in {str(r["lport"]) for r in read_rules()}: return self.out(404, {"error": "No such rule"})
                if self.path == "/api/quota":
                    if d.get("reset"): quota_set(k, reset=True); log("info", "Usage of :%s reset" % k)
                    else: quota_set(k, limit=int(d.get("limit", 0))); log("info", "Quota of :%s set to %s" % (k, hbytes(int(d.get("limit", 0))) if d.get("limit") else "unlimited"))
                    return self.out(200, {"ok": True})
                s = jload(SUBF); a = d.get("action")
                if a in ("create", "rotate"):
                    if a == "rotate" or k not in s: s[k] = secrets.token_hex(24)
                elif a == "delete": s.pop(k, None)
                else: raise ValueError("Bad action")
                jsave(SUBF, s); t = s.get(k, ""); return self.out(200, {"token": t, "path": "/sub/" + t if t else ""})
            if self.path == "/api/domain":
                if d.get("remove"): do_nodomain()
                else: do_domain(d.get("domain", ""), d.get("email", ""))
                return self.out(200, {"ok": True})
            if self.path == "/api/cert": do_cert(d.get("cert", ""), d.get("key", "")); return self.out(200, {"ok": True})
            m = re.fullmatch(r"/api/test/(\d+)", self.path)
            if m:
                rs = read_rules(); i = int(m.group(1)) - 1
                if not 0 <= i < len(rs): return self.out(404, {"error": "No such rule"})
                r = rs[i]
                return self.out(200, {"ms": None if r["proto"] == "udp" else tcp_ms(r["ip"], r["dport"]), "udp": r["proto"] == "udp"})
            if self.path == "/api/settings/telegram":
                kw = {"tg_chat": str(d.get("chat", "")).strip()[:64], "tg_api": str(d.get("api", "")).strip().rstrip("/")[:200]}
                if kw["tg_api"] and not kw["tg_api"].startswith("http"): raise ValueError("API address must start with https://")
                if d.get("token"): kw["tg_token"] = str(d["token"]).strip()[:200]
                upd(**kw); log("info", "Telegram settings updated"); return self.out(200, {"ok": True})
            if self.path == "/api/settings/tgtest":
                e = tg_send("✅ DR-CPanel: Telegram connection works")
                return self.out(200 if not e else 400, {"ok": not e, "error": e})
            if self.path == "/api/settings/password":
                c = cfg()
                if not hmac.compare_digest(mkhash(str(d.get("old", "")), c["salt"]), c["hash"]): raise ValueError("Current password is wrong")
                pw = str(d.get("new", ""))
                if len(pw) < 8: raise ValueError("New password must be at least 8 characters")
                salt = secrets.token_hex(16); upd(salt=salt, hash=mkhash(pw, salt))
                keep = self.token()
                for t in list(SESS):
                    if t != keep: SESS.pop(t)
                log("info", "Admin password changed"); return self.out(200, {"ok": True})
            if self.path == "/api/restore":
                with LOCK: restore(base64.b64decode(d.get("data", ""))); log("info", "Forwards restored from backup")
                return self.out(200, {"ok": True})
            self.out(404, {"error": "not found"})
        except (ValueError, tarfile.TarError, base64.binascii.Error) as e: self.out(400, {"error": str(e) or "Bad request"})
        except Exception: self.out(500, {"error": "Server error"})

    def login(self, d):
        ip = self.client_address[0]; n, until = FAILS.get(ip, (0, 0))
        if until > time.time(): return self.out(429, {"error": "Too many attempts, try later"})
        c = cfg()
        ok = "hash" in c and hmac.compare_digest(mkhash(str(d.get("password", "")), c["salt"]), c["hash"])
        if not ok:
            n += 1; FAILS[ip] = (n, time.time() + 300 if n >= 5 else 0)
            log("warn", "Failed login from %s" % ip); time.sleep(1); return self.out(401, {"error": "Wrong password"})
        FAILS.pop(ip, None); t = secrets.token_urlsafe(32); SESS[t] = time.time() + 43200
        log("info", "Login from %s" % ip)
        ck = "drc=%s; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200%s" % (t, "; Secure" if c.get("tls") else "")
        self.out(200, {"ok": True}, extra=[("Set-Cookie", ck)])

if __name__ == "__main__":
    a = sys.argv[1:] or ["serve"]; c = cfg()
    if a[0] == "setpass":
        c["salt"] = secrets.token_hex(16); c["hash"] = mkhash(a[1], c["salt"]); save(c)
    elif a[0] == "setport": c["port"] = int(a[1]); save(c)
    elif a[0] == "settls": c["tls"] = a[1] == "1"; save(c)
    elif a[0] == "setdomain":
        try: do_domain(a[1], a[2] if len(a) > 2 else "", restart=False); print("OK")
        except Exception as e: print("ERROR:", e); sys.exit(1)
    elif a[0] == "info": print(c.get("port", 8443), "https" if c.get("tls") else "http", c.get("domain") or "-")
    else:
        threading.Thread(target=sampler, daemon=True).start()
        threading.Thread(target=monitor, daemon=True).start()
        try: subprocess.run([BIN, "apply"], timeout=20)
        except Exception: pass
        threading.Thread(target=quota_loop, daemon=True).start()
        log("info", "DR-CPanel web panel started on port %s" % c.get("port", 8443))
        srv = ThreadingHTTPServer(("0.0.0.0", c.get("port", 8443)), H)
        if c.get("tls"):
            x = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            try: x.load_cert_chain(c.get("cert") or CERT, c.get("key") or KEY)
            except Exception as e:
                log("warn", "Certificate could not be loaded (%s): using the self-signed one" % type(e).__name__); x.load_cert_chain(CERT, KEY)
            srv.socket = x.wrap_socket(srv.socket, server_side=True)
            if c.get("domain"): HSTS_H = (("Strict-Transport-Security", "max-age=31536000"),)
        srv.serve_forever()
PYEOF
  sed -i "s/__DR_VERSION__/$VERSION/g" "$WEB_PY"

  cat > "$WEB_UI" <<'HTMLEOF'
<!doctype html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DR-CPanel</title>
<script>try{if(localStorage.getItem("drl")==="en"){document.documentElement.lang="en";document.documentElement.dir="ltr"}}catch(e){}</script>
<style>
:root{--bg:#050505;--panel:#0a0a0a;--gl:#1a1a1a;--fx:255,255,255;--line:#ffffff14;--line2:#ffffff26;--tx:#fafafa;--mu:#8a8a8f;--pr:#3b82f6;--ok:#22c55e;--er:#ef4444;--wa:#f59e0b;--f:#0c0c0c;--sunk:#ffffff0d;--sh:0 1px 0 #ffffff0a inset,0 20px 60px #00000066}
body[data-t=light]{--bg:#f4f4f5;--panel:#fff;--gl:#e7e7ea;--fx:0,0,0;--line:#00000014;--line2:#00000026;--tx:#09090b;--mu:#71717a;--f:#fff;--sunk:#0000000a;--sh:0 1px 0 #fff inset,0 20px 50px #0000001a}
*{box-sizing:border-box}
body{--ac:var(--tx);--acf:var(--bg)}
body{margin:0;background:var(--bg);color:var(--tx);font:14px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Vazirmatn,Tahoma,system-ui,sans-serif;min-height:100vh;-webkit-font-smoothing:antialiased;transition:background .3s,color .3s;overflow-x:hidden}
body::before{content:"";position:fixed;top:0;bottom:0;left:-250px;right:0;z-index:-2;pointer-events:none;background:repeating-linear-gradient(90deg,transparent 0 118px,rgba(var(--fx),.045) 118px 250px);-webkit-mask:linear-gradient(to bottom,transparent 30%,#000 100%);mask:linear-gradient(to bottom,transparent 30%,#000 100%);animation:drift 40s linear infinite}
body::after{content:"";position:fixed;inset:0;z-index:-1;pointer-events:none;background:radial-gradient(900px 380px at 50% -8%,color-mix(in srgb,var(--ac) 13%,transparent),transparent 70%),linear-gradient(to top,rgba(var(--fx),.10),transparent 38%)}
@keyframes drift{to{transform:translateX(250px)}}
@keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@keyframes pop{from{opacity:0;transform:scale(.96) translateY(8px)}to{opacity:1;transform:none}}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
@keyframes glow{0%,100%{box-shadow:0 0 0 0 #fbbf2400,0 10px 30px #00000055}50%{box-shadow:0 0 0 8px #fbbf2412,0 10px 34px #ef444424}}
button,input,select,textarea{font:inherit;color:inherit}
.ic{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex:none}
.mk{width:42px;height:42px;border-radius:13px;background:var(--tx);display:grid;place-items:center;flex:none;animation:glow 5s ease-in-out infinite}.mk svg{width:22px;height:22px}
.layout{min-height:100vh}
.top{direction:ltr;display:flex;align-items:center;justify-content:space-between;gap:12px;max-width:1240px;margin:0 auto;padding:22px 28px 18px;animation:rise .5s both}
.brand{display:flex;align-items:center;gap:12px;min-width:0}.brand .dr{height:26px;width:auto;flex:none;filter:drop-shadow(0 2px 10px #3b82f650)}
.brand .tt{line-height:1.25;min-width:0}.brand .tt b{display:block;font-size:15px;letter-spacing:.02em}.brand .tt small{display:block;color:var(--mu);font-size:11.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tools{display:flex;gap:10px}
.ibtn{display:inline-flex;align-items:center;gap:8px;height:42px;padding:0 16px;border-radius:14px;border:1px solid var(--line2);background:var(--sunk);color:var(--mu);cursor:pointer;transition:.2s;backdrop-filter:blur(12px)}
.ibtn:hover{color:var(--tx);border-color:var(--tx);transform:translateY(-1px)}.ibtn.sq{padding:0;width:42px;justify-content:center}
.tabs{display:flex;justify-content:center;padding:4px 16px 8px;animation:rise .55s .05s both}
.seg{display:flex;gap:4px;padding:5px;border-radius:18px;background:var(--panel);border:1px solid var(--line2);box-shadow:var(--sh);max-width:100%;overflow-x:auto;scrollbar-width:none}.seg::-webkit-scrollbar{display:none}
.nav{display:inline-flex;align-items:center;gap:8px;white-space:nowrap;background:0;border:0;color:var(--mu);padding:10px 18px;border-radius:13px;cursor:pointer;transition:.22s}
.nav:hover{color:var(--tx);background:var(--sunk)}.nav.on{background:var(--ac);color:var(--acf);font-weight:600;box-shadow:0 6px 18px color-mix(in srgb,var(--ac) 28%,transparent)}
main{max-width:1240px;margin:0 auto;padding:6px 28px 60px}
section{animation:rise .5s both}
.sec{display:flex;align-items:center;gap:14px;color:var(--mu);font-size:12px;font-weight:600;margin:26px 0 12px}.sec::after{content:"";flex:1;height:1px;background:var(--line)}
.panel{direction:ltr;display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:1px;background:var(--gl);border:1px solid var(--line2);border-radius:24px;overflow:hidden;box-shadow:var(--sh);animation:rise .6s both}
.panel.two{grid-template-columns:repeat(auto-fit,minmax(300px,1fr))}
.cell{background:var(--panel);padding:22px 24px;direction:ltr;text-align:left;transition:background .25s}.cell:hover{background:color-mix(in srgb,var(--panel) 92%,var(--tx))}
.hd{display:flex;align-items:baseline;gap:8px}.v{font-size:34px;font-weight:700;letter-spacing:-.03em;line-height:1.1}.v small{font-size:15px;font-weight:500;color:var(--mu);margin-left:2px;letter-spacing:0}.v.sm{font-size:20px;letter-spacing:-.01em}
.l{color:var(--mu);font-size:13px}.s{color:var(--mu);font-size:12px;margin-top:14px;direction:ltr}
.pb{height:11px;margin-top:22px;direction:ltr;background:var(--line2);-webkit-mask:repeating-linear-gradient(90deg,#000 0 12px,transparent 12px 16px);mask:repeating-linear-gradient(90deg,#000 0 12px,transparent 12px 16px)}
.pb i{display:block;height:100%;width:0;background:var(--ac);transition:width .9s cubic-bezier(.2,.7,.2,1)}
.hist{display:flex;gap:4px;align-items:flex-end;height:64px;margin-top:16px;direction:ltr}.hist i{flex:1;min-height:6px;background:var(--line2);border-radius:3px;transition:height .6s cubic-bezier(.2,.7,.2,1)}.hist i:last-child{background:var(--ac)}
.btn{border:1px solid var(--line2);background:var(--sunk);color:var(--tx);padding:8px 16px;border-radius:12px;cursor:pointer;transition:.18s}
.btn:hover{border-color:var(--tx);transform:translateY(-1px)}.btn:active{transform:scale(.97)}.btn.p{background:var(--ac);color:var(--acf);border-color:var(--ac);font-weight:600}.btn.on{border-color:var(--ac);box-shadow:inset 0 0 0 1px var(--ac)}
.btn.d{color:var(--er)}.btn.d:hover{border-color:var(--er)}.btn:disabled{opacity:.45;cursor:default;transform:none}
h1{font-size:19px;margin:22px 0 16px;letter-spacing:-.01em}
.card{background:var(--panel);border:1px solid var(--line2);border-radius:22px;padding:22px;margin-bottom:16px;box-shadow:var(--sh);animation:rise .55s both}
.bar{display:flex;justify-content:space-between;align-items:center;margin:22px 0 14px}.bar h2,.bar h1{margin:0}
table{width:100%;border-collapse:collapse}th,td{padding:13px 12px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}
th{color:var(--mu);font-weight:500;font-size:12px}tr:last-child td{border:0}tbody tr{transition:background .15s}tbody tr:hover td{background:rgba(var(--fx),.025)}
.ltr{direction:ltr;text-align:right;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px}
.tbl{overflow-x:auto}.tag{padding:2px 10px;border-radius:20px;font-size:11px;background:var(--sunk);border:1px solid var(--line2);text-transform:uppercase}
.pill{display:inline-flex;align-items:center;gap:6px;padding:3px 11px;border-radius:20px;font-size:12px}.pill::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor}
.pill.up{background:#22c55e1f;color:var(--ok)}.pill.up::before{animation:pulse 2s infinite}.pill.down{background:#ef44441f;color:var(--er)}.pill.unknown{background:var(--sunk);color:var(--mu)}
.mb{height:4px;border-radius:4px;background:var(--line2);margin-top:5px;min-width:110px;overflow:hidden}.mb i{display:block;height:100%;transition:width .6s}
.empty{text-align:center;color:var(--mu);padding:34px}
.modal{position:fixed;inset:0;background:#000a;backdrop-filter:blur(6px);display:none;place-items:center;padding:16px;z-index:20}.modal.on{display:grid;animation:rise .2s both}
.box{background:var(--panel);border:1px solid var(--line2);border-radius:24px;padding:24px;width:100%;max-width:470px;max-height:92vh;overflow:auto;box-shadow:var(--sh);animation:pop .3s cubic-bezier(.2,.7,.2,1) both}
.box h3{margin:0 0 14px;font-size:17px}label{display:block;color:var(--mu);font-size:12px;margin:12px 0 5px}
input,select,textarea{width:100%;background:var(--f);border:1px solid var(--line2);color:var(--tx);border-radius:13px;padding:11px 13px;direction:ltr;text-align:left;transition:.18s}
input:focus,select:focus,textarea:focus{outline:0;border-color:var(--ac);box-shadow:0 0 0 4px color-mix(in srgb,var(--ac) 18%,transparent)}.row{display:flex;gap:10px}.row>*{flex:1}.acts{display:flex;gap:10px;margin-top:18px;flex-wrap:wrap}
.hint{color:var(--mu);font-size:12px;margin-top:6px}
.hl{display:flex;gap:12px;align-items:flex-start;padding:12px 0;border-bottom:1px solid var(--line)}.hl:last-child{border:0}
.hl b{font-size:16px;line-height:1.3}.hl .ok{color:var(--ok)}.hl .warn{color:var(--wa)}.hl .err{color:var(--er)}.hl code{display:block;direction:ltr;text-align:left;color:var(--mu);font-size:12px;margin-top:2px}
.lg{font:12px/1.9 ui-monospace,Menlo,Consolas,monospace;direction:ltr;text-align:left;max-height:62vh;overflow:auto}.lg .warn{color:var(--wa)}.lg .info{color:var(--mu)}.lg .err{color:var(--er)}
.qh{display:flex;gap:18px;align-items:center;margin:4px 0 14px}.ringw{position:relative;width:112px;height:112px;flex:none}.ringw svg{width:112px;height:112px;transform:rotate(-90deg)}
.trk{stroke:var(--line2);stroke-width:9;fill:none}.arc{stroke-width:9;fill:none;stroke-linecap:round;transition:stroke-dasharray .6s}.mid{position:absolute;inset:0;display:grid;place-items:center;font-size:21px;font-weight:700}
.qn{flex:1;display:grid;gap:6px}.qn div{display:flex;justify-content:space-between;gap:8px}.qn span{color:var(--mu)}.qn b{direction:ltr}
.pre{display:flex;flex-wrap:wrap;gap:8px}.qs{padding:10px 12px;border-radius:12px;margin:0 0 12px;font-size:13px;background:var(--sunk)}.qs.er{color:var(--er);background:#ef444419}
.by{display:block;text-align:center;color:var(--mu);font-size:11.5px;direction:ltr;text-decoration:none;transition:.2s}.by:hover{color:var(--tx)}
#login{min-height:100vh;display:grid;place-items:center;padding:20px}
#login .lbox{width:100%;max-width:420px;background:var(--panel);border:1px solid var(--line2);border-radius:28px;box-shadow:var(--sh);overflow:hidden;animation:pop .6s cubic-bezier(.2,.7,.2,1) both}
#login .lin{padding:36px 30px 28px}#login .hero{text-align:center;margin-bottom:26px}#login .hero .mk{width:62px;height:62px;border-radius:19px;margin:0 auto 16px}#login .hero .mk svg{width:32px;height:32px}
#login .hero .dr{height:30px;width:auto;display:block;margin:0 auto 6px;filter:drop-shadow(0 2px 12px #3b82f655)}#login .hero h2{margin:0;font-size:19px;letter-spacing:.01em}#login .hero p{margin:4px 0 0;color:var(--mu);font-size:13px}
#login label{margin:0 0 7px}
.pwf{position:relative}.pwf input{padding:15px 48px 15px 16px;border-radius:16px;font-size:15px}.pwf .lk{position:absolute;left:auto;right:16px;top:50%;transform:translateY(-50%);color:var(--mu);pointer-events:none}
.pwf input{padding-right:46px;padding-left:46px}.pwf .lk{right:auto;left:16px}.pwf input{padding-left:44px;padding-right:46px}
.pwf .eye{position:absolute;right:8px;top:50%;transform:translateY(-50%);width:36px;height:36px;display:grid;place-items:center;border:0;background:0;color:var(--mu);border-radius:10px;cursor:pointer;transition:.18s}.pwf .eye:hover{color:var(--tx);background:var(--sunk)}
#login .go{width:100%;margin-top:14px;padding:14px;border-radius:16px;font-size:15px;display:flex;align-items:center;justify-content:center;gap:10px}#login .go .ic{transition:transform .2s;transform:scaleX(-1)}#login .go:hover .ic{transform:scaleX(-1) translateX(5px)}
#login .ft{border-top:1px solid var(--line);padding:16px;background:rgba(var(--fx),.02)}
#toast{position:fixed;bottom:22px;left:50%;transform:translateX(-50%);display:grid;gap:8px;z-index:30}
.t{background:var(--panel);border:1px solid var(--line2);border-radius:14px;padding:11px 18px;box-shadow:var(--sh);animation:pop .3s both}.t.e{border-color:var(--er)}.t.s{border-color:var(--ok)}
.hide{display:none!important}details summary{cursor:pointer;color:var(--mu);margin-top:14px}
@media(max-width:800px){.top{padding:16px 16px 12px}.brand .tt small{max-width:150px}.ibtn span{display:none}.ibtn{padding:0;width:42px;justify-content:center}.tabs{justify-content:flex-start;padding:4px 12px 6px}main{padding:6px 14px 40px}.v{font-size:28px}.cell{padding:18px}.row{flex-direction:column}.qh{flex-direction:column;align-items:flex-start}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important}}

#login .lgl{position:fixed;top:18px;right:18px;z-index:2}
.sws{display:flex;flex-wrap:wrap;gap:14px;margin:16px 2px 6px}
.sw{position:relative;display:inline-block;width:34px;height:34px;border-radius:50%;border:0;padding:0;background:var(--c);cursor:pointer;transition:transform .18s,box-shadow .18s;box-shadow:inset 0 0 0 1px rgba(var(--fx),.2)}
.sw:hover{transform:scale(1.14)}.sw[data-c=mono]{background:linear-gradient(135deg,#fafafa 50%,#18181b 50%)}
.sw.cu{margin:0;background:conic-gradient(#ef4444,#f59e0b,#22c55e,#06b6d4,#3b82f6,#8b5cf6,#ec4899,#ef4444)}
.sw.on{box-shadow:0 0 0 2px var(--panel),0 0 0 4px var(--c)}
.sw input{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:pointer;padding:0;border:0;border-radius:50%}
#boot{position:fixed;inset:0;z-index:50;display:grid;place-items:center;background:var(--bg);overflow:hidden;transition:opacity .6s,transform .6s,filter .6s;animation:fin .4s both}
#boot::before{content:"";position:absolute;inset:0;background:repeating-linear-gradient(90deg,transparent 0 118px,rgba(var(--fx),.045) 118px 250px);-webkit-mask:linear-gradient(to bottom,transparent 30%,#000 100%);mask:linear-gradient(to bottom,transparent 30%,#000 100%)}
#boot::after{content:"";position:absolute;inset:0;background:radial-gradient(700px 380px at 50% 40%,color-mix(in srgb,var(--ac) 17%,transparent),transparent 70%),linear-gradient(to top,rgba(var(--fx),.09),transparent 40%)}
#boot.out{opacity:0;transform:scale(1.06);filter:blur(8px);pointer-events:none}
.bwrap{position:relative;z-index:1;display:grid;justify-items:center;width:min(340px,86vw);direction:ltr;text-align:center}
.ring{position:relative;width:118px;height:118px;display:grid;place-items:center;margin-bottom:22px}
.ring .rg{position:absolute;inset:0;width:100%;height:100%;transform:rotate(-90deg);overflow:visible}
.ring .r0{fill:none;stroke:var(--line2);stroke-width:2}
.ring .r1{fill:none;stroke:var(--ac);stroke-width:3;stroke-linecap:round;stroke-dasharray:289;stroke-dashoffset:289;transition:stroke-dashoffset .8s cubic-bezier(.3,.7,.2,1);filter:drop-shadow(0 0 5px color-mix(in srgb,var(--ac) 65%,transparent))}
.ring .sp{transform-origin:50px 50px;animation:spin 1.3s linear infinite;transition:opacity .4s}
.ring .sp circle{fill:none;stroke:var(--ac);stroke-width:1.6;stroke-linecap:round;stroke-dasharray:24 265;opacity:.55}
#boot.done .sp{opacity:0}
.ring .mk{width:70px;height:70px;border-radius:22px;animation:glow 3.2s ease-in-out infinite,bob 3.2s ease-in-out infinite}.ring .mk svg{width:35px;height:35px}
#boot.done .ring .mk{animation:glow 3.2s ease-in-out infinite,pulseok .7s both}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-3px)}}
@keyframes fin{from{opacity:0}to{opacity:1}}
@keyframes sweep{from{transform:translateX(-120%)}to{transform:translateX(300%)}}
@keyframes pulseok{0%{transform:scale(1)}40%{transform:scale(1.12)}100%{transform:scale(1)}}
.bwrap .dr{height:34px;width:auto;margin-bottom:6px;filter:drop-shadow(0 2px 12px color-mix(in srgb,var(--pr) 45%,transparent))}
.bt{font-weight:700;font-size:14px;letter-spacing:.34em;text-indent:.34em}
.bs{color:var(--mu);font-size:13px;margin:10px 0 28px;min-height:20px}.bs b{color:var(--tx);font-weight:600;margin-inline-start:8px;font-variant-numeric:tabular-nums}
.bsteps{display:grid;gap:12px;width:100%}
.st{display:flex;align-items:center;gap:12px;color:var(--mu);font-size:12.5px;transition:color .3s}
.st .tk{width:17px;height:17px;border-radius:50%;border:1.5px solid var(--line2);display:grid;place-items:center;flex:none;transition:.3s;font-style:normal}
.st .tk svg{width:10px;height:10px;stroke:var(--acf);fill:none;stroke-width:3;stroke-linecap:round;stroke-linejoin:round;opacity:0;transform:scale(.4);transition:.3s}
.st .lb{flex:none;width:124px;text-align:left}
.st i{flex:1;height:3px;border-radius:3px;background:var(--line2);position:relative;overflow:hidden}
.st b{position:absolute;inset:0 auto 0 0;width:0;background:var(--ac);border-radius:3px;transition:width .5s}
.st.run{color:var(--tx)}.st.run .tk{border-color:var(--ac)}.st.run b{width:38%;animation:sweep 1.1s ease-in-out infinite}
.st.ok{color:var(--tx)}.st.ok .tk{background:var(--ac);border-color:var(--ac)}.st.ok .tk svg{opacity:1;transform:none}.st.ok b{width:100%;animation:none}
html[dir=ltr] th,html[dir=ltr] td{text-align:left}
html[dir=ltr] .ltr{text-align:left}
html[dir=ltr] #login .go .ic{transform:none}
html[dir=ltr] #login .go:hover .ic{transform:translateX(5px)}
</style></head><body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
<linearGradient id="gBolt" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fbbf24"/><stop offset="1" stop-color="#ef4444"/></linearGradient>
<linearGradient id="gDR" x1="0" y1="0" x2="1" y2="1"><stop offset="0" style="stop-color:var(--tx)"/><stop offset="1" style="stop-color:var(--pr)"/></linearGradient>
<symbol id="i-bolt" viewBox="0 0 24 24"><path d="M13.5 2 5 13.5h6L9.5 22 19 9.5h-6.2z" fill="url(#gBolt)"/></symbol>
<symbol id="i-dr" viewBox="0 0 76 36"><g transform="skewX(-9) translate(5 0)" fill="none" stroke="url(#gDR)" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h13c10 0 15 6 15 14s-5 14-15 14H4z"/><path d="M43 32V4h12c7 0 10 4 10 8.5S62 21 55 21H43"/><path d="M54 21l11 11"/></g></symbol>
</defs></svg>
<div id="boot"><div class="bwrap">
<div class="ring"><svg class="rg" viewBox="0 0 100 100"><circle class="r0" cx="50" cy="50" r="46"/><circle class="r1" id="b_r" cx="50" cy="50" r="46"/><g class="sp"><circle cx="50" cy="50" r="46"/></g></svg><i class="mk"><svg><use href="#i-bolt"/></svg></i></div>
<svg class="dr" viewBox="0 0 76 36" aria-label="DR"><use href="#i-dr"/></svg><div class="bt">CPANEL</div>
<div class="bs"><span id="b_s">در حال بارگذاری…</span><b id="b_p">0%</b></div>
<div class="bsteps"><div class="st"><em class="tk"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></em><span class="lb">احراز هویت</span><i><b></b></i></div><div class="st"><em class="tk"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></em><span class="lb">داده‌های سرور</span><i><b></b></i></div><div class="st"><em class="tk"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></em><span class="lb">رابط کاربری</span><i><b></b></i></div></div></div></div>
<div id="login" class="hide"><button class="ibtn lng lgl" type="button" title="زبان"><svg class="ic" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9S14.5 18.3 12 21c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/></svg><span class="lc">EN</span></button><div class="lbox"><div class="lin">
<div class="hero"><i class="mk"><svg><use href="#i-bolt"/></svg></i><svg class="dr" viewBox="0 0 76 36" aria-label="DR"><use href="#i-dr"/></svg><h2>CPanel</h2><p>ورود به پنل مدیریت تانل</p></div>
<label for="pw">رمز عبور</label>
<div class="pwf"><svg class="ic lk" viewBox="0 0 24 24"><rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg><input id="pw" type="password" placeholder="Password" autocomplete="current-password" autofocus spellcheck="false" autocapitalize="off"><button class="eye" id="eye" type="button" title="نمایش رمز"><svg class="ic" viewBox="0 0 24 24"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg></button></div>
<button class="btn p go" id="lb" type="button">ورود<svg class="ic" viewBox="0 0 24 24"><path d="M5 12h14M13 6l6 6-6 6"/></svg></button>
</div><div class="ft"><a class="by" href="https://t.me/DR_Gojo_Satoruu" target="_blank" rel="noopener">Telegram @DR_Gojo_Satoruu</a></div></div></div>

<div class="layout hide" id="app">
<header class="top"><div class="brand"><i class="mk"><svg><use href="#i-bolt"/></svg></i><svg class="dr" viewBox="0 0 76 36" aria-label="DR"><use href="#i-dr"/></svg><div class="tt"><b>CPanel</b><small><span id="host"></span> · <span id="ver"></span></small></div></div>
<div class="tools"><button class="ibtn lng" type="button" title="زبان"><svg class="ic" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9S14.5 18.3 12 21c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/></svg><span class="lc">EN</span></button><button class="ibtn" id="thm" title="تم"><svg class="ic" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 3v18a9 9 0 0 0 0-18z" fill="currentColor"/></svg><span>ظاهر</span></button><button class="ibtn sq" id="out" title="خروج"><svg class="ic" viewBox="0 0 24 24"><path d="M9 4H5v16h4M16 8l4 4-4 4M20 12H9"/></svg></button></div></header>
<nav class="tabs"><div class="seg"><button class="nav on" data-p="dash"><svg class="ic" viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg><span>داشبورد</span></button><button class="nav" data-p="tun"><svg class="ic" viewBox="0 0 24 24"><path d="M3 12h4l3-7 4 14 3-7h4"/></svg><span>تانل‌ها</span></button><button class="nav" data-p="health"><svg class="ic" viewBox="0 0 24 24"><path d="M12 3 4 6v6c0 4.5 3.4 8 8 9 4.6-1 8-4.5 8-9V6z"/><path d="m9 12 2 2 4-4"/></svg><span>بررسی سلامت</span></button><button class="nav" data-p="logs"><svg class="ic" viewBox="0 0 24 24"><path d="M6 3h9l4 4v14H6z"/><path d="M9 12h7M9 16h7"/></svg><span>لاگ‌ها</span></button><button class="nav" data-p="set"><svg class="ic" viewBox="0 0 24 24"><path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/></svg><span>تنظیمات</span></button></div></nav>
<main>
<section id="p_dash">
<div class="sec">سرور</div>
<div class="panel">
<div class="cell"><div class="hd"><b class="v" id="c_cpu">0<small>%</small></b><span class="l">CPU</span></div><div class="pb"><i id="b_cpu"></i></div><div class="s" id="s_load">—</div></div>
<div class="cell"><div class="hd"><b class="v" id="c_ram">0<small>%</small></b><span class="l">RAM</span></div><div class="pb"><i id="b_ram"></i></div><div class="s" id="s_ram">—</div></div>
<div class="cell"><div class="hd"><b class="v" id="c_dsk">0<small>%</small></b><span class="l">دیسک</span></div><div class="pb"><i id="b_dsk"></i></div><div class="s" id="s_dsk">—</div></div>
</div>
<div class="panel two" style="margin-top:14px">
<div class="cell"><div class="hd"><b class="v" id="c_dn">0<small>B/s</small></b><span class="l">Download</span></div><div class="hist" id="h_dn"></div><div class="s" id="s_dn">—</div></div>
<div class="cell"><div class="hd"><b class="v" id="c_up">0<small>B/s</small></b><span class="l">Upload</span></div><div class="hist" id="h_up"></div><div class="s" id="s_up">—</div></div>
</div>
<div class="sec">تانل‌ها</div>
<div class="panel">
<div class="cell"><div class="hd"><b class="v" id="t_n">0</b><span class="l">تانل</span></div><div class="s" id="t_ud">—</div></div>
<div class="cell"><div class="hd"><b class="v" id="t_b">0 B</b><span class="l">ترافیک کل</span></div><div class="s" id="t_p">—</div></div>
<div class="cell"><div class="hd"><b class="v" id="t_s">0 B/s</b><span class="l">سرعت لحظه‌ای</span></div><div class="s">live</div></div>
<div class="cell"><div class="hd"><b class="v sm" id="t_fw">—</b></div><div class="s" id="t_cc">—</div></div>
</div>
<div class="sec">وضعیت تانل‌ها</div>
<div class="card"><div class="tbl"><table><thead><tr><th>نام</th><th>مسیر</th><th>وضعیت</th><th>پینگ</th><th>نمودار</th><th>سرعت</th></tr></thead><tbody id="tb_d"></tbody></table></div></div></section>

<section id="p_tun" class="hide"><div class="bar"><h1 style="margin:0">تانل‌ها</h1><button class="btn p" id="add">+ افزودن تانل</button></div>
<div class="card"><div class="tbl"><table><thead><tr><th>#</th><th>نام</th><th>پروتکل</th><th>پورت ورودی</th><th>مقصد</th><th>وضعیت</th><th>پینگ</th><th>حجم (مصرف / سقف)</th><th></th></tr></thead><tbody id="tb_m"></tbody></table></div></div></section>

<section id="p_health" class="hide"><div class="bar"><h1 style="margin:0">بررسی سلامت</h1><button class="btn p" id="hrun">اجرای بررسی</button></div><div class="card" id="hl"><div class="empty">برای شروع «اجرای بررسی» را بزنید</div></div></section>
<section id="p_logs" class="hide"><h1>لاگ‌ها</h1><div class="card"><div class="lg" id="lg"></div></div></section>

<section id="p_set" class="hide"><h1>تنظیمات</h1>
<div class="card"><h2 style="margin-top:0;font-size:16px">رنگ‌بندی و ظاهر</h2>
<div class="hint" style="margin:0">رنگ اصلی پنل را انتخاب کنید؛ روی دکمه‌ها، تب فعال، نوارها و نمودارها اعمال می‌شود.</div>
<div class="sws" id="sws"></div>
<label>زبان</label><div class="acts" style="margin-top:6px"><button class="btn" type="button" data-l="fa">فارسی</button><button class="btn" type="button" data-l="en">English</button></div></div>
<div class="card"><h2 style="margin-top:0;font-size:16px">تلگرام (اعلان قطع/وصل و منابع)</h2>
<div class="row"><div><label>Bot Token</label><input id="g_t" placeholder="123456:ABC…" autocomplete="off"></div><div><label>Chat ID</label><input id="g_c"></div></div>
<label>آدرس API تلگرام (اختیاری — برای سرور ایران با پروکسی/ورکر)</label><input id="g_a" placeholder="https://api.telegram.org">
<div class="hint" id="g_h"></div><div class="acts"><button class="btn p" id="g_s">ذخیره</button><button class="btn" id="g_x">ارسال پیام تست</button></div></div>
<div class="card"><h2 style="margin-top:0;font-size:16px">دامنه و HTTPS</h2>
<div class="hint" id="d_h" style="margin:0 0 8px"></div>
<div class="row"><div><label>دامنه (باید به IP همین سرور اشاره کند)</label><input id="d_d" placeholder="panel.example.com"></div><div><label>ایمیل (اختیاری)</label><input id="d_e" placeholder="you@example.com"></div></div>
<div class="hint">برای گرفتن گواهی Let's Encrypt پورت ۸۰ باید آزاد باشد. تمدید خودکار انجام می‌شود. لینک کاربران هم روی همین دامنه و HTTPS کار می‌کند.</div>
<div class="acts"><button class="btn p" id="d_s">دریافت گواهی و فعال‌سازی</button><button class="btn d" id="d_r">حذف دامنه</button></div>
<details><summary>یا گواهی خودم را وارد می‌کنم</summary><label>Certificate (PEM)</label><textarea id="c_c" rows="4"></textarea><label>Private key (PEM)</label><textarea id="c_k" rows="4"></textarea><div class="acts"><button class="btn" id="c_s">نصب گواهی</button></div></details></div>
<div class="card"><h2 style="margin-top:0;font-size:16px">تغییر رمز</h2>
<div class="row"><div><label>رمز فعلی</label><input id="w_o" type="password"></div><div><label>رمز جدید (حداقل ۸ کاراکتر)</label><input id="w_n" type="password"></div></div>
<div class="acts"><button class="btn p" id="w_s">تغییر رمز</button></div></div>
<div class="card"><h2 style="margin-top:0;font-size:16px">بکاپ و بازیابی</h2>
<div class="hint" style="margin:0 0 10px">بکاپ شامل تانل‌ها، تنظیمات پنل، رمز و گواهی است. بازیابی فقط لیست تانل‌ها را برمی‌گرداند.</div>
<div class="acts" style="margin:0"><button class="btn p" id="k_d">دانلود بکاپ</button><button class="btn" id="k_r">بازیابی از فایل</button><input id="k_f" type="file" accept=".gz,.tgz" class="hide"></div></div></section>
</main></div>

<div class="modal" id="m"><div class="box"><h3>افزودن تانل جدید</h3>
<div class="row"><div><label>پورت ورودی (این سرور)</label><input id="f_l" inputmode="numeric"></div><div><label>پروتکل</label><select id="f_p"><option>tcp</option><option>udp</option><option>both</option></select></div></div>
<label>IP سرور خارج</label><input id="f_i" placeholder="1.2.3.4">
<div class="row"><div><label>پورت مقصد (خالی = برابر)</label><input id="f_d" inputmode="numeric"></div><div><label>نام (اختیاری)</label><input id="f_n"></div></div>
<div class="acts"><button class="btn p" id="f_ok">ذخیره</button><button class="btn" id="f_x">انصراف</button></div></div></div>
<div class="modal" id="qm"><div class="box"><h3 id="q_t">حجم تانل</h3><div id="q_b"></div>
<div class="acts"><button class="btn p" id="q_ok">ذخیره</button><button class="btn" id="q_x">بستن</button><button class="btn d" id="q_r">ریست مصرف</button></div></div></div>
<div class="modal" id="sm"><div class="box"><h3 id="s_t">لینک کاربر</h3><div class="hint" style="margin:0 0 10px">صفحه‌ای فقط‌خواندنی که کاربر بدون ورود به پنل، حجم مصرف‌شده و باقی‌مانده‌اش را می‌بیند. آدرس آن حدس‌زدنی نیست.</div><div id="s_b"></div>
<div class="acts"><button class="btn" id="s_x">بستن</button></div></div></div>
<div id="toast"></div>
<script>
const $=id=>document.getElementById(id);let prev=null,timer=null,page="dash";
let LANG="fa";try{LANG=localStorage.getItem("drl")==="en"?"en":"fa"}catch(e){}
const EN={"ورود به پنل مدیریت تانل": "Sign in to the tunnel manager", "رمز عبور": "Password", "نمایش رمز": "Show password", "ورود": "Sign in", "تم": "Theme", "ظاهر": "Appearance", "خروج": "Sign out", "داشبورد": "Dashboard", "تانل‌ها": "Tunnels", "بررسی سلامت": "Health check", "لاگ‌ها": "Logs", "تنظیمات": "Settings", "سرور": "Server", "دیسک": "Disk", "تانل": "Tunnels", "ترافیک کل": "Total traffic", "سرعت لحظه‌ای": "Live speed", "وضعیت تانل‌ها": "Tunnel status", "نام": "Name", "مسیر": "Route", "وضعیت": "Status", "پینگ": "Ping", "نمودار": "Chart", "سرعت": "Speed", "+ افزودن تانل": "+ Add tunnel", "پروتکل": "Protocol", "پورت ورودی": "Listen port", "مقصد": "Destination", "حجم (مصرف / سقف)": "Quota (used / limit)", "اجرای بررسی": "Run check", "برای شروع «اجرای بررسی» را بزنید": "Press “Run check” to start", "تلگرام (اعلان قطع/وصل و منابع)": "Telegram (up/down and resource alerts)", "آدرس API تلگرام (اختیاری — برای سرور ایران با پروکسی/ورکر)": "Telegram API address (optional — for Iran servers via proxy/worker)", "ذخیره": "Save", "ارسال پیام تست": "Send test message", "دامنه و HTTPS": "Domain & HTTPS", "دامنه (باید به IP همین سرور اشاره کند)": "Domain (must point to this server's IP)", "ایمیل (اختیاری)": "Email (optional)", "برای گرفتن گواهی Let's Encrypt پورت ۸۰ باید آزاد باشد. تمدید خودکار انجام می‌شود. لینک کاربران هم روی همین دامنه و HTTPS کار می‌کند.": "To get a Let's Encrypt certificate, port 80 must be free. Renewal is automatic. User links also work on this domain over HTTPS.", "دریافت گواهی و فعال‌سازی": "Get certificate & enable", "حذف دامنه": "Remove domain", "یا گواهی خودم را وارد می‌کنم": "Or I'll enter my own certificate", "نصب گواهی": "Install certificate", "تغییر رمز": "Change password", "رمز فعلی": "Current password", "رمز جدید (حداقل ۸ کاراکتر)": "New password (min. 8 characters)", "بکاپ و بازیابی": "Backup & restore", "بکاپ شامل تانل‌ها، تنظیمات پنل، رمز و گواهی است. بازیابی فقط لیست تانل‌ها را برمی‌گرداند.": "The backup includes tunnels, panel settings, password and certificate. Restore only brings back the tunnel list.", "دانلود بکاپ": "Download backup", "بازیابی از فایل": "Restore from file", "افزودن تانل جدید": "Add new tunnel", "پورت ورودی (این سرور)": "Listen port (this server)", "IP سرور خارج": "Foreign server IP", "پورت مقصد (خالی = برابر)": "Destination port (empty = same)", "نام (اختیاری)": "Name (optional)", "انصراف": "Cancel", "حجم تانل": "Tunnel quota", "حجم تانل —": "Tunnel quota —", "بستن": "Close", "ریست مصرف": "Reset usage", "لینک کاربر": "User link", "صفحه‌ای فقط‌خواندنی که کاربر بدون ورود به پنل، حجم مصرف‌شده و باقی‌مانده‌اش را می‌بیند. آدرس آن حدس‌زدنی نیست.": "A read-only page where the user can see used and remaining data without signing in to the panel. Its address is not guessable.", "خطا": "Error", "آنلاین": "online", "قطع": "offline", "نامشخص": "unknown", "آنلاین ·": "online ·", "هنوز تانلی نساخته‌اید": "No tunnels yet", "حجم تمام": "Quota reached", "تست": "Test", "حجم": "Quota", "لینک": "Link", "حذف": "Delete", "UDP قابل تست نیست": "UDP can't be tested", "مقصد پاسخ نمی‌دهد": "Destination is not responding", "اتصال موفق ·": "Connected ·", "این تانل حذف شود؟": "Delete this tunnel?", "حذف شد": "Deleted", "تانل اضافه شد": "Tunnel added", "در حال بررسی…": "Checking…", "لاگی ثبت نشده": "No logs yet", "•••••• (ذخیره شده — برای تغییر وارد کنید)": "•••••• (saved — enter a new one to change)", "فعال: https://": "Active: https://", "بدون دامنه: گواهی self-signed (مرورگر هشدار می‌دهد)": "No domain: self-signed certificate (the browser will warn)", "HTTPS خاموش است": "HTTPS is off", "اگر سرور ایران به تلگرام دسترسی ندارد، آدرس یک پروکسی/ورکر سازگار با Bot API را در فیلد API بگذارید.": "If the Iran server can't reach Telegram, put the address of a Bot API–compatible proxy/worker in the API field.", "ذخیره شد": "Saved", "پیام تست ارسال شد": "Test message sent", "ارسال ناموفق:": "Send failed:", "رمز تغییر کرد": "Password changed", "لیست تانل‌ها با محتوای این بکاپ جایگزین شود؟": "Replace the tunnel list with this backup's contents?", "بازیابی شد": "Restored", "رمز را وارد کنید": "Enter the password", "مصرف": "Used", "سقف": "Limit", "نامحدود": "Unlimited", "باقی‌مانده": "Remaining", "حجم تمام شده و تانل قطع است. با بالا بردن سقف یا ریست مصرف، خودکار وصل می‌شود.": "The quota is used up and the tunnel is cut off. Raising the limit or resetting usage reconnects it automatically.", "مقدار دلخواه": "Custom amount", "افزودن به سقف:": "Add to limit:", "سقف حجم ذخیره شد": "Quota limit saved", "سقف حجم برداشته شد": "Quota limit removed", "مصرف این تانل صفر شود؟": "Reset this tunnel's usage to zero?", "مصرف صفر شد": "Usage reset", "لینک کاربر —": "User link —", "کپی لینک": "Copy link", "لینک جدید": "New link", "حذف لینک": "Delete link", "ساخت لینک": "Create link", "کپی شد": "Copied", "لینک قبلی از کار می‌افتد. ادامه؟": "The old link will stop working. Continue?", "لینک حذف شود؟": "Delete the link?", "دامنه را وارد کنید": "Enter a domain", "گواهی گرفته می‌شود و پنل ری‌استارت می‌شود. ادامه؟": "A certificate will be issued and the panel will restart. Continue?", "در حال دریافت گواهی؛ تا دو دقیقه صبر کنید…": "Getting the certificate; wait up to two minutes…", "فعال شد؛ در حال انتقال به دامنه…": "Enabled; redirecting to the domain…", "دامنه حذف شود و گواهی self-signed برگردد؟": "Remove the domain and go back to the self-signed certificate?", "انجام شد؛ پنل ری‌استارت می‌شود": "Done; the panel is restarting", "گواهی نصب شد؛ پنل ری‌استارت می‌شود": "Certificate installed; the panel is restarting", "رنگ‌بندی و ظاهر": "Colors & appearance", "رنگ اصلی پنل را انتخاب کنید؛ روی دکمه‌ها، تب فعال، نوارها و نمودارها اعمال می‌شود.": "Pick the panel's main color. It applies to buttons, the active tab, meters and charts.", "زبان": "Language", "در حال بارگذاری…": "Loading…", "احراز هویت": "Authentication", "داده‌های سرور": "Server metrics", "رابط کاربری": "Interface"};
const FA={"Wrong password": "رمز اشتباه است", "Too many attempts, try later": "تلاش‌های زیاد؛ بعداً امتحان کنید", "Too many requests": "درخواست‌های زیاد؛ کمی صبر کنید", "Current password is wrong": "رمز فعلی اشتباه است", "New password must be at least 8 characters": "رمز جدید باید حداقل ۸ کاراکتر باشد", "A forward on this port already exists": "برای این پورت قبلاً تانل ساخته شده", "Invalid IP": "آی‌پی نامعتبر است", "Invalid port": "پورت نامعتبر است", "Port out of range": "پورت خارج از محدوده است", "Invalid protocol": "پروتکل نامعتبر است", "Invalid domain": "دامنه نامعتبر است", "Invalid email": "ایمیل نامعتبر است", "This port is used by the web panel": "این پورت توسط خود پنل استفاده می‌شود", "No such rule": "چنین تانلی وجود ندارد", "Server error": "خطای سرور", "Bad request": "درخواست نامعتبر", "Too large": "حجم داده زیاد است", "Bad action": "عملیات نامعتبر", "Port 80 is busy: Let's Encrypt needs it for a moment": "پورت ۸۰ اشغال است؛ Let's Encrypt لحظه‌ای به آن نیاز دارد", "API address must start with https://": "آدرس API باید با https:// شروع شود", "No forwards found in this file": "در این فایل تانلی پیدا نشد", "Certificate and key are invalid or do not match": "گواهی و کلید نامعتبر یا ناهمخوان‌اند", "Certificate and key must be PEM text": "گواهی و کلید باید متن PEM باشند"};
const RE=new RegExp(Object.keys(EN).sort((a,b)=>b.length-a.length).map(k=>k.replace(/[.*+?^${}()|[\]\\]/g,"\\$&")).join("|"),"g");
const TX=s=>{s=String(s);return LANG==="en"?s.replace(RE,m=>EN[m]):(FA[s]||s)};
const cf=s=>confirm(TX(s));
const ORIG=new WeakMap(),AR=/[\u0600-\u06FF]/;
function walk(root,fn){const w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:n=>/^(SCRIPT|STYLE)$/.test(n.parentNode.nodeName)?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});let n;while(n=w.nextNode())fn(n)}
function tNode(n){const has=ORIG.has(n),o=has?ORIG.get(n):n.nodeValue;if(!has&&!AR.test(o))return;ORIG.set(n,o);const v=LANG==="en"?o.replace(RE,m=>EN[m]):o;if(n.nodeValue!==v)n.nodeValue=v}
function tAttr(el){for(const a of["placeholder","title"]){if(!el.hasAttribute(a))continue;const k="fa"+a[0].toUpperCase()+a.slice(1),cur=el.getAttribute(a);if(AR.test(cur))el.dataset[k]=cur;const o=el.dataset[k];if(o===undefined)continue;const v=LANG==="en"?o.replace(RE,m=>EN[m]):o;if(cur!==v)el.setAttribute(a,v)}}
function tAll(r){if(r.nodeType===1)tAttr(r);walk(r,tNode);r.querySelectorAll&&r.querySelectorAll("[placeholder],[title]").forEach(tAttr)}
new MutationObserver(ms=>{if(LANG!=="en")return;for(const m of ms){if(m.type==="characterData")tNode(m.target);else if(m.type==="attributes")tAttr(m.target);else m.addedNodes.forEach(n=>{if(n.nodeType===3)tNode(n);else if(n.nodeType===1)tAll(n)})}}).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["placeholder","title"]});
function setLang(l){LANG=l==="en"?"en":"fa";try{localStorage.setItem("drl",LANG)}catch(e){}const d=document.documentElement;d.lang=LANG;d.dir=LANG==="en"?"ltr":"rtl";tAll(document.body);
 document.querySelectorAll(".lng .lc").forEach(e=>e.textContent=LANG==="en"?"FA":"EN");document.querySelectorAll("[data-l]").forEach(b=>b.classList.toggle("on",b.dataset.l===LANG));buildSw();bootDraw()}
let ACC="mono";try{ACC=localStorage.getItem("drc")||"mono"}catch(e){}
const ACS=[["mono","سفید","Mono"],["#3b82f6","آبی","Blue"],["#8b5cf6","بنفش","Violet"],["#ec4899","صورتی","Pink"],["#ef4444","قرمز","Red"],["#f97316","نارنجی","Orange"],["#f59e0b","زرد","Amber"],["#22c55e","سبز","Green"],["#06b6d4","فیروزه\u200cای","Cyan"]];
const fgc=h=>{const n=parseInt(h.slice(1),16),r=n>>16,g=n>>8&255,b=n&255;return(r*299+g*587+b*114)/1000>155?"#0a0a0a":"#fff"};
function markSw(){document.querySelectorAll("#sws .sw").forEach(e=>{if(e.classList.contains("cu")){const cu=!ACS.some(a=>a[0]===ACC);e.classList.toggle("on",cu);e.style.setProperty("--c",cu?ACC:"var(--tx)")}else e.classList.toggle("on",e.dataset.c===ACC)})}
function setAc(c){ACC=/^#[0-9a-f]{6}$/i.test(c)?c:"mono";try{localStorage.setItem("drc",ACC)}catch(e){}const st=document.body.style;
 if(ACC==="mono")["--ac","--acf","--pr"].forEach(k=>st.removeProperty(k));else{st.setProperty("--ac",ACC);st.setProperty("--acf",fgc(ACC));st.setProperty("--pr",ACC)}markSw()}
function buildSw(){const en=LANG==="en";$("sws").innerHTML=ACS.map(([v,f,e])=>`<button class="sw" type="button" data-c="${v}" style="--c:${v==="mono"?"var(--tx)":v}" title="${en?e:f}"></button>`).join("")+`<label class="sw cu" title="${en?"Custom":"دلخواه"}"><input type="color" id="ac_c" value="${/^#/.test(ACC)?ACC:"#3b82f6"}"></label>`;markSw()}
const B={el:$("boot"),shown:0,target:0,t:0,min:1200,iv:0},PCT=[12,46,78,100];
function bootDraw(){const n=B.shown;B.el.querySelectorAll(".st").forEach((e,i)=>{e.className="st"+(i<n?" ok":i===n?" run":"")});$("b_r").style.strokeDashoffset=289*(1-PCT[n]/100);$("b_s").textContent=TX("در حال بارگذاری…");$("b_p").textContent=PCT[n]+"%";B.el.classList.toggle("done",n>=3)}
function bootOut(){clearInterval(B.iv);B.el.classList.add("out");setTimeout(()=>B.el.classList.add("hide"),650)}
function bootStart(n,min){B.shown=B.target=n;B.t=Date.now();B.min=min;B.el.classList.remove("hide","out");bootDraw();clearInterval(B.iv);B.iv=setInterval(()=>{if(B.shown<B.target){B.shown++;bootDraw()}else if(B.shown>=3&&Date.now()-B.t>=B.min)bootOut()},380)}
function bootGo(n){if(n>B.target)B.target=n}
function bootFast(){if(B.el.classList.contains("hide")||B.el.classList.contains("out"))return;clearInterval(B.iv);B.shown=B.target=3;bootDraw();setTimeout(bootOut,220)}

const nv=t=>{const i=t.indexOf(" ");return t.slice(0,i)+"<small>"+t.slice(i+1)+"</small>"};
const HD=Array(22).fill(0),HU=Array(22).fill(0);function hist(id,a,v){a.push(v);if(a.length>22)a.shift();const m=Math.max(...a,1);$(id).innerHTML=a.map(x=>`<i style="height:${Math.max(8,x/m*100)}%"></i>`).join("")}
const hb=b=>{const u=["B","KB","MB","GB","TB"];let i=0;b=b||0;while(b>=1024&&i<4){b/=1024;i++}return b.toFixed(i?1:0)+" "+u[i]};
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const toast=(t,k)=>{const e=document.createElement("div");e.className="t "+(k||"");e.textContent=TX(t);$("toast").appendChild(e);setTimeout(()=>e.remove(),3500)};
async function api(p,m,b){const r=await fetch("/api/"+p,{method:m||"GET",headers:{"Content-Type":"application/json"},body:b?JSON.stringify(b):undefined});
 let j={};try{j=await r.json()}catch(e){}if(r.status===401&&p!=="login"){show(false);throw new Error("auth")}if(!r.ok)throw new Error(j.error||"خطا");return j}
function show(on){$("app").classList.toggle("hide",!on);$("login").classList.toggle("hide",on);clearInterval(timer);if(on){bootGo(1);load().then(()=>bootGo(3));timer=setInterval(tick,3000)}else{bootFast();$("pw").focus()}}
function tick(){load();if(page==="logs")logs()}
async function load(){try{render(await api("state"))}catch(e){}}
function nav(p){page=p;document.querySelectorAll(".nav[data-p]").forEach(b=>b.classList.toggle("on",b.dataset.p===p));
 ["dash","tun","health","logs","set"].forEach(x=>$("p_"+x).classList.toggle("hide",x!==p));if(p==="logs")logs();if(p==="set")settings()}
document.querySelectorAll(".nav[data-p]").forEach(b=>b.onclick=()=>nav(b.dataset.p));
function spark(h){const v=(h||[]).map(x=>x==null?-1:x);if(v.length<2)return"";const m=Math.max(...v,1),w=84,H=22,st=w/(v.length-1);
 return `<svg width="${w}" height="${H}">`+v.map((x,i)=>x<0?`<line x1="${i*st}" x2="${i*st}" y1="3" y2="${H}" stroke="#ff5d6c" stroke-width="2"/>`:"").join("")+
 `<polyline fill="none" stroke="#4f8cff" stroke-width="1.6" points="${v.map((x,i)=>x<0?"":(i*st).toFixed(1)+","+(H-2-(x/m)*(H-4)).toFixed(1)).filter(Boolean).join(" ")}"/></svg>`}
const pill=s=>`<span class="pill ${s}">${{up:"آنلاین",down:"قطع",unknown:"نامشخص"}[s]}</span>`;
function bar(id,p){$("b_"+id).style.width=Math.min(100,p)+"%"}
function render(s){
 const y=s.sys||{};$("host").textContent=s.host;$("ver").textContent="v"+s.ver;
 $("c_cpu").innerHTML=(y.cpu||0).toFixed(0)+"<small>%</small>";bar("cpu",y.cpu||0);$("s_load").textContent="load "+(y.load||0).toFixed(2)+" · up "+Math.floor((y.up||0)/86400)+"d "+Math.floor((y.up||0)%86400/3600)+"h";
 const rp=100*(y.ram_used||0)/(y.ram_total||1);$("c_ram").innerHTML=rp.toFixed(0)+"<small>%</small>";bar("ram",rp);$("s_ram").textContent=hb(y.ram_used)+" / "+hb(y.ram_total);
 const dp=100*(y.disk_used||0)/(y.disk_total||1);$("c_dsk").innerHTML=dp.toFixed(0)+"<small>%</small>";bar("dsk",dp);$("s_dsk").textContent=hb(y.disk_used)+" / "+hb(y.disk_total);
 let nd=0,nu=0;if(prev&&prev.t&&y.t>prev.t){nd=(y.rx-prev.rx)/(y.t-prev.t);nu=(y.tx-prev.tx)/(y.t-prev.t)}
 $("c_dn").innerHTML=nv(hb(nd)+"/s");$("c_up").innerHTML=nv(hb(nu)+"/s");hist("h_dn",HD,nd);hist("h_up",HU,nu);$("s_dn").textContent="peak "+hb(Math.max(...HD))+"/s · total "+hb(y.rx);$("s_up").textContent="peak "+hb(Math.max(...HU))+"/s · total "+hb(y.tx);
 let sp={},all=0;if(prev&&prev.now){const dt=s.now-prev.now;s.rules.forEach(r=>{const o=prev.m[r.lport+r.proto];if(o!=null&&dt>0){sp[r.lport+r.proto]=Math.max(0,(r.bytes-o)/dt);all+=sp[r.lport+r.proto]}})}
 prev={now:s.now,t:y.t,rx:y.rx,tx:y.tx,m:Object.fromEntries(s.rules.map(r=>[r.lport+r.proto,r.bytes]))};
 const up=s.rules.filter(r=>r.status==="up").length,dn=s.rules.filter(r=>r.status==="down").length;
 $("t_n").textContent=s.rules.length;$("t_ud").textContent=up+" آنلاین · "+dn+" قطع";
 $("t_b").textContent=hb(s.rules.reduce((a,r)=>a+r.bytes,0));$("t_p").textContent=s.rules.reduce((a,r)=>a+r.packets,0)+" packets";$("t_s").textContent=hb(all)+"/s";
 $("t_fw").innerHTML=`<span style="color:var(${s.ip_forward?"--ok":"--er"})">●</span> IP Forward: ${s.ip_forward?"ON":"OFF"}`;$("t_cc").textContent="TCP: "+s.cc.toUpperCase();
 const ms=r=>r.ms==null?"—":r.ms+" ms";
 $("tb_d").innerHTML=s.rules.length?s.rules.map(r=>`<tr><td>${esc(r.name)}</td><td class="ltr">:${r.lport} → ${r.ip}:${r.dport}</td><td>${pill(r.status)}</td><td class="ltr">${ms(r)}</td><td>${spark(r.hist)}</td><td class="ltr">${hb(sp[r.lport+r.proto]||0)}/s</td></tr>`).join(""):`<tr><td colspan="6" class="empty">هنوز تانلی نساخته‌اید</td></tr>`;
 const qc=r=>{const p=r.limit?Math.min(100,100*r.bytes/r.limit):0,c=r.blocked||p>=90?"var(--er)":p>=70?"var(--wa)":"var(--ok)";return `<div class="ltr">${hb(r.bytes)} / ${r.limit?hb(r.limit):"∞"}</div>${r.limit?`<div class="mb"><i style="width:${p}%;background:${c}"></i></div>`:""}`};
 window.RULES=s.rules;
 $("tb_m").innerHTML=s.rules.length?s.rules.map((r,i)=>`<tr><td>${i+1}</td><td>${esc(r.name)}</td><td><span class="tag">${r.proto}</span></td><td class="ltr">${r.lport}</td><td class="ltr">${r.ip}:${r.dport}</td><td>${r.blocked?'<span class="pill down">حجم تمام</span>':pill(r.status)}</td><td class="ltr">${ms(r)}</td><td>${qc(r)}</td><td><button class="btn" onclick="tst(${i+1},this)">تست</button> <button class="btn" onclick="qopen(${i})">حجم</button> <button class="btn" onclick="sopen(${i})">${r.sub?"🔗 ":""}لینک</button> <button class="btn d" onclick="del(${i+1})">حذف</button></td></tr>`).join(""):`<tr><td colspan="9" class="empty">هنوز تانلی نساخته‌اید</td></tr>`}
async function tst(n,b){b.disabled=true;try{const r=await api("test/"+n,"POST",{});toast(r.udp?"UDP قابل تست نیست":r.ms==null?"مقصد پاسخ نمی‌دهد":"اتصال موفق · "+r.ms+" ms",r.udp?"":r.ms==null?"e":"s")}catch(e){toast(e.message,"e")}b.disabled=false}
async function del(n){if(!cf("این تانل حذف شود؟"))return;try{await api("rules/"+n,"DELETE");toast("حذف شد","s");load()}catch(e){toast(e.message,"e")}}
$("add").onclick=()=>$("m").classList.add("on");$("f_x").onclick=()=>$("m").classList.remove("on");
$("f_ok").onclick=async()=>{try{await api("rules","POST",{lport:$("f_l").value,proto:$("f_p").value,ip:$("f_i").value,dport:$("f_d").value,name:$("f_n").value});
 $("m").classList.remove("on");["f_l","f_d","f_n"].forEach(i=>$(i).value="");toast("تانل اضافه شد","s");load()}catch(e){toast(e.message,"e")}};
$("hrun").onclick=async()=>{$("hl").innerHTML='<div class="empty">در حال بررسی…</div>';try{const r=await api("health");
 $("hl").innerHTML=r.map(i=>`<div class="hl"><b class="${i.level}">${{ok:"✔",warn:"!",err:"✘"}[i.level]}</b><div>${esc(i.msg)}${i.fix&&i.level!=="ok"?`<code>${esc(i.fix)}</code>`:""}</div></div>`).join("")}catch(e){toast(e.message,"e")}};
async function logs(){try{const r=await api("logs");$("lg").innerHTML=r.length?r.map(l=>`<div class="${l.l}">${new Date(l.t*1000).toLocaleString("sv")} [${l.l}] ${esc(l.m)}</div>`).join(""):'<div class="empty">لاگی ثبت نشده</div>'}catch(e){}}
async function settings(){try{const s=await api("settings");$("g_c").value=s.tg_chat;$("g_a").value=s.tg_api;$("g_t").value="";$("g_t").placeholder=s.has_token?"•••••• (ذخیره شده — برای تغییر وارد کنید)":"123456:ABC…";
 $("d_h").textContent=s.domain?"فعال: https://"+s.domain+":"+s.port:(s.tls?"بدون دامنه: گواهی self-signed (مرورگر هشدار می‌دهد)":"HTTPS خاموش است");$("g_h").textContent="اگر سرور ایران به تلگرام دسترسی ندارد، آدرس یک پروکسی/ورکر سازگار با Bot API را در فیلد API بگذارید."}catch(e){}}
$("g_s").onclick=async()=>{try{await api("settings/telegram","POST",{token:$("g_t").value,chat:$("g_c").value,api:$("g_a").value});toast("ذخیره شد","s");settings()}catch(e){toast(e.message,"e")}};
$("g_x").onclick=async()=>{try{await api("settings/tgtest","POST",{});toast("پیام تست ارسال شد","s")}catch(e){toast("ارسال ناموفق: "+e.message,"e")}};
$("w_s").onclick=async()=>{try{await api("settings/password","POST",{old:$("w_o").value,new:$("w_n").value});$("w_o").value=$("w_n").value="";toast("رمز تغییر کرد","s")}catch(e){toast(e.message,"e")}};
$("k_d").onclick=async()=>{try{const r=await fetch("/api/backup");if(!r.ok)throw new Error("خطا");const a=document.createElement("a");a.href=URL.createObjectURL(await r.blob());a.download="dr-cpanel-backup.tar.gz";a.click()}catch(e){toast(e.message,"e")}};
$("k_r").onclick=()=>$("k_f").click();
$("k_f").onchange=async e=>{const f=e.target.files[0];if(!f)return;if(!cf("لیست تانل‌ها با محتوای این بکاپ جایگزین شود؟"))return;
 const buf=new Uint8Array(await f.arrayBuffer());let s="";for(let i=0;i<buf.length;i+=8192)s+=String.fromCharCode.apply(null,buf.subarray(i,i+8192));
 try{await api("restore","POST",{data:btoa(s)});toast("بازیابی شد","s");load()}catch(x){toast(x.message,"e")}e.target.value=""};
async function login(){if(!$("pw").value){toast("رمز را وارد کنید","e");return}try{await api("login","POST",{password:$("pw").value});$("pw").value="";bootStart(1,1500);show(true)}catch(e){toast(e.message,"e")}}
$("login").addEventListener("click",e=>{if(!e.target.closest("button,a,input"))$("pw").focus()});
document.addEventListener("keydown",e=>{if($("login").classList.contains("hide")||e.ctrlKey||e.metaKey||e.altKey||e.key.length!==1)return;const a=document.activeElement;if(a&&a.id==="pw")return;$("pw").focus()});
$("lb").onclick=login;$("pw").addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();login()}});
$("eye").onclick=()=>{const p=$("pw");p.type=p.type==="password"?"text":"password";p.focus()};
$("out").onclick=async()=>{await api("logout","POST",{}).catch(()=>{});show(false)};

document.body.dataset.t=localStorage.getItem("drt")||"dark";
$("thm").onclick=()=>{const t=document.body.dataset.t==="dark"?"light":"dark";document.body.dataset.t=t;localStorage.setItem("drt",t)};
const GB=1024**3,TB=1024**4;let QR=null,QW=0,SR=null;
function qopen(i){QR=window.RULES[i];QW=QR.limit||0;$("q_t").textContent="حجم تانل — "+QR.name;$("qm").classList.add("on");qdraw()}
function qdraw(){const r=QR,u=r.bytes,w=QW,p=w?Math.min(1,u/w):0,col=!w?"var(--mu)":p>=.9?"var(--er)":p>=.7?"var(--wa)":"var(--ok)";
 $("q_b").innerHTML=`<div class="qh"><div class="ringw"><svg viewBox="0 0 120 120"><circle class="trk" cx="60" cy="60" r="52"/><circle class="arc" cx="60" cy="60" r="52" pathLength="1000" stroke="${col}" stroke-dasharray="${Math.round(p*1000)} 1000"/></svg><div class="mid">${w?Math.round(p*100)+"%":"∞"}</div></div>
 <div class="qn"><div><span>مصرف</span><b>${hb(u)}</b></div><div><span>سقف</span><b>${w?hb(w):"نامحدود"}</b></div><div><span>باقی‌مانده</span><b>${w?hb(Math.max(0,w-u)):"—"}</b></div></div></div>
 ${r.blocked?'<div class="qs er">حجم تمام شده و تانل قطع است. با بالا بردن سقف یا ریست مصرف، خودکار وصل می‌شود.</div>':""}
 <div class="pre">${[[0,"نامحدود"],[50*GB,"50 GB"],[100*GB,"100 GB"],[500*GB,"500 GB"],[TB,"1 TB"],[2*TB,"2 TB"]].map(([v,l])=>`<button class="btn${v===w?" on":""}" data-v="${v}">${l}</button>`).join("")}</div>
 <div class="row" style="margin-top:10px"><input id="q_n" type="number" min="0" step="any" placeholder="مقدار دلخواه"><select id="q_u"><option value="${GB}">GB</option><option value="${TB}">TB</option></select></div>
 <div class="pre" style="margin-top:10px"><span class="hint" style="align-self:center;margin:0">افزودن به سقف:</span>${[10*GB,100*GB,TB].map(a=>`<button class="btn" data-a="${a}">+ ${hb(a)}</button>`).join("")}</div>`;
 $("q_ok").disabled=w===(r.limit||0);$("q_r").disabled=!r.bytes}
$("q_b").onclick=e=>{const b=e.target.closest("button");if(!b)return;if(b.dataset.v!==undefined)QW=+b.dataset.v;else if(b.dataset.a)QW=(QW||QR.bytes||0)+ +b.dataset.a;else return;qdraw()};
$("q_b").oninput=e=>{if(e.target.id==="q_n"||e.target.id==="q_u"){const n=+$("q_n").value;if(n>0){QW=Math.round(n*+$("q_u").value);$("q_ok").disabled=QW===(QR.limit||0)}}};
$("q_b").onchange=e=>{if(e.target.id==="q_n")qdraw()};
$("q_x").onclick=()=>$("qm").classList.remove("on");
$("q_ok").onclick=async()=>{try{await api("quota","POST",{lport:QR.lport,limit:QW});toast(QW?"سقف حجم ذخیره شد":"سقف حجم برداشته شد","s");$("qm").classList.remove("on");load()}catch(e){toast(e.message,"e")}};
$("q_r").onclick=async()=>{if(!cf("مصرف این تانل صفر شود؟"))return;try{await api("quota","POST",{lport:QR.lport,reset:true});toast("مصرف صفر شد","s");$("qm").classList.remove("on");load()}catch(e){toast(e.message,"e")}};
async function sopen(i){SR=window.RULES[i];$("s_t").textContent="لینک کاربر — "+SR.name;$("sm").classList.add("on");sdraw(await api("sub?lport="+SR.lport))}
function sdraw(j){$("s_b").innerHTML=j.token?`<input id="s_u" readonly value="${esc(location.origin+j.path)}"><div class="acts"><button class="btn p" data-s="copy">کپی لینک</button><button class="btn" data-s="rotate">لینک جدید</button><button class="btn d" data-s="delete">حذف لینک</button></div>`:`<div class="acts" style="margin:0"><button class="btn p" data-s="create">ساخت لینک</button></div>`}
$("s_b").onclick=async e=>{const b=e.target.closest("button");if(!b)return;const a=b.dataset.s;try{
 if(a==="copy"){const el=$("s_u");try{await navigator.clipboard.writeText(el.value)}catch(x){el.select();document.execCommand("copy")}toast("کپی شد","s");return}
 if(a==="rotate"&&!cf("لینک قبلی از کار می‌افتد. ادامه؟"))return;if(a==="delete"&&!cf("لینک حذف شود؟"))return;
 sdraw(await api("sub","POST",{lport:SR.lport,action:a}));load()}catch(x){toast(x.message,"e")}};
$("s_x").onclick=()=>$("sm").classList.remove("on");
$("d_s").onclick=async()=>{const d=$("d_d").value.trim();if(!d)return toast("دامنه را وارد کنید","e");if(!cf("گواهی گرفته می‌شود و پنل ری‌استارت می‌شود. ادامه؟"))return;
 $("d_s").disabled=true;toast("در حال دریافت گواهی؛ تا دو دقیقه صبر کنید…");try{await api("domain","POST",{domain:d,email:$("d_e").value});toast("فعال شد؛ در حال انتقال به دامنه…","s");setTimeout(()=>location.href="https://"+d+":"+(location.port||443)+"/",4500)}catch(e){toast(e.message,"e")}$("d_s").disabled=false};
$("d_r").onclick=async()=>{if(!cf("دامنه حذف شود و گواهی self-signed برگردد؟"))return;try{await api("domain","POST",{remove:true});toast("انجام شد؛ پنل ری‌استارت می‌شود","s");setTimeout(()=>location.reload(),4500)}catch(e){toast(e.message,"e")}};
$("c_s").onclick=async()=>{try{await api("cert","POST",{cert:$("c_c").value,key:$("c_k").value});toast("گواهی نصب شد؛ پنل ری‌استارت می‌شود","s");setTimeout(()=>location.reload(),4500)}catch(e){toast(e.message,"e")}};
document.querySelectorAll(".lng").forEach(b=>b.onclick=()=>setLang(LANG==="en"?"fa":"en"));document.querySelectorAll("[data-l]").forEach(b=>b.onclick=()=>setLang(b.dataset.l));
$("sws").onclick=e=>{const b=e.target.closest(".sw[data-c]");if(b)setAc(b.dataset.c)};$("sws").oninput=e=>{if(e.target.id==="ac_c")setAc(e.target.value)};
setAc(ACC);setLang(LANG);bootStart(0,900);
api("state").then(()=>{bootGo(1);show(true)}).catch(()=>show(false));
</script></body></html>
HTMLEOF
}

web_pubip() {   # public IPv4 of this server (validated, so error pages never leak into the URL)
  local re='^[0-9]{1,3}(\.[0-9]{1,3}){3}$' ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  if ! [[ $ip =~ $re ]] || [[ $ip =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    ip=$(curl -s4 --max-time 4 https://api.ipify.org 2>/dev/null)
  fi
  [[ $ip =~ $re ]] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "$ip"
}

web_info() {
  [[ -f $WEB_PY ]] || { err "Web panel is not installed."; return; }
  local port scheme dom host; read -r port scheme dom < <(python3 "$WEB_PY" info)
  host=$(web_pubip); [[ ${dom:--} != "-" ]] && host=$dom
  ok "URL: ${scheme}://${host}:${port}"
  info "Service: $(systemctl is-active dr-cpanel-web 2>/dev/null)"
  command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active" && warn "ufw is active: ufw allow ${port}/tcp"
}

web_install() {
  banner; echo "  ${C_BLD}Install / update web panel${C_RST}"; echo
  command -v python3 >/dev/null 2>&1 || {
    warn "python3 not found, installing..."
    if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq python3
    elif command -v dnf >/dev/null 2>&1; then dnf install -y python3
    elif command -v yum >/dev/null 2>&1; then yum install -y python3; fi
  }
  command -v python3 >/dev/null 2>&1 || { err "python3 is required."; return; }
  ensure_boot
  local fresh=0 port pw; [[ -f $WEB_CFG ]] || fresh=1
  web_write_files
  if (( fresh )); then
    read -rp "  Web panel port [8443]: " port; port=${port:-8443}
    valid_port "$port" || { err "Invalid port."; return; }
    pw=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 14)
    read -rp "  Admin password [$pw]: " p2; pw=${p2:-$pw}
    python3 "$WEB_PY" setport "$port"; python3 "$WEB_PY" setpass "$pw"
    if command -v openssl >/dev/null 2>&1 && \
       openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=dr-cpanel" \
         -keyout "$CONF_DIR/web.key" -out "$CONF_DIR/web.crt" >/dev/null 2>&1; then
      chmod 600 "$CONF_DIR/web.key"; python3 "$WEB_PY" settls 1
      info "HTTPS enabled (self-signed certificate: the browser will warn once)."
    else
      warn "openssl not found: panel runs on plain HTTP."
    fi
  fi
  cat > "$WEB_UNIT" <<EOF
[Unit]
Description=DR-CPanel web panel
After=network-online.target

[Service]
ExecStart=/usr/bin/env python3 $WEB_PY serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable dr-cpanel-web.service >/dev/null 2>&1
  systemctl restart dr-cpanel-web.service
  sleep 1
  if systemctl is-active --quiet dr-cpanel-web.service; then
    ok "Web panel is running."; web_info
    (( fresh )) && ok "Password: $pw  (change it from this menu any time)"
  else
    err "Service failed to start: journalctl -u dr-cpanel-web -n 20"
  fi
}

web_passwd() {
  [[ -f $WEB_PY ]] || { err "Web panel is not installed."; return; }
  local pw; info "Paste with right-click or Shift+Insert (Ctrl+C would cancel the script)."
  read -rp "  New password (min 8 chars): " pw
  (( ${#pw} >= 8 )) || { err "Too short."; return; }
  python3 "$WEB_PY" setpass "$pw" && systemctl restart dr-cpanel-web && ok "Password changed."
}

web_port() {
  [[ -f $WEB_PY ]] || { err "Web panel is not installed."; return; }
  local port; read -rp "  New port: " port
  valid_port "$port" || { err "Invalid port."; return; }
  python3 "$WEB_PY" setport "$port" && systemctl restart dr-cpanel-web && ok "Port changed." && web_info
}

web_remove() {
  systemctl disable --now dr-cpanel-web.service >/dev/null 2>&1
  rm -f "$WEB_UNIT"; systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$WEB_DIR" "$WEB_CFG" "$CONF_DIR/web.crt" "$CONF_DIR/web.key"
  ok "Web panel removed."
}

web_domain() {
  [[ -f $WEB_PY ]] || { err "Web panel is not installed."; return; }
  local d e; read -rp "  Domain (its A record must point to this server): " d; [[ -n $d ]] || return
  read -rp "  Email for Let's Encrypt (optional): " e
  info "Requesting a certificate (port 80 must be free)..."
  if python3 "$WEB_PY" setdomain "$d" "$e"; then systemctl restart dr-cpanel-web; ok "Domain set."; web_info; else err "Failed."; fi
}

web_menu() {
  banner; echo "  ${C_BLD}Web panel${C_RST}"; echo
  if [[ -f $WEB_UNIT ]]; then info "Status: $(systemctl is-active dr-cpanel-web 2>/dev/null)"; else info "Status: not installed"; fi
  echo
  echo "   1) Install / update"
  echo "   2) Show access info"
  echo "   3) Change password"
  echo "   4) Change port"
  echo "   5) Restart"
  echo "   6) Remove web panel"
  echo "   7) Domain + HTTPS (Let's Encrypt)"
  echo "   0) Back"; echo
  local c; read -rp "  Select: " c; echo
  case $c in
    1) web_install;;
    2) web_info;;
    3) web_passwd;;
    4) web_port;;
    5) systemctl restart dr-cpanel-web && ok "Restarted.";;
    6) confirm "Remove the web panel?" && web_remove;;
    7) web_domain;;
  esac
}

# ---------------------------------------------------------- operations ----

list_rules() {
  if [[ ! -s $CONF ]]; then info "No forwards configured yet."; return 0; fi
  printf "  ${C_BLD}%-3s %-16s %-5s %-7s %-23s %-9s %s${C_RST}\n" "#" NAME PROTO LISTEN DESTINATION PACKETS TRAFFIC
  local i=0 name proto lport ip dport pk by
  while IFS='|' read -r name proto lport ip dport; do
    [[ -z $name ]] && continue
    i=$((i+1))
    read -r pk by < <(counters "$proto" "$lport")
    printf "  %-3s %-16s %-5s %-7s %-23s %-9s %s\n" "$i" "$name" "$proto" "$lport" "$ip:$dport" "$pk" "$(hb "$by")"
  done < "$CONF"
}

add_forward() {
  banner; echo "  ${C_BLD}Add forward${C_RST}"; echo
  local lport proto name ip dport defip=""
  read -rp "  Listen port on this server: " lport
  valid_port "$lport" || { err "Invalid port."; return; }
  if ss -ltnH "sport = :$lport" 2>/dev/null | grep -q .; then
    warn "A local service already listens on TCP $lport (SSH?). Forwarding would take the port over."
    confirm "Continue anyway?" || return
  fi
  read -rp "  Protocol tcp/udp/both [tcp]: " proto; proto=${proto:-tcp}
  [[ $proto =~ ^(tcp|udp|both)$ ]] || { err "Invalid protocol."; return; }
  if awk -F'|' -v p="$lport" -v pr="$proto" '$3==p && ($2==pr||$2=="both"||pr=="both"){f=1} END{exit !f}' "$CONF" 2>/dev/null; then
    err "A forward on port $lport already exists."; return
  fi
  [[ -f $DEF_IP_FILE ]] && defip=$(<"$DEF_IP_FILE")
  read -rp "  Foreign server IP${defip:+ [$defip]}: " ip; ip=${ip:-$defip}
  valid_ip "$ip" || { err "Invalid IP."; return; }
  read -rp "  Foreign port [$lport]: " dport; dport=${dport:-$lport}
  valid_port "$dport" || { err "Invalid port."; return; }
  read -rp "  Name [fw$lport]: " name; name=${name:-fw$lport}
  name=${name//[^A-Za-z0-9_.-]/_}

  mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
  echo "$name|$proto|$lport|$ip|$dport" >> "$CONF"
  echo "$ip" > "$DEF_IP_FILE"
  apply_rules; ensure_boot
  echo; ok "Forward added: :$lport -> $ip:$dport ($proto), saved for reboot."
  if [[ $proto != udp ]]; then
    local t; t=$(tcp_time "$ip" "$dport")
    if [[ $t == fail ]]; then
      err "Foreign node did not answer on $dport (refused/timeout). Check the inbound exists and its firewall."
    else
      ok "Foreign node answers on $dport (${t} ms)."
    fi
  fi
  info "In the client config set the address to this server's IP; keep port/UUID/SNI/keys unchanged."
}

remove_forward() {
  banner; echo "  ${C_BLD}Remove forward${C_RST}"; echo
  [[ -s $CONF ]] || { info "Nothing to remove."; return; }
  list_rules; echo
  local n; read -rp "  Number to remove: " n
  [[ $n =~ ^[0-9]+$ ]] && (( n >= 1 && n <= $(wc -l < "$CONF") )) || { err "Invalid number."; return; }
  sed -i "${n}d" "$CONF"
  apply_rules
  ok "Removed."
}

test_forwards() {
  banner; echo "  ${C_BLD}Connection test${C_RST}"; echo
  [[ -s $CONF ]] || { info "No forwards configured."; return; }
  local name proto lport ip dport t out avg loss seen=" "
  while IFS='|' read -r name proto lport ip dport; do
    [[ -z $name ]] && continue
    echo "  ${C_BLD}$name${C_RST}  :$lport -> $ip:$dport ($proto)"
    if [[ $proto != udp ]]; then
      t=$(tcp_time "$ip" "$dport")
      if [[ $t == fail ]]; then err "  TCP connect FAILED"; else ok "  TCP connect ${t} ms"; fi
    else
      info "  UDP cannot be probed"
    fi
    if [[ $seen != *" $ip "* ]]; then
      seen="$seen$ip "
      out=$(ping -c 5 -W 2 -q "$ip" 2>/dev/null </dev/null)
      avg=$(awk -F'/' '/^rtt|^round-trip/{print $5}' <<<"$out")
      loss=$(grep -oE '[0-9.]+%' <<<"$out" | head -1)
      if [[ -n $avg ]]; then ok "  Ping avg ${avg} ms, loss ${loss:-?}"; else warn "  Ping: no reply (ICMP may be blocked)"; fi
    fi
  done < "$CONF"
}

optimize() {
  banner; echo "  ${C_BLD}Optimize (BBR + buffers)${C_RST}"; echo
  modprobe tcp_bbr 2>/dev/null || true
  if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    warn "BBR is not available on this kernel (some VPS types block it). Buffers only."
  fi
  {
    grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null && {
      echo "net.core.default_qdisc=fq"
      echo "net.ipv4.tcp_congestion_control=bbr"
    }
    echo "net.core.rmem_max=16777216"
    echo "net.core.wmem_max=16777216"
    echo "net.ipv4.tcp_rmem=4096 87380 16777216"
    echo "net.ipv4.tcp_wmem=4096 65536 16777216"
    [[ -e /proc/sys/net/netfilter/nf_conntrack_max ]] && echo "net.netfilter.nf_conntrack_max=262144"
  } > "$SYSCTL_OPT"
  sysctl -q -p "$SYSCTL_OPT" >/dev/null 2>&1
  ok "Applied and saved to $SYSCTL_OPT"
  info "Congestion control now: $(sysctl -n net.ipv4.tcp_congestion_control)"
}

backup_restore() {
  banner; echo "  ${C_BLD}Backup & Restore${C_RST}"; echo
  echo "   1) Backup settings"
  echo "   2) Restore from file"
  echo "   0) Back"; echo
  local c f; read -rp "  Select: " c
  case $c in
    1) [[ -d $CONF_DIR ]] || { err "Nothing to back up."; return; }
       f="/root/dr-cpanel-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
       tar czf "$f" -C / "${CONF_DIR#/}" && ok "Saved: $f";;
    2) read -rp "  Backup file path: " f
       [[ -f $f ]] || { err "File not found."; return; }
       tar xzf "$f" -C / "${CONF_DIR#/}" && apply_rules && ensure_boot && ok "Restored and applied.";;
  esac
}

import_legacy() {
  banner; echo "  ${C_BLD}Import manual iptables rules${C_RST}"; echo
  local re='-p ([a-z]+) .*--dport ([0-9]+) .*--to-destination ([0-9.]+):([0-9]+)'
  local line n=0 proto lport ip dport
  while IFS= read -r line; do
    [[ $line == *"-j DNAT"* && $line =~ $re ]] || continue
    proto=${BASH_REMATCH[1]}; lport=${BASH_REMATCH[2]}; ip=${BASH_REMATCH[3]}; dport=${BASH_REMATCH[4]}
    mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
    grep -qF "|$proto|$lport|$ip|$dport" "$CONF" 2>/dev/null || echo "imported-$lport|$proto|$lport|$ip|$dport" >> "$CONF"
    iptables -t nat ${line/#-A/-D}
    # matching manual MASQUERADE rule
    while IFS= read -r m; do
      [[ $m == *"-j MASQUERADE"* && $m == *"-d $ip/32"* && $m == *"--dport $dport "* ]] && iptables -t nat ${m/#-A/-D}
    done < <(iptables -t nat -S POSTROUTING 2>/dev/null)
    n=$((n+1)); ok "Imported :$lport -> $ip:$dport ($proto)"
  done < <(iptables -t nat -S PREROUTING 2>/dev/null)
  if (( n == 0 )); then info "No manual DNAT rules found."; return; fi
  apply_rules; ensure_boot
  ok "$n rule(s) now managed by the panel."
}

status() {
  banner; echo "  ${C_BLD}Status${C_RST}"; echo
  [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] && ok "IP forwarding: on" || err "IP forwarding: off"
  info "Congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
  if command -v systemctl >/dev/null 2>&1; then
    info "Boot service: $(systemctl is-enabled dr-cpanel.service 2>/dev/null || echo not-installed)"
    info "Web panel: $(systemctl is-active dr-cpanel-web.service 2>/dev/null || echo not-installed)"
  fi
  local legacy; legacy=$(iptables -t nat -S PREROUTING 2>/dev/null | grep -c -- '-j DNAT')
  (( legacy > 0 )) && warn "$legacy manual DNAT rule(s) outside the panel (use 'Import manual rules')."
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    warn "ufw is active: allow each listen port (ufw allow <port>/tcp)."
  fi
  echo; list_rules
}

uninstall() {
  banner; echo "  ${C_BLD}Uninstall${C_RST}"; echo
  confirm "Remove all forwards, the web panel, the boot service and this tool?" || return
  web_remove >/dev/null 2>&1
  local spec t parent chain
  for spec in "nat PREROUTING DRC_PRE" "nat POSTROUTING DRC_POST" "filter FORWARD DRC_FWD"; do
    set -- $spec; t=$1; parent=$2; chain=$3
    iptables -t "$t" -D "$parent" -j "$chain" 2>/dev/null
    iptables -t "$t" -F "$chain" 2>/dev/null
    iptables -t "$t" -X "$chain" 2>/dev/null
  done
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now dr-cpanel.service >/dev/null 2>&1
    rm -f "$UNIT"; systemctl daemon-reload >/dev/null 2>&1
  fi
  confirm "Also delete saved settings in $CONF_DIR?" && rm -rf "$CONF_DIR"
  rm -f "$SYSCTL_FWD" "$SYSCTL_OPT" "$BIN"
  ok "Uninstalled."; exit 0
}

main_menu() {
  local c
  while true; do
    banner
    echo "   1) Add forward           new port -> foreign node"
    echo "   2) List forwards         with live traffic counters"
    echo "   3) Remove forward"
    echo "   4) Connection test       TCP connect time and ping"
    echo "   5) Optimize              BBR and buffers"
    echo "   6) Backup & Restore"
    echo "   7) Import manual rules   adopt hand-made iptables rules"
    echo "   8) Status"
    echo "   9) Web panel             install and manage the web UI"
    echo "  10) Uninstall"
    echo "   0) Exit"
    echo
    read -rp "  Select an option: " c
    echo
    case $c in
      1) add_forward; pause;;
      2) banner; list_rules; pause;;
      3) remove_forward; pause;;
      4) test_forwards; pause;;
      5) optimize; pause;;
      6) backup_restore; pause;;
      7) import_legacy; pause;;
      8) status; pause;;
      9) web_menu; pause;;
      10) uninstall;;
      0) exit 0;;
    esac
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  need_root
  ensure_deps
  migrate_legacy
  case "${1:-}" in
    apply) apply_rules;;
    list)  list_rules;;
    update) bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh);;
    "")    main_menu;;
    *)     echo "Usage: $0 [apply|list|update]"; exit 1;;
  esac
fi
