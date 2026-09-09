# asterisk-config

The **only** part of the DataHub Asterisk server's configuration that this repo deploys directly, on every push to `main`, via [.github/workflows/deploy-asterisk-config.yml](../.github/workflows/deploy-asterisk-config.yml). See [documentation/09-datahub-production-deployment.md](../documentation/09-datahub-production-deployment.md) for why everything else (extensions, trunks, routes, IVR menus) stays GUI-managed instead.

## Why `*_custom.conf`

FreePBX generates most of Asterisk's dialplan itself from what's in its database, and rewrites those generated files whenever the GUI changes something or `fwconsole reload` runs. Hand-edited dialplan in those generated files gets silently clobbered on the next regeneration.

FreePBX's own generated `extensions.conf` includes one specific escape hatch: `#include extensions_custom.conf`. Anything in that file (and its equivalents — `*_custom.conf` is a general FreePBX convention, not unique to extensions) is preserved verbatim across every GUI change and every `fwconsole reload`. That's the one place hand-maintained, git-versioned dialplan can safely live.

## Layout

```
asterisk-config/
└── dialplan-custom/
    └── extensions_custom.conf   -> deployed to /etc/asterisk/extensions_custom.conf
```

Add more `*_custom.conf` files here as needed (e.g. `queues_custom.conf`) — the deploy workflow syncs everything in `dialplan-custom/` by filename, so a new file just needs adding to this directory and the workflow.

## Deploying a change

1. Edit the relevant `*_custom.conf` file, commit, push to `main`.
2. The deploy workflow rsyncs it to `/etc/asterisk/` on the DataHub server and runs `asterisk -rx "dialplan reload"` (not a full `fwconsole reload` — this only reparses dialplan, which is all a custom-context change needs, and is far faster).
3. It then runs `asterisk -rx "dialplan show lamaerp-custom"` as a smoke test. If that fails (syntax error, missing context), the workflow restores the previous file automatically.

## Testing locally first

Point `local-dev/`'s FreePBX at a copy of these files before pushing — copy `dialplan-custom/extensions_custom.conf` into the running container (`docker cp asterisk-config/dialplan-custom/extensions_custom.conf freepbx-app:/etc/asterisk/extensions_custom.conf` then `docker exec freepbx-app asterisk -rx "dialplan reload"`) and confirm the context parses before pushing to `main`.
