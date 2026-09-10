# Connecting a Softphone (Linphone) to an Extension

How a SIP extension was set up on the YetiApp Cloud install to work with roaming softphones (phones that move between networks — office wifi, mobile data, home), using [Linphone](https://linphone.org/) as the reference client. Encrypted end to end: SIP signaling over TLS, media over SRTP.

Prerequisite: FreePBX is installed and reachable at `https://sainowine.com.np/admin` — see [10-yetiappcloud-install-log.md](10-yetiappcloud-install-log.md).

## Why the roaming approach (open SIP + fail2ban), not IP-scoped

Two options exist for exposing SIP:
- **IP-scoped**: firewall SIP/RTP to a fixed office IP only — tighter, but breaks the moment a phone isn't on that network.
- **Open + hardened** (chosen here): SIP/RTP open to `0.0.0.0/0`, protected by fail2ban, strong per-extension secrets, and TLS/SRTP. Works from anywhere.

This project went with the roaming approach since phones need to work outside a single fixed office connection.

## 1. Enable fail2ban first

Do this **before** opening SIP to the internet — an unprotected open port gets brute-forced within hours.

```bash
systemctl enable --now fail2ban
```

`/etc/fail2ban/jail.d/asterisk.local`:

```ini
[asterisk]
enabled  = true
filter   = asterisk
port     = 5060,5061
protocol = udp
logpath  = /var/log/asterisk/messages
maxretry = 5
findtime = 600
bantime  = 86400
```

```bash
systemctl restart fail2ban
fail2ban-client status asterisk   # confirm the jail is active
```

## 2. Create the extension

FreePBX admin → **Connectivity → Extensions → Add Extension → Add New PJSIP Extension**.

- **User Extension**: e.g. `1001`
- **Display Name**: e.g. the person's name
- **Secret**: use FreePBX's auto-generated one — long and random, never a simple password (SIP is open to the internet)

Submit → **Apply Config**. (Two extensions exist on this install: `1001` Manish, `1002` Bipin.)

## 3. Lock down PBX-side SIP settings

**Settings → Asterisk SIP Settings → General SIP Settings**:
- **Allow Anonymous Inbound SIP Calls**: No (default — confirm it)
- **External Address**: the server's public IP (`103.90.84.156`)
- **Local Networks**: the internal Jelastic network (`10.121.0.0/16`)

This is what lets Asterisk correctly tell phones where to send media despite being behind YetiApp's NAT — without it, calls can register but have no audio.

## 4. Enable the TLS transport

**Settings → Asterisk SIP Settings → SIP Settings [chan_pjsip]**:

1. **TLS/SSL/SRTP Settings → Certificate Manager**: select the Let's Encrypt cert for the domain (issued via Certificate Manager, see [10](10-yetiappcloud-install-log.md) §7).
2. **Transports → `tls - 0.0.0.0 - All`**: toggle to **Yes**. A `0.0.0.0 (tls)` block appears — leave **Port to Listen On = 5061**.
3. Submit → Apply Config → **restart Asterisk fully** (transport changes need a restart, not just a reload — FreePBX says so on this page):
   ```bash
   fwconsole restart
   ```

Verify both transports are up:

```bash
asterisk -rx "pjsip show transports"
```
```
Transport:  0.0.0.0-tls    tls    3    96    0.0.0.0:5061
Transport:  0.0.0.0-udp    udp    3    96    0.0.0.0:5060
```

Verify the cert actually bound to the TLS transport:

```bash
asterisk -rx "pjsip show transport 0.0.0.0-tls"
```
Look for `cert_file` / `priv_key_file` pointing at the domain's cert files (e.g. `/etc/asterisk/keys/sainowine.com.np-fullchain.crt`), and `external_signaling_address` / `local_net` matching step 3.

**Hardening follow-up (not done yet):** `method` defaults to `tlsv1` (accepts TLS 1.0 as the floor). Set **SSL Method → tlsv1_2** on this page to require modern TLS. Clients still negotiate up to their best version either way, so this isn't a functional blocker — just tighten it when convenient. Tracked in [11-deferred-steps.md](11-deferred-steps.md).

## 5. Enable SRTP on the extension

**Connectivity → Extensions → [extension] → Advanced tab → Media Encryption**: set to `SRTP` (or `Best effort SRTP` while testing, so a client that doesn't support SRTP can still register — plain, not encrypted). Submit → Apply Config.

## 6. Jelastic firewall — inbound rules

On the Elastic VPS node → **Firewall → Inbound Rules**, add (in addition to the existing 80/443 rules from [10](10-yetiappcloud-install-log.md)):

| Priority | Name | Protocol | Port Range | Source | Action |
|---|---|---|---|---|---|
| 1060 | Allow SIP | UDP | 5060 | `0.0.0.0/0` | ALLOW |
| 1070 | Allow SIP TLS | **TCP** | 5061 | `0.0.0.0/0` | ALLOW |
| 1080 | Allow RTP | UDP | 10000-20000 | `0.0.0.0/0` | ALLOW |

TLS SIP runs over TCP, not UDP — easy to get wrong. RTP media stays UDP regardless of signaling transport.

## 7. Configure Linphone

Install Linphone (App Store / Play Store / [linphone.org](https://linphone.org/) for desktop) → **Add account → Use a third-party SIP account** (not a linphone.org account):

- **Username**: the extension number (e.g. `1001`)
- **Domain / SIP server**: `sainowine.com.np` — **use the hostname, not the IP.** The TLS cert is issued for that hostname; connecting by IP fails certificate validation.
- **Password**: the extension's secret from step 2
- **Transport**: TLS
- **Media encryption**: SRTP

## 8. Test

- Linphone should show **Connected / Registered**.
- On the server:
  ```bash
  asterisk -rx "pjsip show contacts"
  ```
  Should list the extension with the phone's current IP and transport `tls`.
- Dial **`*43`** (echo test) from the softphone — clear two-way audio confirms SIP/TLS + SRTP + RTP + NAT are all working end to end.
- For two extensions calling each other: audio relays **through the PBX** (Asterisk bridges both legs) — the phones never need to reach each other directly, only the PBX. This is why the roaming setup works regardless of which networks the two phones are on.

## Troubleshooting

If registration fails:

```bash
asterisk -rx "pjsip set logger on"
asterisk -rvvv
```
Then retry registration from the client and watch the console — shows whether packets are arriving and, if so, why they're being rejected (wrong secret, transport mismatch, NAT issue).

```bash
asterisk -rx "pjsip show endpoints"     # confirms the extension exists as a PJSIP endpoint
fail2ban-client status asterisk          # check you haven't locked yourself out via too many failed attempts
```
