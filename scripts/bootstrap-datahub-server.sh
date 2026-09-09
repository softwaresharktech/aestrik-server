#!/usr/bin/env bash
#
# One-time bootstrap for the DataHub Asterisk + FreePBX server.
# Consolidates documentation/01-server-provisioning.md, 02-asterisk-freepbx-installation.md,
# and 06-security-hardening.md into a single run. NOT part of CI/CD — see
# documentation/09-datahub-production-deployment.md, Step 2, for why this is a deliberate
# one-time (or rare, by-hand re-run) action, not something a push to main re-triggers.
#
# Unlike the Sangoma all-in-one installer (sng_freepbx_debian_install.sh), this does NOT
# bundle a local MariaDB — it installs FreePBX against the separate DataHub DB service
# provisioned in Step 1, using the same --dbhost mechanism already proven to work end-to-end
# in local-dev/ (escomputers/freepbx-docker uses the identical installer under the hood).
#
# Target: Debian 13 (bookworm+) or Ubuntu 24.04 LTS, per documentation/01. Run as root.
#
# Required environment variables:
#   ERP_BACKEND_IP     Private IP of the LamaERP backend — the only host allowed to reach AMI/ARI
#   ADMIN_SSH_CIDR      CIDR allowed to SSH in (e.g. 10.0.0.5/32) — never 0.0.0.0/0
#   DB_HOST             Private IP/hostname of the separate DataHub MariaDB service (Step 1)
#   DB_PASS             Password for 'freepbxuser' created by scripts/configure-external-db.sql
# Optional:
#   DB_USER             Default: freepbxuser
#   DB_NAME              Default: asterisk
#   TRUNK_PROVIDER_CIDR CIDR of the SIP trunk provider's signaling IPs. Default: 0.0.0.0/0 with
#                        a loud warning — tighten this the moment the trunk provider's IP range
#                        is known (documentation/01-server-provisioning.md).
#   ASTERISK_VERSION     Default: 22-current (Asterisk 22 LTS, per documentation/02)
#   FREEPBX_TARBALL      Default: http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

: "${ERP_BACKEND_IP:?Set ERP_BACKEND_IP (private IP of the LamaERP backend)}"
: "${ADMIN_SSH_CIDR:?Set ADMIN_SSH_CIDR (e.g. 10.0.0.5/32) — never leave SSH open to 0.0.0.0/0}"
: "${DB_HOST:?Set DB_HOST (the separate DataHub MariaDB service from Step 1)}"
: "${DB_PASS:?Set DB_PASS (the freepbxuser password from scripts/configure-external-db.sql)}"

DB_USER="${DB_USER:-freepbxuser}"
DB_NAME="${DB_NAME:-asterisk}"
TRUNK_PROVIDER_CIDR="${TRUNK_PROVIDER_CIDR:-0.0.0.0/0}"
ASTERISK_VERSION="${ASTERISK_VERSION:-22-current}"
FREEPBX_TARBALL="${FREEPBX_TARBALL:-http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz}"

if [[ "$TRUNK_PROVIDER_CIDR" == "0.0.0.0/0" ]]; then
  echo "WARNING: TRUNK_PROVIDER_CIDR not set — SIP (5060/udp) will be open to the internet." >&2
  echo "         Set it to your trunk provider's actual signaling IP range as soon as you have it." >&2
fi

log() { echo -e "\n>>> $*\n"; }

# ── 1. Base packages, NTP (documentation/01) ─────────────────────────────────────────────
log "Updating system and installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get -y upgrade
apt-get -y install curl wget git sudo ufw fail2ban chrony ca-certificates gnupg

systemctl enable --now chrony

# ── 2. Firewall (documentation/01, 06) ────────────────────────────────────────────────────
log "Configuring UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$ADMIN_SSH_CIDR" to any port 22 proto tcp comment 'SSH - admin only'
ufw allow from "$TRUNK_PROVIDER_CIDR" to any port 5060 proto udp comment 'SIP signaling'
ufw allow 10000:20000/udp comment 'RTP media'
ufw allow from "$ERP_BACKEND_IP" to any port 5038 proto tcp comment 'AMI - ERP backend only'
ufw allow from "$ERP_BACKEND_IP" to any port 8089 proto tcp comment 'ARI (TLS) - ERP backend only'
ufw --force enable

# ── 3. Build/runtime dependencies (verified against escomputers/freepbx-docker's Dockerfile,
#       the same image local-dev/ already proved builds and installs cleanly) ───────────────
log "Installing Asterisk build dependencies + Apache/PHP/Node runtime"
apt-get -y install \
  build-essential pkg-config cron bison flex libnewt-dev libssl-dev libncurses5-dev \
  subversion libsqlite3-dev libjansson-dev libxml2-dev uuid uuid-dev default-libmysqlclient-dev \
  lame ffmpeg mpg123 expect \
  apache2 mariadb-client \
  php8.2 php8.2-curl php8.2-cli php8.2-common php8.2-mysql php8.2-gd php8.2-mbstring \
  php8.2-intl php8.2-xml php-pear php-soap \
  sox sqlite3 automake libtool autoconf unixodbc-dev \
  libasound2-dev libogg-dev libvorbis-dev libicu-dev libcurl4-openssl-dev \
  odbc-mariadb unixodbc libical-dev libneon27-dev libsrtp2-dev libspandsp-dev libtool-bin \
  nodejs npm

# ── 4. Asterisk 22 LTS from source (documentation/02, Option 2) ──────────────────────────
log "Building Asterisk $ASTERISK_VERSION from source — this takes a while"
cd /usr/src
wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz"
tar xzf "asterisk-${ASTERISK_VERSION}.tar.gz"
cd asterisk-*/
contrib/scripts/install_prereq install
./configure --with-pjproject-bundled --with-jansson-bundled
make menuselect.makeopts
menuselect/menuselect --enable format_mp3 menuselect.makeopts
make -j"$(nproc)"
make install
make samples
make config
ldconfig

groupadd -f asterisk
id -u asterisk &>/dev/null || useradd -r -d /var/lib/asterisk -g asterisk asterisk
usermod -aG audio,dialout asterisk
chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk
sed -i 's|;runuser.*|runuser = "asterisk"|' /etc/asterisk/asterisk.conf
sed -i 's|;rungroup.*|rungroup = "asterisk"|' /etc/asterisk/asterisk.conf
systemctl enable --now asterisk

# ── 5. Apache + PHP tuning for FreePBX ────────────────────────────────────────────────────
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/8.2/apache2/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
a2enmod rewrite
grep -q "^ServerName" /etc/apache2/apache2.conf || echo "ServerName $(hostname -f)" >> /etc/apache2/apache2.conf
systemctl restart apache2

# ── 6. FreePBX against the SEPARATE DataHub DB service ───────────────────────────────────
log "Installing FreePBX 17 against external DB at $DB_HOST"
cd /usr/local/src
wget -q "$FREEPBX_TARBALL" -O freepbx.tgz
tar xzf freepbx.tgz
cd freepbx
./install -n --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST"

fwconsole ma updateall
fwconsole reload
fwconsole restart

# ── 7. AMI user, scoped to the ERP backend only (documentation/02, 04) ───────────────────
log "Provisioning AMI user"
AMI_SECRET="$(openssl rand -base64 32)"
cat >> /etc/asterisk/manager_additional.conf <<EOF

[lamaerp]
secret = ${AMI_SECRET}
deny = 0.0.0.0/0.0.0.0
permit = ${ERP_BACKEND_IP}/255.255.255.255
read = system,call,agent,user,config
write = system,call,agent,originate
EOF

# ── 8. ARI user + TLS HTTP listener, scoped to the ERP backend only ───────────────────────
log "Provisioning ARI user"
ARI_SECRET="$(openssl rand -base64 32)"
sed -i 's/^enabled=no/enabled=yes/' /etc/asterisk/http.conf 2>/dev/null || true
cat >> /etc/asterisk/ari_additional.conf <<EOF

[lamaerp]
type = user
read_only = no
password = ${ARI_SECRET}
password_format = plain
EOF

asterisk -rx "manager reload"
asterisk -rx "module reload res_ari.so"

# ── 9. fail2ban (documentation/06) ────────────────────────────────────────────────────────
systemctl enable --now fail2ban

log "Bootstrap complete."
cat <<EOF

===========================================================================
 Save these now — they are not written to any log file.

 AMI  (lamaerp / manager.conf)  secret: ${AMI_SECRET}
 ARI  (lamaerp / ari.conf)      password: ${ARI_SECRET}

 Put both into the server's production secrets store and the ERP backend's
 own config (documentation/09-datahub-production-deployment.md, Step 4).

 Next: open https://<this-server>/admin to finish the FreePBX first-run
 wizard, then continue with documentation/03-freepbx-configuration.md
 (trunks, extensions, IVR).
===========================================================================
EOF
