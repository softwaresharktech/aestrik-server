# Deferred Steps / TODO

Everything skipped, stubbed, or temporarily loosened during the YetiApp Cloud install ([10-yetiappcloud-install-log.md](10-yetiappcloud-install-log.md)), so nothing gets forgotten. Grouped by area, roughly in priority order. Check items off here as they're done.

---

## A. Finish the bootstrap script's remaining sections (by hand)

The script stopped after `./install -n` (FreePBX's installer exits non-zero despite success; `set -e` killed the rest). `fwconsole reload`/`restart` were run manually. Still not done:

- [ ] **`fwconsole ma updateall`** — pull latest FreePBX module versions. Skipped to get the UI up faster; run once things are stable.
- [ ] **AMI user provisioning** (script section 7). Appends a `[lamaerp]` block to `/etc/asterisk/manager_additional.conf` with a generated secret, `permit` scoped to the ERP backend IP. AMI (5038) is **not currently listening**. Do this via the FreePBX GUI (Settings → Asterisk Manager Users) or the file, but only add **one** `[lamaerp]` block.
- [ ] **ARI user provisioning** (script section 8). `http.conf` is already `enabled` and ARI **is listening on 8089**, but the `[lamaerp]` user block in `/etc/asterisk/ari_additional.conf` was **not added**. Add it (GUI: Settings → Asterisk REST Interface Users, or the file).
- [ ] **Record the AMI + ARI secrets** into `.env.production` (`AMI_SECRET=`, `ARI_SECRET=`) when you provision them — the script would have printed them; done by hand, you generate them.
- [ ] **`systemctl enable --now fail2ban`** (script section 9). fail2ban is installed but **not enabled/running**. No brute-force protection on SIP/SSH/admin until this is done — see [06-security-hardening.md](06-security-hardening.md).

## B. Jelastic firewall — inbound rules still missing on the Elastic VPS node

The bare "Elastic VPS" node type ships with only FTP/SSH/SMTP inbound rules + deny-all. Added during install: **HTTP 80, HTTPS 443** (source `All`). Still missing:

- [ ] **TCP 5038 (AMI)** — inbound rule, source = **ERP backend IP only**, not `All`.
- [ ] **TCP 8089 (ARI)** — inbound rule, source = **ERP backend IP only**. (ARI is listening but unreachable externally until this is added — and it should only ever be reached over the internal network anyway; see item F.)
- [ ] **UDP 5060 (SIP)** — inbound rule, source = **SIP trunk provider's signaling range only** (once a provider is chosen). Currently no rule → denied.
- [ ] **UDP 10000–20000 (RTP)** — inbound rule, source = SIP trunk provider's range. No real calls until this + 5060 are open.
- [ ] **Re-scope HTTP/HTTPS** — 80/443 are currently open to `All`. 80 needs to stay open for Let's Encrypt HTTP-01 renewal, but consider scoping **443** to admin IPs + relying on fail2ban + FreePBX's own login. Decision, not urgent.

## C. Node `ufw` — loosened during debugging, needs tidying

`ufw` on `node26243` was opened up while chasing the web-UI block (before we found it was the Jelastic firewall). Now that Jelastic's firewall is the real gate:

- [ ] Remove the blanket `ufw allow 80/tcp` / `ufw allow 443/tcp` rules (added for testing).
- [ ] Remove the now-redundant `ufw allow from 45.115.217.10 to any port 80/443` rules.
- [ ] Decide whether to keep `ufw` at all as defense-in-depth, or let Jelastic's firewall be the single source of truth. If keeping it, make sure its rules don't contradict Jelastic's.

## D. Database — temporary values to rotate/tighten

- [ ] **Rotate `DB_PASS`.** It's currently the throwaway `FreePbxTemp2026` set during troubleshooting. Change the MariaDB `freepbxuser` password **and** `.env.production`'s `DB_PASS` together, then `fwconsole reload`.
- [ ] **Tighten the `freepbxuser` grant.** It's currently `freepbxuser@'%'` (any host) — opened wide because the source IP kept changing (`10.121.1.16`/`.17` internal, `103.90.84.156` public egress). Once the source-IP behaviour is pinned down, scope it (e.g. `10.121.%.%` plus whatever the egress path actually presents). Acceptable as-is for now only because the DB has no public IP.
- [ ] **Clean up leftover DB objects.** `asterisk` was originally created, renamed to `asteriskcdrdb`, then a fresh `asterisk` was made — there may be a stray renamed/empty database. Also verify no leftover `freepbxuser@10.121.1.17` / `@10.121.1.%` / `@10.121.%.%` grants remain from the failed attempts (`SELECT User, Host FROM mysql.user;`).
- [ ] Confirm `.env.production` on the server has `DB_HOST=10.121.5.221` (the internal IP), not the public hostname.

## E. FreePBX post-install configuration (via the GUI)

- [x] **First-run wizard** — admin account created.
- [x] **TLS cert for `sainowine.com.np`** — Let's Encrypt via Certificate Manager, HTTP-01, set as Default Certificate. `https://sainowine.com.np/admin` live. (Auto-renews ~every 2 months per FreePBX — don't add a separate renewer.)
- [ ] **SIP trunk** — provider not chosen (business decision, open since [09](09-datahub-production-deployment.md) Phase 0). Blocks all real inbound/outbound calling.
- [ ] **Extensions / inbound + outbound routes / IVR** — per [03-freepbx-configuration.md](03-freepbx-configuration.md). Not started.
- [ ] **`TRUNK_PROVIDER_CIDR`** in `.env.production` is commented out — SIP left unscoped by default. Set it to the provider's real range once known.
- [ ] **Call recording** — decide scope + confirm the compliance/consent position in [06-security-hardening.md](06-security-hardening.md) before enabling.

## F. ERP integration (future — lives in FinalLamaErp, not this repo)

- [ ] **`LamaERP.Platform.Telephony` module** — not started. See [05-erp-integration.md](05-erp-integration.md).
- [ ] Point the ERP backend at AMI/ARI over the **internal** Jelastic network (node-to-node), never the public IP — same lesson as the database. The public-hostname path goes through a shared proxy that mangles connections.

## G. Docs & scripts to update with lessons learned

- [ ] **`scripts/configure-external-db.sql`** — currently scopes the grant to a single `<asterisk-node-internal-ip>`. Rework for YetiApp: connect via the DB node's internal IP, and grant on a network range (source IP isn't stable). Add the `asteriskcdrdb` create explicitly.
- [ ] **`scripts/bootstrap-datahub-server.sh`** — make the AMI/ARI sections idempotent (check for an existing `[lamaerp]` block before `cat >>`, so re-runs don't stack duplicates). Consider tolerating FreePBX's `./install` non-zero exit instead of letting `set -e` kill the run.
- [ ] **[09-datahub-production-deployment.md](09-datahub-production-deployment.md)** — Step 1 should say: use the DB node's **internal IP** as `DB_HOST`, never the `*.ktm.yetiappcloud.com` public hostname (shared proxy blocks it).
- [ ] **[01-server-provisioning.md](01-server-provisioning.md)** / **[06-security-hardening.md](06-security-hardening.md)** — note that on Jelastic the authoritative inbound firewall is the platform's own (dashboard → Firewall → Inbound Rules), not the node's `ufw`; a bare "Elastic VPS" node only allows FTP/SSH/SMTP by default.
- [ ] **`format_mp3`** — not built into the current Asterisk (MP3 source wasn't pre-fetched). The script now runs `get_mp3_source.sh` for future rebuilds; the running install lacks it. Not needed by FreePBX core — rebuild only if something actually requires MP3 playback.
- [ ] Asterisk runs from a **legacy SysV init script** (`/etc/init.d/asterisk`), not a native systemd unit. Works fine; installing `contrib/systemd/asterisk.service` from the source tree would be cleaner. Low priority.

## H. CI/CD (from [09](09-datahub-production-deployment.md), not yet wired)

- [ ] Add GitHub repo secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DB_HOST`, `DB_BACKUP_USER`, `DB_BACKUP_PASS`. Until then `deploy-asterisk-config.yml` and `backup-freepbx-db.yml` will fail if triggered.
- [x] Repo cloned on the server at `/opt/lamaerp/asterisk` (done — also the prerequisite for `deploy-asterisk-config.yml`).
- [ ] Note the SSH gate detail: YetiApp uses `ssh <envid>@gate.yetiapp.cloud -p 3022`, not direct `:22` to the node — the deploy workflows may need adjusting for that.
