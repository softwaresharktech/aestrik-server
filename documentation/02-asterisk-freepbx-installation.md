# Installing Asterisk + FreePBX

Prerequisite: the server from [01-server-provisioning.md](01-server-provisioning.md) exists, is patched, and has correct NTP time.

## Which install path

Two realistic options:

1. **FreePBX 17 installer on Debian 13 / Ubuntu 24.04** (recommended) — official installer script that compiles/installs a supported **Asterisk 22 LTS** (support through Oct 2028, security fixes to 2029) plus Apache, MariaDB, PHP 8.3, Node.js, and FreePBX itself. This is the path to take if a human admin will also manage trunks/extensions/IVRs through a GUI day to day. ([computingforgeeks.com](https://computingforgeeks.com/install-asterisk-freepbx-debian-ubuntu/), [ipcomms.net](https://www.ipcomms.net/blog/asterisk-debian-13-install/))
2. **Asterisk-only, from source, no GUI** — smaller footprint, fewer moving parts, but every trunk/extension/dialplan change is a hand-edited config file. Only worth it if the system will be 100% API-driven from LamaERP with no human FreePBX admin.

Given the note in [00-overview.md](00-overview.md) that FreePBX's UI is attractive for whoever administers the system, **go with option 1** unless that changes.

## Option 1 — FreePBX 17 on Debian/Ubuntu

Run as root (or with sudo) on the freshly provisioned box:

```bash
apt update && apt -y upgrade
apt -y install git curl wget sudo

# Official FreePBX 17 installer (Debian 12/13; also supports Ubuntu 24.04)
git clone https://github.com/FreePBX/sng_freepbx_debian_install.git
cd sng_freepbx_debian_install
chmod +x sng_freepbx_debian_install.sh
./sng_freepbx_debian_install.sh
```

The script installs and configures, in order: Apache, MariaDB, Node.js, PHP 8.3, then compiles Asterisk 22 LTS with PJSIP support, then installs FreePBX and starts `fwconsole`. It takes a while (source compilation) — expect 20–40+ minutes depending on the box.

After it completes:

```bash
fwconsole ma updateall     # pull latest module versions
fwconsole reload
fwconsole restart
```

Then open `https://<server-ip-or-hostname>/admin` **from an allowlisted admin IP only** (see firewall rules in [01](01-server-provisioning.md)) and complete the first-run wizard: set the admin username/password, accept the license, and let it check for module updates.

### TLS for the admin UI

Use FreePBX's built-in **Certificate Manager** module to issue a Let's Encrypt cert if the box has a public hostname reachable for ACME HTTP-01 validation; otherwise install an internal CA cert, or terminate TLS at a reverse proxy that's already part of DataHub's setup. Never leave the admin UI on plain HTTP.

## Option 2 — Asterisk from source, no FreePBX

Only if the "no GUI" decision is made later:

```bash
apt update && apt -y install build-essential wget libssl-dev libncurses5-dev \
  libnewt-dev libxml2-dev uuid-dev sqlite3 libsqlite3-dev pkg-config \
  subversion libjansson-dev libedit-dev

cd /usr/src
wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz
tar xvf asterisk-22-current.tar.gz
cd asterisk-22*/
contrib/scripts/install_prereq install
./configure
make menuselect   # confirm chan_pjsip, res_ari*, res_stasis, app_confbridge are selected
make -j"$(nproc)"
make install
make samples
make config        # installs the systemd service
ldconfig
systemctl enable --now asterisk
```

## Enabling AMI (Asterisk Manager Interface)

Needed regardless of install path — this is what the ERP backend will use for call origination and event monitoring (details in [04](04-asterisk-apis-ami-ari.md)).

`/etc/asterisk/manager.conf`:

```ini
[general]
enabled = yes
port = 5038
bindaddr = 127.0.0.1   ; bind loopback-only if fronting with a tunnel/VPN to the ERP server; otherwise the private-VPC IP, never a public one

[lamaerp]
secret = <strong-random-secret>          ; generate with `openssl rand -base64 32`
deny = 0.0.0.0/0.0.0.0
permit = <erp-backend-private-ip>/255.255.255.255
read = system,call,agent,user,config
write = system,call,agent,originate
```

If FreePBX is installed, the equivalent is the **"Asterisk API" (manager) module** in the GUI (Settings → Asterisk Manager Users), which writes this same file — prefer doing it there so FreePBX doesn't overwrite manual edits on its next config regeneration.

```bash
asterisk -rx "manager reload"
```

## Enabling ARI (Asterisk REST Interface)

`/etc/asterisk/http.conf`:

```ini
[general]
enabled = yes
bindaddr = <private-VPC-IP or 127.0.0.1 if tunneled>
bindport = 8088
; prefer TLS in production:
; tlsenable = yes
; tlsbindaddr = <private-ip>:8089
; tlscertfile = /etc/asterisk/keys/ari-cert.pem
; tlsprivatekey = /etc/asterisk/keys/ari-key.pem
```

`/etc/asterisk/ari.conf`:

```ini
[general]
enabled = yes
pretty = yes
allowed_origins = 

[lamaerp]
type = user
read_only = no
password = <strong-random-secret>
password_format = plain
```

```bash
asterisk -rx "module reload res_ari.so"
asterisk -rx "http show status"   # confirm it's listening on the expected bind address only
```

In FreePBX, the equivalent GUI location is **Settings → Asterisk REST Interface Users** (module `ariusers`); same guidance as AMI — configure through the GUI when FreePBX is present.

Confirm from the ERP backend host (not from the Asterisk box itself) that the port is reachable, and confirm from anywhere else that it is **not**.

## PJSIP, not chan_sip

Use `chan_pjsip`/`res_pjsip` for all endpoints and trunks — `chan_sip` is deprecated/removed in current Asterisk branches. FreePBX 17 defaults to PJSIP already; if going the from-source route, make sure `chan_pjsip` and its `res_pjsip_*` modules are selected in `make menuselect`.

## Next step

With Asterisk running and AMI/ARI reachable only from the ERP backend, move to [03-freepbx-configuration.md](03-freepbx-configuration.md) to set up trunks, extensions, and IVRs.
