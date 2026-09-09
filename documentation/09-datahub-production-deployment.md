# DataHub Production Deployment & CI/CD

How this project actually ships to the DataHub server, with a separate database service (not a container next to Asterisk), and a GitHub Actions pipeline — modeled on how [FinalLamaErp](../../FinalLamaErp) already deploys, adapted for what's actually different about a PBX.

## Read this first: why this isn't a copy-paste of FinalLamaErp's pipeline

FinalLamaErp's `deploy.yml` builds Docker images, pushes them to GHCR, and SSHes into the server to `docker compose pull && up -d`. That works because the app is stateless HTTP services behind Traefik. Asterisk isn't that shape, for two reasons this project already reasoned through:

1. **[02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md) already chose a native FreePBX install over Docker for production** — RTP media needs host networking, and containerizing it adds a NAT layer on top of the NAT layer SIP already fights with. `local-dev/` proves the point: it's real and browsable, but its own README admits it can't complete a live call locally because Docker Desktop can't do the RTP port trick the container image needs. That's a local-exploration tool, not a production shape.
2. **Most of FreePBX's own configuration lives in its MariaDB database, not in files** — extensions, trunks, routes, IVR menus are rows in tables, edited through the GUI. There's no `git reset --hard` equivalent for that; you can't treat FreePBX config as a stateless artifact the way a Docker image is.

So the CI/CD here has a narrower, honest scope: automate what's actually file-based and stateless (server bootstrap, custom dialplan overlays, DB backups), and leave GUI-managed PBX configuration to FreePBX's own admin UI, the way it's designed to be managed. What *does* transfer directly from FinalLamaErp's pattern: **the externalized database**, **SSH-based deploy**, **secrets in GitHub, not in the repo**, and **a server-side `.env` that deploys never touch**.

## What's git-managed vs GUI/DB-managed

| Lives in this repo, deployed by CI | Lives in FreePBX's own DB, managed via the GUI |
|---|---|
| OS/Asterisk bootstrap (`scripts/bootstrap-datahub-server.sh`) | Extensions |
| Custom dialplan overlays (`asterisk-config/dialplan-custom/*_custom.conf`) | Trunks |
| AMI/ARI user provisioning (scripted, see below) | Inbound/outbound routes |
| Firewall rules | IVR menus, ring groups, queues |
| DB backup/restore jobs | Recordings, CDR data |

FreePBX's `*_custom.conf` convention (`extensions_custom.conf` etc.) is the intentional escape hatch here: files with that exact name are `#include`d by FreePBX's generated config and are **never overwritten** when the GUI regenerates its own files. That's the one place hand-maintained, git-versioned dialplan is safe to deploy over SSH without fighting FreePBX for ownership of the file. See [asterisk-config/README.md](../../asterisk-config/README.md).

## Architecture

```
GitHub repo (this project)
        │
        │  push to main
        ▼
GitHub Actions ── SSH ──► DataHub: Asterisk + FreePBX server (native install, not Docker)
                                │
                                │  private network only (see 01-server-provisioning.md)
                                ▼
                          DataHub: MariaDB — separate service, own VM/managed instance
                          (asterisk, asteriskcdrdb databases)
```

Same shape as FinalLamaErp's `POSTGRES_HOST=10.121.6.217` externalized Postgres — the database is a peer service the app server talks to over the private network, not something bundled alongside it.

## Step 1 — Provision the separate MariaDB service

DataHub has a managed MySQL/MariaDB DBaaS — use it. Mirrors exactly how FinalLamaErp's Postgres runs as a managed Azure Container App (`infra/postgres.yaml`) rather than a container in `docker-compose.prod.yml`; DataHub handles patching/backups of the DB engine itself, same division of responsibility.

**"DataHub" turns out to be a Jelastic-based panel on YetiApp Cloud** — the same host `FinalLamaErp`'s `deploy.yml` already targets (`*.ktm.yetiappcloud.com` matches). That means DB↔app private networking here works exactly the way it already does for LamaERP's Postgres, and the "SQL Databases" node type in the topology editor is the thing to add.

Concrete picks:

- **Engine: MariaDB**, not MySQL, if the console offers a choice — FreePBX/Asterisk are developed and tested primarily against MariaDB, and it's what `local-dev/` already runs.
- **Version: MariaDB `10.xx` → 10.11**, not the panel's `12.3.3` default. Jelastic's version picker offers 12.xx/11.xx/10.xx — 12.x is very new (MariaDB's newest line) and FreePBX has a track record of subtle breakage on newer MariaDB releases (stricter SQL modes, changed defaults) that take time to shake out. 10.11 matches `local-dev/docker-compose.yml` exactly, so nothing behaves differently between what's already been clicked through locally and production. If something more current than 10.11 is wanted, `11.xx` → 11.4 LTS is the next-safest step; skip 12.x until FreePBX compatibility on it is better established.
- **Sizing: start small.** FreePBX's own DB load is config/CDR rows, not big data — Jelastic's default reserved tier (around 4 cloudlets, ~512MiB/1.6GHz) is already in the right range, the same ballpark as FinalLamaErp's Postgres container app (0.5 vCPU/1GB). Scale up only if CDR volume from voice campaigns actually grows into it.
- **Horizontal scaling: leave it at 1 node.** No Galera clustering needed for this workload — it's pure added cost/complexity.
- **Public IPv4: 0.** Keep it at zero — this is the private-networking requirement that actually matters. Apply the same firewall discipline as [01-server-provisioning.md](01-server-provisioning.md): **the DB's port 3306 is reachable only from the Asterisk app server's private IP**, never public, never a wildcard.

(If DataHub's DBaaS ever turns out to be Postgres-only, or there's no managed DB product at all, the fallback is a small dedicated VM running MariaDB natively — `apt install mariadb-server`, not Docker, consistent with the same host-networking-avoidance reasoning as Asterisk itself. Not needed here since the managed option exists.)

Once it exists, run [scripts/configure-external-db.sql](../../scripts/configure-external-db.sql) against it once (`mysql -h <db-host> -u root -p < configure-external-db.sql`) to create the `asterisk` and `asteriskcdrdb` databases and a `freepbxuser` scoped to only the Asterisk server's IP — tighter than `local-dev/init.sql`'s wildcard grant, which is fine for a localhost-only dev container but wrong for production.

## Step 2 — Bootstrap the Asterisk server

[scripts/bootstrap-datahub-server.sh](../../scripts/bootstrap-datahub-server.sh) consolidates [01](01-server-provisioning.md), [02](02-asterisk-freepbx-installation.md), and [06](06-security-hardening.md) into one script instead of a manual walkthrough: base packages, NTP, UFW firewall rules scoped to the ERP backend's IP, the FreePBX 17 installer, and AMI/ARI user provisioning with generated secrets.

**Node OS: Ubuntu 24.04 LTS.** Jelastic's compute-node picker offers Debian only as an unexpanded submenu, but lists Ubuntu 24.04/22.04/20.04/18.04 directly — 24.04 is exactly the pairing [01-server-provisioning.md](01-server-provisioning.md) already recommends (LTS through 2029, officially supported by FreePBX 17/Asterisk 22), so there's no reason to dig for a Debian option. One consequence: Ubuntu 24.04's default archive ships **PHP 8.3**, not the PHP 8.2 that `local-dev/`'s Docker image (based on Debian 12) is validated against. The bootstrap script installs whichever `PHP_VERSION` says (default 8.3) rather than hardcoding 8.2 — expected to work, since FreePBX 17's own officially-supported Ubuntu 24.04 installer path relies on PHP 8.3 too, but it's a small delta from what's actually been clicked through locally. Worth a smoke test of the FreePBX install specifically after first bootstrap.

Run it once, by hand, over SSH on the freshly provisioned box. Cloning the repo there first (rather than just `scp`-ing the one script) also satisfies Step 3's prerequisite for `deploy-asterisk-config.yml`, so it's worth doing even though the script alone doesn't strictly need it:

```bash
ssh you@datahub-asterisk-server
apt update && apt install -y git
git clone https://github.com/<owner>/<repo>.git /opt/lamaerp/asterisk
cd /opt/lamaerp/asterisk

cp .env.production.example .env.production
nano .env.production   # fill in ERP_BACKEND_IP, ADMIN_SSH_CIDR, DB_HOST, DB_USER, DB_PASS

bash scripts/bootstrap-datahub-server.sh
```

The script reads `.env.production` automatically (no flag needed) — see the note at the top of [scripts/bootstrap-datahub-server.sh](../../scripts/bootstrap-datahub-server.sh). Anything also passed inline (`DB_PASS=... bash scripts/bootstrap-datahub-server.sh`) overrides the file, so it's fine to keep most values in `.env.production` and override one-off on the command line when needed.

It prints the generated AMI/ARI secrets at the end — put those straight into `.env.production` and the ERP's own secrets store; they're shown once and not logged to a file.

This step is **not** what CI/CD automates — it's a one-time (or rare, deliberate re-run) provisioning action against a specific box, the same way nobody has FinalLamaErp's CI re-provision the DataHub VM on every push. CI/CD picks up after this.

## Step 3 — What CI/CD actually deploys

Three workflows, all under `.github/workflows/`:

### `deploy-asterisk-config.yml` — on push to `main`

Mirrors FinalLamaErp's `deploy.yml` even more directly than it might look: same `git fetch origin main && git reset --hard origin/main` idempotent-sync idiom over SSH, just against a plain git checkout on the Asterisk server instead of a Docker Compose project directory — no image to build, so it goes straight to sync + reload.

```
SSH in → cd /opt/lamaerp/asterisk && git fetch && git reset --hard origin/main →
copy asterisk-config/dialplan-custom/*.conf into /etc/asterisk/ →
asterisk -rx "dialplan reload" → smoke-test (dialplan show lamaerp-custom) →
roll back the previous file on failure
```

One-time prerequisite this workflow assumes and does not do for you: the repo needs to already be `git clone`d on the server at `/opt/lamaerp/asterisk`, using a deploy key with read access. Set that up once during — or right after — Step 2's bootstrap.

Only touches the `*_custom.conf` files described above — never anything FreePBX's GUI owns, so this workflow can't clobber a trunk or extension someone configured through the admin UI.

### `backup-freepbx-db.yml` — nightly, scheduled

Runs `mysqldump` **from the Asterisk server**, not from the GitHub runner — the DB firewall in step 1 only allows connections from that server's private IP, and GitHub-hosted runners have public, unpredictable IPs. SSH in, dump both `asterisk` and `asteriskcdrdb`, gzip, keep the last 14 days locally with a `find -mtime +14 -delete` cleanup. (Pushing dumps to the MinIO instance FinalLamaErp already runs is a reasonable next step once this is proven out — not wired up here to avoid inventing a dependency this project doesn't need yet.)

### `validate-local-dev.yml` — on pull request

Lightweight sanity check, unrelated to production: runs `docker compose -f local-dev/docker-compose.yml config` to catch YAML/compose errors in the local exploration environment before they land on `main`. Cheap insurance for a file real people will `docker compose up` on their own machines.

## Step 4 — Secrets

GitHub repo → Settings → Secrets and variables → Actions:

| Secret | Used by |
|---|---|
| `DEPLOY_HOST` | Both SSH workflows — the Asterisk server's address |
| `DEPLOY_USER` | Both SSH workflows |
| `DEPLOY_SSH_KEY` | Both SSH workflows |
| `DB_HOST` | `backup-freepbx-db.yml` — the separate MariaDB service's address |
| `DB_BACKUP_USER` | `backup-freepbx-db.yml` — reuse `freepbxuser` or create a dedicated backup account |
| `DB_BACKUP_PASS` | `backup-freepbx-db.yml` |

Everything else (DB password, AMI/ARI secrets, trunk credentials) lives in a **server-side `.env`-equivalent** the deploy workflow never writes to — same discipline as FinalLamaErp's `/opt/lamaerp/.env`, which `git reset --hard` on deploy deliberately leaves untouched because it's gitignored/untracked on the server. See the reference values laid out in [.env.production.example](../../.env.production.example) at the repo root — note its header: FreePBX doesn't read a dotenv file the way the .NET app does, so this is the canonical list of values to have on hand (for the bootstrap script's arguments, the GUI's AMI/ARI/trunk forms, and the GitHub secrets above), not a file FreePBX consumes automatically.

## Rollback

- **Custom dialplan**: the deploy workflow keeps the previous `*_custom.conf` alongside the new one (`.bak` suffix) and restores it automatically if the post-deploy `dialplan show` smoke test fails.
- **Database**: restore the most recent nightly dump (`backup-freepbx-db.yml`'s output) with `mysql -h <db-host> -u root -p asterisk < dump.sql`.
- **GUI-managed config** (extensions/trunks/routes): FreePBX has no git history for this by design — rely on the DB backups above, or FreePBX's own **Backup & Restore** module (Admin → Backup & Restore) for a full point-in-time restore of GUI state.

## Where this leaves the LamaERP side

The `LamaERP.Platform.Telephony` module proposed in [05-erp-integration.md](05-erp-integration.md) is regular application code that lives in **FinalLamaErp's own repo**, not this one — it ships through FinalLamaErp's existing `deploy.yml` (build → GHCR → SSH → `docker compose up -d`) exactly as every other Platform module does today. This project's CI/CD only covers the Asterisk/FreePBX server itself and its database.
