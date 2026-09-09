# Server Provisioning (DataHub)

This covers the new server to provision in DataHub before installing anything, per [00-overview.md](00-overview.md).

## Sizing

School-ERP telephony load is low-concurrency (a handful of simultaneous calls per tenant, not a call center at scale). A modest VM is enough to start, and Asterisk scales vertically well past this:

| Resource | Minimum | Recommended (headroom for growth) |
|---|---|---|
| vCPU | 2 | 4 |
| RAM | 2 GB | 4–8 GB |
| Disk | 20 GB SSD | 40–80 GB SSD (call recordings grow this fast — see retention note below) |
| Network | 10 Mbps | 100 Mbps, low jitter |

Re-evaluate once real tenant/call-volume numbers exist — this is a starting point, not a permanent ceiling.

## Operating system

Use **Debian 13 (Trixie)** or **Ubuntu 24.04 LTS** — both are the officially supported targets for the FreePBX 17 installer and Asterisk 22 LTS. ([computingforgeeks.com](https://computingforgeeks.com/install-asterisk-pbx-ubuntu-debian/), [ipcomms.net](https://www.ipcomms.net/blog/asterisk-debian-13-install/))

- Minimal server install, no desktop environment.
- A dedicated, unprivileged Linux user for day-to-day admin (sudo, not root login over SSH).
- `chrony` or `systemd-timesyncd` enabled — **Asterisk is sensitive to clock skew** (SIP registration timing, CDR timestamps, TLS cert validation), so NTP must be correct before anything else is configured.

## Networking

- **Static private IP** inside the DataHub VPC/subnet — this is what the ERP backend and internal admins will talk to.
- **Public IP / NAT**, only if the chosen SIP trunk provider requires direct public reachability (many ITSPs support IP-authenticated trunks that need this). If the trunk provider connects out to you, confirm whether their signaling originates from a small, documented IP range — firewall to that range specifically rather than opening SIP to the internet broadly.
- **DNS**: an internal-only hostname (e.g. `pbx.internal.<datahub-domain>`) for the ERP backend to resolve, plus a public hostname only if FreePBX's Certificate Manager module will issue a Let's Encrypt cert for the admin UI/ARI endpoint.

## Firewall / security-group rules

Default-deny, then allow only what's needed:

| Port | Protocol | From | Purpose |
|---|---|---|---|
| 22 | TCP | Admin IPs / VPN only | SSH |
| 5060 (or 5061 for TLS) | UDP/TCP | SIP trunk provider IP range + registered remote extensions only | SIP signaling |
| 10000–20000 | UDP | Same as above | RTP media (range is configurable in `rtp.conf`; keep it as narrow as the expected concurrent-call count allows) |
| 5038 | TCP | **ERP backend server IP only** | AMI — never expose beyond the app tier |
| 443 (or a non-standard port) | TCP | **ERP backend server IP only** for ARI; admin IPs/VPN for the FreePBX GUI | ARI + FreePBX web UI, both over HTTPS |

Do **not** put AMI, ARI, or the FreePBX admin UI directly on the public internet. If DataHub's network doesn't give you a private link between the ERP server and this box, put a VPN (WireGuard is a good fit) or an IP-allowlisted reverse proxy in front instead of opening these to 0.0.0.0/0.

## Storage for call recordings

If outbound IVR campaigns or inbound calls are recorded (see [03](03-freepbx-configuration.md) and [06](06-security-hardening.md) for the compliance angle), recordings accumulate fast — budget separately for this and plan either:
- a periodic archive/purge job to object storage (e.g. the same MinIO instance LamaERP already uses for file storage — check `minio-update.yaml` in the ERP repo), or
- a retention policy (e.g. 90 days locally, then delete) enforced via cron.

Don't let recordings share the OS/Asterisk disk without a cap — a full disk on the Asterisk box takes down live calls, not just recordings.

## Next step

Once the server exists with the above network/firewall shape, proceed to [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md).
