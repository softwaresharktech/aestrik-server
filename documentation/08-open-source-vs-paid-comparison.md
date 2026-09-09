# Open Source vs Paid: What Each Path Buys You

"Open source vs paid" actually splits into three separate decisions for this project. This doc covers all three, with the recommendation for LamaERP's actual shape (multi-tenant, Nepal-based tenants, cost-sensitive high-volume outbound campaigns like fee reminders).

1. **Core Asterisk/FreePBX (free) vs Sangoma's commercial FreePBX modules (paid add-ons on the same box)**
2. **Self-hosted Asterisk (open source, run-it-yourself) vs a CPaaS voice API (Twilio/Vonage/Plivo — pay-per-use, no server)**
3. **Self-hosted vs a fully-hosted commercial PBX (3CX Cloud, Sangoma PBXact, RingCentral — someone else runs "your" PBX)**

## 1. Core Asterisk/FreePBX vs Sangoma's paid modules

Everything [02](02-asterisk-freepbx-installation.md)–[05](05-erp-integration.md) rely on — PJSIP, dialplan, IVR, queues, call recording, **AMI, and ARI** — is in the free, open-source core. No paid tier gates the APIs the ERP integration needs. FreePBX's own commercial modules (sold via the Sangoma Portal) are optional conveniences layered on top:

| Module | What it adds | Rough cost | Needed for LamaERP? |
|---|---|---|---|
| Endpoint Manager | Auto-provisions physical desk IP phones | ~$36/yr renewal per the Sangoma portal ([thetelecomspot.com](https://www.thetelecomspot.com/products/sangoma-freepbx-advanced-bundle-license-fpbx-c25y-ab)) | Only if staff get physical desk phones. Softphone/webphone-only staff extensions don't need it. |
| Zulu UC (softphone/UC client) | Polished softphone + presence/chat app | Free for 2 users/12 months, paid per additional user | No — a free SIP softphone (Zoiper, MicroSIP, or a browser WebRTC phone) covers the click-to-call staff-extension leg described in [05](05-erp-integration.md). |
| Sysadmin Pro | GUI backup/restore, network config | Bundled in paid bundles | Nice-to-have ops convenience, not a functional requirement. |
| Advanced/Everything Bundles | Grab-bag of the above plus fax, call reports, etc. | Advanced Bundle valued at ~$1,528 if bought separately ([voipsupply.com](https://www.voipsupply.com/sangoma-freepbx-everything-bundle-fpbx-c01y-eb-commercial-module-software)) | Skip at launch. Revisit individual modules only if a specific gap shows up (e.g. many physical phones to provision). |

**Bottom line:** nothing in the documented integration requires a paid FreePBX module. Treat these as optional, evaluate one at a time if a real operational need appears (e.g. "we're issuing 40 desk phones, provisioning them by hand is painful" → Endpoint Manager).

## 2. Self-hosted Asterisk vs a CPaaS voice API (Twilio / Vonage / Plivo)

This is the more consequential decision — it's a different architecture, not an add-on. Instead of provisioning a DataHub server ([01](01-server-provisioning.md)) and installing Asterisk ([02](02-asterisk-freepbx-installation.md)), the ERP backend could call a hosted voice API (Twilio Voice, Vonage, Plivo) directly — no PBX to run at all.

| | Self-hosted Asterisk (this doc set) | CPaaS (e.g. Twilio Voice) |
|---|---|---|
| Setup effort | Provision server, install, configure trunk/extensions/IVR ([01](01-server-provisioning.md)–[03](03-freepbx-configuration.md)) | Sign up, buy a number, call a REST API |
| Ongoing ops | You patch/secure/monitor a Linux box indefinitely ([06](06-security-hardening.md)) | None — carrier-grade infra managed by the provider |
| Fixed cost | Server cost regardless of call volume (~$10–40/mo class of box per [01](01-server-provisioning.md)) | $0 fixed; scales purely with usage |
| Per-minute cost, Nepal mobile | Local SIP trunk rate (typically low single-digit US cents/min for domestic termination — get an actual quote from the trunk provider chosen in [03](03-freepbx-configuration.md)) | **$0.3084/min** (Twilio's published Nepal mobile rate — [twilio.com/en-us/voice/pricing/np](https://www.twilio.com/en-us/voice/pricing/np)) |
| Per-minute cost, Nepal landline | Same local trunk rate | $0.2981/min (same source) |
| Built-in extras | None out of the box — TTS/STT/transcription would be a separate integration | Speech recognition, call recording ($0.0025/min), conferencing available as add-on API features |
| Multi-country tenants | Needs a trunk/DID per country, or a trunk provider with broad coverage | One account, works globally with no per-country trunk setup |
| API surface | AMI + ARI, self-hosted, full control ([04](04-asterisk-apis-ami-ari.md)) | Vendor REST API + webhooks, fully managed |

**The cost gap is the deciding factor here.** Twilio's Nepal mobile rate (~$0.31/min) is roughly **20x** a typical domestic SIP trunk rate. For LamaERP's actual use cases — fee-reminder and attendance-alert voice campaigns potentially reaching hundreds or thousands of parents per tenant, per run — that multiplier compounds fast:

> Illustrative, not a quote: 1,000 minutes/month of parent calls ≈ **~$308/month** on Twilio (Nepal mobile rate) vs. a self-hosted box (~$20–40/mo) plus local trunk minutes at domestic rates (get an actual quote, but this is typically well under $50/month at that volume). The self-hosted path is cheaper by a wide margin specifically *because* the traffic is Nepal-domestic.

CPaaS providers (Vonage $0.00798/min, Plivo $0.0115/min for **US** calls — [apicostcalc.com](https://apicostcalc.com/blog/twilio-vs-vonage-vs-plivo-voice-call-cost.html)) are only cheap for US/Western-Europe-heavy traffic; Nepal-specific rates for Vonage/Plivo weren't published in a way this research could confirm — if a CPaaS path is ever reconsidered, get a Nepal-specific quote from each before comparing, don't assume US rates transfer.

**Where CPaaS would still make sense:**
- A tenant based outside Nepal, where the domestic-trunk cost advantage disappears.
- Needing to launch before the DataHub server/trunk is ready — a CPaaS could prototype the click-to-call/IVR flow in days.
- No in-house appetite for the ongoing security/ops burden in [06-security-hardening.md](06-security-hardening.md).
- Wanting built-in TTS/STT rather than building that separately.

None of those currently apply to LamaERP's primary case (Nepal-domestic, ops-capable team already running DataHub infrastructure), so self-hosted is the right default — but it's worth keeping the door open. The `IAmiClient`/`IAriClient` interfaces proposed in [05-erp-integration.md](05-erp-integration.md) already isolate the Telephony module's Application layer from the transport — a Twilio-backed implementation of `ITelephonyDispatcher` could be swapped in later (e.g. per-tenant, for a non-Nepal tenant) without touching the Application/Domain layers.

## 3. Self-hosted vs a fully-hosted commercial PBX (3CX Cloud, PBXact, RingCentral, etc.)

A middle ground: someone else runs the actual PBX server, but it's a subscription, not pay-per-use — you're not calling a raw voice API, you're renting a managed phone system.

- 3CX: free for up to 10 users self-hosted/on-prem; paid tiers are licensed by simultaneous calls rather than user count, and 3CX has moved new hosted deployments to commercial-only ([ringoffice.com](https://ringoffice.com/blog/3cx-vs-freepbx), [sipnex.ca](https://www.sipnex.ca/blog/3cx-vs-freepbx)).
- Realistic 36-month TCO for a self-hosted PBX (self-run, in-house expertise) lands around **$12–35 per user/month** once support, hardware refresh, and admin time are counted for a 50–300 user deployment ([ringoffice.com](https://ringoffice.com/blog/3cx-vs-freepbx)) — hosted/managed alternatives trade a chunk of that cost for less in-house effort.

This model doesn't fit LamaERP's shape well: LamaERP is one platform serving **many small tenants** (individual schools), not one org with 50–300 internal users. A per-user hosted-PBX subscription would need to be multiplied per tenant, and — more importantly — commercial hosted PBX offerings vary in whether they expose an AMI/ARI-equivalent API for the kind of programmatic Originate-and-Stasis control [04-asterisk-apis-ami-ari.md](04-asterisk-apis-ami-ari.md) depends on. Self-hosting keeps that API access guaranteed and keeps per-tenant marginal cost low (shared server, shared FreePBX instance, per-tenant `TelephonySettings` row per [05](05-erp-integration.md)) rather than paying a per-seat SaaS fee multiplied across every school tenant.

## Recommendation

- **Core platform: self-hosted, open-source Asterisk + FreePBX**, exactly as documented in [01](01-server-provisioning.md)–[07](07-rollout-checklist.md). Zero licensing cost, full AMI/ARI access, and the per-tenant multi-tenancy model in [03](03-freepbx-configuration.md)/[05](05-erp-integration.md) fits a many-small-tenants platform far better than a per-seat hosted PBX.
- **Skip Sangoma's paid FreePBX modules at launch.** Nothing documented here needs them; add one only if a concrete operational gap appears (e.g. bulk physical phone provisioning).
- **Don't use Twilio/Vonage/Plivo as the primary path for Nepal-domestic traffic** — confirmed roughly 20x more expensive per minute than a local SIP trunk for this specific corridor. Keep a CPaaS as a documented fallback for non-Nepal tenants or for prototyping ahead of server availability, via the `ITelephonyDispatcher` abstraction already in the design.
- **Get an actual quote from the SIP trunk provider chosen in [03-freepbx-configuration.md](03-freepbx-configuration.md)** before finalizing any cost model here — the domestic trunk rate used above is illustrative, not sourced from a specific provider.

Sources: [Sangoma FreePBX Advanced Bundle License](https://www.thetelecomspot.com/products/sangoma-freepbx-advanced-bundle-license-fpbx-c25y-ab), [Sangoma FreePBX Everything Bundle](https://www.voipsupply.com/sangoma-freepbx-everything-bundle-fpbx-c01y-eb-commercial-module-software), [Twilio Voice Pricing — Nepal](https://www.twilio.com/en-us/voice/pricing/np), [Twilio vs Vonage vs Plivo cost comparison](https://apicostcalc.com/blog/twilio-vs-vonage-vs-plivo-voice-call-cost.html), [3CX vs FreePBX TCO](https://ringoffice.com/blog/3cx-vs-freepbx), [3CX vs FreePBX pricing model](https://www.sipnex.ca/blog/3cx-vs-freepbx).
