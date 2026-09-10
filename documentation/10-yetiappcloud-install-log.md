# YetiApp Cloud Install Log

A running as-built record of installing Asterisk 22 + FreePBX 17 on YetiApp Cloud (a Jelastic-based PaaS), including every wrong turn and the fix for it. This is the "what actually happened" companion to the clean plan in [09-datahub-production-deployment.md](09-datahub-production-deployment.md) — kept separately because the detours are worth remembering.

**Status: in progress.** FreePBX is installed and running; the admin UI is now reachable at `http://103.90.84.156/admin/`. First-run wizard + TLS still to do. Full remaining list in [11-deferred-steps.md](11-deferred-steps.md).

---

## Environment

"DataHub" turned out to be **YetiApp Cloud**, a Jelastic/Virtuozzo-based PaaS — the same host [FinalLamaErp](../../FinalLamaErp) already deploys to (`*.ktm.yetiappcloud.com`).

| Thing | Value |
|---|---|
| Environment | `env-7970601` (`env-7970601.ktm.yetiappcloud.com`) |
| Asterisk/FreePBX node | `node26243-env-7970601`, Ubuntu 24.04, **1 vCPU** (cloudlets scale RAM + CPU GHz, not core count), public egress IP `103.90.84.156` |
| Database node | `node26242-env-7970601`, managed "SQL Databases" node, **MariaDB 10.11**, internal IP `10.121.5.221` (`/16`), no public IP |
| Repo on server | `git clone` at `/opt/lamaerp/asterisk` (also satisfies the CI/CD prerequisite in doc 09) |
| Domain | `sainowine.com.np` (apex, Cloudflare "DNS only") — internal-use domain, being used directly rather than a subdomain |

Approach: **native install** (not Docker) via [scripts/bootstrap-datahub-server.sh](../../scripts/bootstrap-datahub-server.sh), FreePBX pointed at the **separate** managed MariaDB via `--dbhost`.

---

## Timeline

### 1. Database node

- Created a managed "SQL Databases" node. Jelastic's version picker defaulted to **MariaDB 12.3.3**; chose **10.xx → 10.11** instead — 12.x is very new and FreePBX has a history of breaking on newer MariaDB.
- Left horizontal scaling at 1 node (no Galera), Public IPv4 at 0.
- Created the `freepbxuser` account + databases through phpMyAdmin. (This is where the later grief started — see [The database connectivity saga](#4-the-database-connectivity-saga).)

### 2. Server bootstrap — script bugs found and fixed

Ran `bash scripts/bootstrap-datahub-server.sh` repeatedly; each failure exposed a real bug, fixed and pushed:

| Symptom | Root cause | Fix (commit) |
|---|---|---|
| `xargs: unmatched single quote` on startup | `.env.production` parser trimmed values by piping through `xargs`, which re-parses quotes — choked on an apostrophe in the file's own comments ("It's…") | Pure-bash trim, no `xargs` (`d761257`) |
| `ERROR: Bad source address` from `ufw` | Parser didn't strip a **trailing inline comment** (`ADMIN_SSH_CIDR=1.2.3.4/32  # never 0.0.0.0/0`), so the whole string went to `ufw` | Strip `#…` from values (`4be3cdc`); also tolerate quoted values (`975ad3f`) |
| Config typos hard to catch without a 30-min compile | — | Added `--check-env` flag to print resolved config and exit (`110085b`) |
| Script silently exits right after "Building Asterisk…" with zero output | `contrib/scripts/install_prereq install` exits **non-zero even when prerequisites are already satisfied**; `set -euo pipefail` aborted the whole script with no message | Made that command non-fatal; also skip re-download on rerun; added `get_mp3_source.sh` (`716c90d`) |
| Header said "Debian 13 (bookworm+)" | bookworm is Debian **12**, trixie is 13 — and the verified package set was from a Debian 12 base | Corrected; parameterised `PHP_VERSION` (default 8.3, since Ubuntu 24.04 ships PHP 8.3 not the 8.2 `local-dev/` uses) (`92bf474` area) |
| `asterisk -cvvv` → `No such group '"asterisk"'!` | Script wrote `rungroup = "asterisk"` **with quotes** into `asterisk.conf`; Asterisk takes the value verbatim and looked up a group literally named `"asterisk"` | Removed the quotes (`92bf474`) |
| FreePBX admin UI unreachable even from the admin IP | Firewall rules never opened **80/443 to anyone** — no rule existed at all | Added 80/443 rules scoped to `ADMIN_SSH_CIDR` (`c566df1`) |

### 3. Asterisk build + service

- **1 vCPU** confirmed via `nproc`. Cloudlet scaling on this platform bumps RAM/GHz, not core count — so `make -j$(nproc)` = `-j1`. Budgeted 45–90 min; in practice it was fast because earlier interrupted attempts had already compiled most objects (`make` is incremental).
- `format_mp3` was skipped (MP3 decoder source not pre-fetched) — harmless, not needed by FreePBX. Script now runs `get_mp3_source.sh` for future rebuilds.
- After fixing the `rungroup` quotes, `asterisk -cvvv` reached **"Asterisk Ready."** The wall of ALSA/JACK errors and "declined to load" CDR/CEL modules are all normal noise on a headless VM.
- The service registered as a **legacy SysV init script** (`/etc/init.d/asterisk`), not a native systemd unit — `systemctl enable --now asterisk` had silently done nothing (zero journal entries) because the underlying start was failing on the `rungroup` bug. After the fix, `systemctl restart asterisk` + `asterisk -rx "core show version"` confirmed it running.

### 4. The database connectivity saga

The longest detour. FreePBX's installer kept failing at "Database installation checking credentials and permissions":

```
Access denied for user 'freepbxuser'@'10.121.1.16' (using password: YES)
```

What was tried, in order:

1. **Scoped the grant to the exact source IP** (`10.121.1.17`) — next attempt came from `10.121.1.16`. The source IP **rotates** across a small pool.
2. **Widened to `10.121.1.%`** — still `Access denied`. phpMyAdmin's user overview showed `USAGE` only for these host entries (its "Global privileges" column doesn't show per-DB grants, a red herring).
3. **Widened to `%`** (any host) — *still* `Access denied`. At this point host-matching was ruled out.
4. **Tested `root`** from the Asterisk node → also `Access denied`, this time reporting `root@10.121.1.17` (different IP again). `root@%` exists with `mysql_native_password`, so this shouldn't fail.
5. **Connected locally on the DB node** (`mysql -u root -p`, Unix socket, no `-h`) → **worked instantly.** Credentials and grants were fine all along.
6. **Checked mysqld's error log** (`/var/log/mysql/mysqld.log`, not `error.log`) → **not one** of the failed external attempts appeared in it. Only a local `root@localhost` test. The connections were **never reaching MariaDB.**
7. **Got the DB node's internal IP** (`hostname -i` → `10.121.5.221`) and connected to *that* directly from the Asterisk node → **worked** (as root).

**Root cause:** the public hostname `node26242-env-7970601.ktm.yetiappcloud.com` routes through a **shared Jelastic proxy/gateway** that was rejecting the connections before they reached mysqld — returning a well-formed MySQL "Access denied" without ever forwarding the connection or logging it. Nothing in MySQL grants, `my.cnf`, `iptables`, or the account could fix that.

**Fix:** point `DB_HOST` at the **internal IP** `10.121.5.221`, not the public hostname.

Two more issues surfaced immediately after switching to the internal IP:

- `Access denied for 'freepbxuser'@'103.90.84.156'` — connecting to the internal IP, mysqld saw the source as the Asterisk node's **public egress IP**, not a `10.121.x.x` address, so even `10.121.%.%` didn't match. Resolved by using `freepbxuser@'%'` (acceptable: the DB has no public IP and is only reachable over the internal network now).
- `Unknown database 'asterisk'` — the `asterisk` database had been **renamed to `asteriskcdrdb`** during initial setup. FreePBX needs **both** `asterisk` (config) and `asteriskcdrdb` (call records). Created both explicitly.

After that, `./install -n` completed: **"You have successfully installed FreePBX"**.

### 5. Finishing the install by hand

- `./install -n` **exits non-zero despite printing success** — a known FreePBX quirk — so `set -e` stopped the bootstrap script before its last steps (`fwconsole` reload/restart, AMI/ARI provisioning, fail2ban).
- Ran the rest manually: `fwconsole reload` + `fwconsole restart` → clean, Asterisk restarted under FreePBX management. (`fwconsole status` isn't a command in this version — ignore.)
- `curl -sI http://localhost/admin/` → `HTTP/1.1 302 Found` (FreePBX serving).

### 6. Admin UI not reachable from outside (current blocker)

- `http://103.90.84.156/admin` from a browser → `ERR_CONNECTION_TIMED_OUT`, even with `ufw allow 80/tcp` / `443/tcp` wide open.
- `ss -tlnp` → Apache is listening on `0.0.0.0:80`. ARI is listening on `*:8089`. AMI (5038) not yet listening (not provisioned).
- `curl -sI http://103.90.84.156/admin/` **from the node itself** → `302 Found`. Service and local routing are fine.
- Conclusion: inbound 80/443 is being dropped at **Jelastic's network layer** — same class of problem as the database. `ufw` is not the constraint.
- The shared-load-balancer path (`env-7970601.ktm.yetiappcloud.com`) turned out **not to apply** — that URL returns "non-existing environment" because a bare "Elastic VPS" node type doesn't create a web entry point (no LB node, no "Open in Browser" button). The Custom Domains form is only for the shared-LB case.
- **Root cause:** the "Elastic VPS" node's Jelastic firewall (dashboard → Firewall → Inbound Rules) shipped with only FTP(21)/SSH(22)/SMTP(25) allowed, then Deny-All at priority 65535 — **no rule for 80/443**. (The managed "SQL Databases" node came pre-loaded with HTTP/HTTPS rules; the VPS node didn't.)
- **Fix:** added inbound rules on the VPS node — `Allow HTTP` (TCP 80, `0.0.0.0/0`, priority 1030) and `Allow HTTPS` (TCP 443, `0.0.0.0/0`, priority 1040). `http://103.90.84.156/admin/` then loaded immediately.
- `sainowine.com.np` over `https` fails with connection-refused (no 443 listener / no cert yet — TLS still to do). `http://sainowine.com.np` gets auto-upgraded to `https` by the browser (Chrome HTTPS-upgrade) — not a server-side redirect (confirmed: `curl -H "Host: sainowine.com.np" http://localhost/.well-known/...` → 404, plain HTTP). Use the IP for the first-run wizard, then issue the cert.

---

## Gotchas specific to YetiApp Cloud / Jelastic

Reusable lessons, independent of this project:

1. **Connect to the managed DB via its internal IP, not the public `*.ktm.yetiappcloud.com` hostname.** The public hostname routes through a shared proxy that silently rejects connections it can't attribute — you get a MySQL "Access denied" that never appears in the DB's own logs. Use `hostname -i` on the DB node to get the internal IP.
2. **Cloudlets scale RAM and CPU clock speed, not core count.** Nodes here are single-core regardless of how many cloudlets you assign. Plan compile times accordingly (`make -j1`).
3. **Jelastic has its own network/firewall layer above the OS.** Both the DB block and the web-UI block were at this layer — opening `ufw`/`iptables` on the node does nothing for it. Inbound rules live in the Jelastic dashboard (node → Firewall → Inbound Rules).
4. **A bare "Elastic VPS" node ships with a minimal inbound ruleset** — FTP/SSH/SMTP only, then deny-all. Any other port you want reachable (80, 443, 5060, 5038, 8089…) needs an explicit inbound rule added. Managed stack nodes (like "SQL Databases") come with more open by default.
5. **A raw VPS node has no shared load balancer / no `env-*.ktm.yetiappcloud.com` web entry point.** The Custom Domains form and "Open in Browser" don't apply. Expose web services via the node's public IP + inbound firewall rules, and point DNS straight at the IP with an A record.
6. **A node's public egress IP (`curl ifconfig.me`) is not proof of dedicated inbound routing** on its own — but here it was fine; the block was purely the missing firewall rule.
5. **The source IP of outbound connections from a node rotates** across a small internal pool (`10.121.1.16`/`.17` seen interchangeably). Don't scope DB grants to a single IP.
6. **FreePBX's `./install -n` exits non-zero even on success.** Don't let `set -e` treat that as fatal.

---

## Current state

**Done:**
- Asterisk 22.11.0 built + running as a service on `node26243`
- FreePBX 17 installed against the external MariaDB (`DB_HOST=10.121.5.221`, `freepbxuser@'%'`)
- Databases `asterisk` + `asteriskcdrdb` created
- `fwconsole reload` / `restart` clean
- Jelastic firewall inbound rules added on the VPS node: HTTP 80, HTTPS 443 (`0.0.0.0/0`)
- **Admin UI reachable: `http://103.90.84.156/admin/`**
- `sainowine.com.np` A record → `103.90.84.156` (Cloudflare, DNS-only)
- `ufw` on the node: 22 (admin IP), 5060/udp, 10000-20000/udp, 5038 + 8089 (ERP backend IP), plus blanket 80/443 (loosened during debugging — see [11-deferred-steps.md](11-deferred-steps.md) §C)

**Immediate next:**
- [ ] FreePBX first-run wizard (create admin account) — via `http://103.90.84.156/admin/`
- [ ] Let's Encrypt cert for `sainowine.com.np` (FreePBX Certificate Manager; port 80 open + serving plain HTTP, so HTTP-01 will validate)
- [ ] Force HTTPS in FreePBX once the cert is set; then `https://sainowine.com.np/admin` works

**Everything else deferred:** see [11-deferred-steps.md](11-deferred-steps.md) — AMI/ARI provisioning, fail2ban, `DB_PASS` rotation, grant tightening, `ufw` cleanup, SIP trunk, FreePBX config, doc/script updates, CI/CD secrets.
