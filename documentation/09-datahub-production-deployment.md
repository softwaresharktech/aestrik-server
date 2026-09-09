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

Two ways to do this in DataHub, in order of preference:

1. **DataHub's managed MySQL/MariaDB offering**, if it has one — mirrors exactly how FinalLamaErp's Postgres runs as a managed Azure Container App (`infra/postgres.yaml`) rather than a container in `docker-compose.prod.yml`. Least operational burden — DataHub handles patching/backups of the DB engine itself.
2. **A small, dedicated VM running MariaDB natively** (`apt install mariadb-server`, not Docker — consistent with the same host-networking-avoidance reasoning as Asterisk itself, and it keeps the DB off the Asterisk box so a PBX issue can't take the database down with it). 1 vCPU / 1–2GB RAM is plenty for FreePBX's own DB load.

Either way, apply the same firewall discipline as [01-server-provisioning.md](01-server-provisioning.md): **the DB's port 3306 is reachable only from the Asterisk app server's private IP**, never public, never a wildcard.

Once it exists, run [scripts/configure-external-db.sql](../../scripts/configure-external-db.sql) against it once (`mysql -h <db-host> -u root -p < configure-external-db.sql`) to create the `asterisk` and `asteriskcdrdb` databases and a `freepbxuser` scoped to only the Asterisk server's IP — tighter than `local-dev/init.sql`'s wildcard grant, which is fine for a localhost-only dev container but wrong for production.

## Step 2 — Bootstrap the Asterisk server

[scripts/bootstrap-datahub-server.sh](../../scripts/bootstrap-datahub-server.sh) consolidates [01](01-server-provisioning.md), [02](02-asterisk-freepbx-installation.md), and [06](06-security-hardening.md) into one script instead of a manual walkthrough: base packages, NTP, UFW firewall rules scoped to the ERP backend's IP, the FreePBX 17 installer, and AMI/ARI user provisioning with generated secrets. Run it once, by hand, over SSH on the freshly provisioned box:

```bash
scp scripts/bootstrap-datahub-server.sh you@datahub-asterisk-server:/tmp/
ssh you@datahub-asterisk-server
sudo ERP_BACKEND_IP=10.x.x.x ADMIN_SSH_CIDR=10.x.x.x/32 DB_HOST=<mariadb-private-ip> DB_PASS='<freepbxuser password from step 1>' \
  bash /tmp/bootstrap-datahub-server.sh
```

It prints the generated AMI/ARI secrets at the end — put those straight into the server's `.env` (step 4) and the ERP's own secrets store; they're shown once and not logged to a file.

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
