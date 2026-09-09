# Security Hardening

Asterisk/FreePBX boxes are a well-known toll-fraud target — an unsecured system can be found and abused (expensive international calls billed to you) within hours of being exposed. This isn't optional hardening, it's baseline for going live at all.

## Toll-fraud prevention

- **No guest/anonymous calls.** Ensure `pjsip.conf` (or the FreePBX equivalent) has no context that lets an unauthenticated caller reach an outbound route. Every PJSIP endpoint must require registration/auth.
- **Strong, generated secrets** for every extension and trunk — no default/weak passwords, ever. Rotate if any device/credential is decommissioned.
- **Restrict dial patterns** on outbound routes ([03](03-freepbx-configuration.md)) to only what tenants legitimately need to call. A route that matches "anything" is a blank check to whoever gets in.
- **Cap concurrent calls per trunk** and per extension in FreePBX (Trunk → "Maximum Channels") — bounds the damage even if a credential leaks.
- **fail2ban** with the Asterisk jail enabled (bundled with the FreePBX installer, or configure manually for a from-source install) — bans IPs after repeated failed SIP registration attempts.
- **Geo/IP restriction** on SIP signaling: if remote extensions and the trunk provider are both known, fixed IP ranges, the firewall in [01-server-provisioning.md](01-server-provisioning.md) should already be the primary control — treat fail2ban as defense in depth, not the only layer.
- Enable **Asterisk's own security log** (`logger.conf` → `security` channel) and forward it to monitoring/alerting (see below).

## AMI / ARI credential hygiene

- AMI and ARI credentials ([02](02-asterisk-freepbx-installation.md)) are bound to the ERP backend's private IP only — never widen `permit`/`allowed_origins` beyond that without a reason.
- Store the credentials in the ERP's existing secrets mechanism (the repo already uses `.env.*` files per environment — follow that pattern, do not commit secrets to source control).
- **One set of credentials per environment** (dev/staging/prod) — never share a single AMI/ARI login across environments; a dev bug shouldn't be able to originate a call on the production trunk.
- ARI must run over TLS in production (`tlsenable=yes` in `http.conf`) — Basic Auth credentials in plaintext HTTP are trivially sniffable on a shared network segment.
- Rotate AMI/ARI secrets on a schedule and immediately on any suspected exposure (e.g. a secret accidentally logged).

## Network isolation

- Asterisk lives in a private subnet; only the ERP backend and the SIP trunk provider's known IP range can reach it (already specified in [01](01-server-provisioning.md) — this section is the "why").
- The FreePBX admin web UI is **not** public — VPN or IP-allowlisted reverse proxy only.
- If DataHub's network doesn't provide a private link between the ERP app tier and the Asterisk box by default, add one (WireGuard or equivalent) rather than opening AMI/ARI to a wider range "temporarily."

## Call recording — compliance, not just a toggle

Before enabling call recording anywhere ([03-freepbx-configuration.md](03-freepbx-configuration.md)):

- Confirm consent/notice requirements for the jurisdictions the tenants operate in (this varies; call/verify rather than assume — telecom and privacy regulation differs by country and can require an audible notice or opt-in).
- Recordings are personal data about parents/guardians and potentially minors (school context) — encrypt at rest, restrict access to the same role boundaries the ERP already enforces for student data, and set a retention/deletion policy rather than keeping everything indefinitely (see the storage note in [01](01-server-provisioning.md)).
- If recordings move to object storage (e.g. MinIO, per the existing ERP infra), make sure that bucket's access policy is at least as strict as the student-data buckets already in use.

## Monitoring / alerting

At minimum, alert on:
- fail2ban ban events (spike = someone's actively probing).
- Asterisk security log entries (`security` channel in `logger.conf`).
- Disk usage on the Asterisk box (a full disk drops live calls, not just recordings).
- Trunk/registration health (a trunk silently going unregistered means outbound calls — including automated fee-reminder campaigns — silently stop).
- Unusual call-volume patterns (e.g. a campaign misfire looping, or a compromised credential placing far more calls than expected) — cross-check against the `CallLog`/`CallCampaign` data the Telephony module ([05](05-erp-integration.md)) is already recording.

## Next step

[07-rollout-checklist.md](07-rollout-checklist.md) sequences all of the above into a phased go-live plan.
