# Local FreePBX — Real App, Local UI

A genuine FreePBX 17 + Asterisk 21 install, running locally in Docker, that you click through in your browser. Not a mockup — this is the same admin GUI documented in [documentation/02](../documentation/02-asterisk-freepbx-installation.md) and [documentation/03](../documentation/03-freepbx-configuration.md), just running on your machine instead of the DataHub server.

**Status: running.** Containers `freepbx-app` and `freepbx-db` are up.

## Open it

**http://localhost/admin**

First visit walks you through FreePBX's setup wizard: pick your own admin username/password (there's no default login — you set it on first load). After that you land in the real FreePBX dashboard.

## What to click through

Everything in [03-freepbx-configuration.md](../documentation/03-freepbx-configuration.md) exists here for real:

- **Connectivity → Extensions** — add a PJSIP extension, see the actual form FreePBX generates.
- **Connectivity → Trunks** — the trunk setup screen (you don't need a real SIP provider to look around).
- **Connectivity → Routes** — inbound/outbound routing.
- **Applications → IVR** — the drag-together menu builder referenced in the docs.
- **Applications → Ring Groups / Queues**.
- **Settings → Asterisk Manager Users** — this is where AMI ([documentation/04](../documentation/04-asterisk-apis-ami-ari.md)) gets its credentials; add a user here, it's reachable at `localhost:5038` from the host.
- **Settings → Asterisk REST Interface Users** — same idea for ARI, reachable at `localhost:8088`.
- **Admin → Module Admin** — this is where the paid-vs-free module split from [documentation/08](../documentation/08-open-source-vs-paid-comparison.md) is visible directly: browse the module catalog and see which ones are marked commercial.

## What this environment can't do

- **No real phone calls.** RTP media ports aren't published to the host — the upstream project ([escomputers/freepbx-docker](https://github.com/escomputers/freepbx-docker)) handles that via a Linux-only `iptables` script (`run.sh`) that doesn't apply to Docker Desktop on Windows. You can configure trunks/extensions and see every screen, but audio won't flow end-to-end. That's fine for exploring the UI and testing AMI/ARI reachability; it's not a substitute for the real DataHub build.
- **No email.** Postfix/SMTP is present in the image but not configured (`sasl_passwd.txt` here is a placeholder) — email notifications will silently fail. Irrelevant to browsing the GUI.
- **fail2ban is disabled** (`17-nofail2ban` image tag) — deliberate, so the container doesn't need `NET_ADMIN`/privileged mode on Windows. Don't carry this choice into the production DataHub build; see [documentation/06-security-hardening.md](../documentation/06-security-hardening.md).

This is a different, older stack than what's documented for production (FreePBX 17/Asterisk 21 here vs. the Asterisk 22 LTS install path in [documentation/02](../documentation/02-asterisk-freepbx-installation.md)) — good enough to be the real UI, not what should actually get deployed to DataHub.

## Commands

```bash
cd local-dev

docker compose up -d       # start (already done)
docker compose ps          # status
docker compose logs -f freepbx   # tail logs
docker compose down        # stop, keep data
docker compose down -v     # stop and wipe all data (start over from scratch)
```

If you do need to re-run the FreePBX installer (e.g. after a `down -v` reset), the DB password lives in `freepbxuser_password.txt` — on Windows, run this from Git Bash (not PowerShell) so the container path doesn't get mangled:

```bash
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" docker compose exec -w /usr/local/src/freepbx freepbx \
  php install -n --dbuser=freepbxuser --dbpass="$(cat freepbxuser_password.txt)" --dbhost=db
```

## Files here

| File | Purpose |
|---|---|
| `docker-compose.yml` | The two services — `db` (MariaDB) and `freepbx` (FreePBX+Asterisk) |
| `my.cnf`, `init.sql` | Required by the MariaDB container (SQL mode + the `asterisk`/`asteriskcdrdb` databases FreePBX expects) |
| `mysql_root_password.txt`, `freepbxuser_password.txt` | Generated local-only DB passwords — not secrets worth protecting, just dev credentials. Not committed if this ever becomes a git repo (see `.gitignore`). |
| `sasl_passwd.txt` | Placeholder — the image mounts a file here regardless of whether email is configured |

Ports are bound to `127.0.0.1` only — nothing here is reachable from your LAN, only from this machine.
