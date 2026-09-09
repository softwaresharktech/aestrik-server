# Asterisk × LamaERP

Standing up [Asterisk](https://www.asterisk.org/)/FreePBX on a DataHub server and connecting it to [FinalLamaErp](../FinalLamaErp)'s telephony needs — fee-reminder/attendance-alert voice campaigns, click-to-call, screen pop. This repo holds the plan, a working local FreePBX to click through, and what actually deploys the real thing.

## Layout

| Path | What it is |
|---|---|
| [documentation/](documentation/) | The full write-up, in order — start at [documentation/README.md](documentation/README.md) |
| [local-dev/](local-dev/) | A real FreePBX 17 + Asterisk 21 running locally in Docker — genuine admin GUI at `http://localhost/admin`, for exploring the UI (no live call audio; see its own README) |
| [asterisk-config/](asterisk-config/) | The one slice of production Asterisk config this repo deploys directly (`*_custom.conf` dialplan overlays) |
| [scripts/](scripts/) | `bootstrap-datahub-server.sh` (one-time server setup) and `configure-external-db.sql` (one-time DB setup) |
| [.github/workflows/](.github/workflows/) | CI/CD — deploys `asterisk-config/`, nightly DB backups, PR validation for `local-dev/` |
| [.env.production.example](.env.production.example) | Canonical list of production values (not a file Asterisk reads — see its header) |

## Run it locally

```bash
cd local-dev
docker compose up -d
```

Wait ~30–60s for MariaDB and Asterisk to boot, then open **http://localhost/admin**. First visit shows FreePBX's real setup wizard — pick your own admin username/password there (no default login).

If it's a brand-new start (empty database, never installed before), run the installer once after the containers are up:

```bash
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker compose exec -w /usr/local/src/freepbx freepbx \
  php install -n --dbuser=freepbxuser --dbpass="$(cat freepbxuser_password.txt)" --dbhost=db
```

Day to day:

```bash
docker compose ps                # check it's running
docker compose logs -f freepbx   # watch logs
docker compose down              # stop, keep all data
docker compose down -v           # stop and wipe everything (start over)
```

No live call audio locally (Docker Desktop on Windows can't do the RTP port trick the image needs) — this is for clicking through the real GUI, not placing calls. Full details in [local-dev/README.md](local-dev/README.md).

## Where to start

- **Just want to see what FreePBX actually looks like?** → [local-dev/README.md](local-dev/README.md), then open `http://localhost/admin`.
- **Planning the real DataHub deployment?** → [documentation/00-overview.md](documentation/00-overview.md) through [09](documentation/09-datahub-production-deployment.md), in order.
- **Ready to provision the real server?** → [documentation/09-datahub-production-deployment.md](documentation/09-datahub-production-deployment.md) is the operational entry point: separate MariaDB service, `scripts/bootstrap-datahub-server.sh`, then the GitHub Actions workflows take over.

## Status

Planning + a working local exploration environment. Nothing has been deployed to DataHub yet — the SIP trunk provider, exact server specs/IPs, and final `LamaERP.Platform.Telephony` module code (which lives in [FinalLamaErp](../FinalLamaErp), not here) are all still open. Flagged inline wherever they come up in the docs.
