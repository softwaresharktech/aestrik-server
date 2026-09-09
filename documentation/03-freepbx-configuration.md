# FreePBX Configuration for LamaERP Use Cases

Prerequisite: FreePBX is installed and reachable per [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md).

## SIP trunk

Pick a SIP trunk provider (ITSP) that covers the phone numbers LamaERP tenants need to dial/receive on — this is a business decision (coverage, per-minute rates, DID availability, IP-auth vs registration-auth) that hasn't been made yet in these docs; whichever is chosen, plug it in as a **PJSIP trunk**:

- Connectivity → Trunks → Add Trunk → PJSIP Trunk.
- Auth: prefer IP authentication over username/password registration where the provider supports it — one less credential to leak.
- Match the provider's codec list (usually `ulaw`/`alaw`, sometimes `g729` — g729 needs a licensed module).
- Set the outbound CallerID the provider has authorized for this trunk.

Verify registration status (if registration-based) under **Reports → Asterisk Info** or `asterisk -rx "pjsip show registrations"` before moving on.

## Extensions

One PJSIP extension per staff member who needs click-to-call or a desk/soft phone (admissions desk, accounts/fees office, front office). Connectivity → Extensions → Add PJSIP Extension. Use strong, generated secrets — see [06-security-hardening.md](06-security-hardening.md) for why this matters (toll fraud).

These extensions are what the ERP's "click-to-call" flow will `Originate` through — the call legs into the staff member's extension first, then out to the parent's number, once answered (see the sequence in [05-erp-integration.md](05-erp-integration.md)).

## Outbound routes

Standard **Connectivity → Outbound Routes**: match dial patterns (e.g. Nepal mobile/landline prefixes, or whatever the tenant base actually needs), send to the trunk above. Keep route patterns as specific as practical — an overly permissive route is a toll-fraud vector if any credential ever leaks.

## Inbound routes / IVR

For the published school number(s):

- **Applications → IVR**: build a menu (e.g. "Press 1 for Admissions, 2 for Accounts, 3 for the Front Office"), each option routing to a ring group or queue.
- **Applications → Ring Groups / Queues**: front office and admissions extensions ring together; queues if hold/overflow behavior is needed later.
- **Applications → Recordings**: upload/record the IVR prompts. If prompts need to be dynamic per tenant (school name, hours), that's a good candidate to generate as audio files from the ERP side and push into Asterisk's recordings, rather than re-recording by hand per tenant — revisit once multi-tenant IVR volume justifies it.

## Call recording

**Applications → Outbound Route / Inbound Route → Call Recording**, or per-extension recording, depending on what needs to be captured (admissions counselling calls, for example). See [06-security-hardening.md](06-security-hardening.md) for consent/retention obligations before turning this on broadly — this is a compliance decision, not just a technical toggle.

## Multi-tenant mapping

LamaERP is multi-tenant with **one Postgres database per tenant** (`Tenant.DatabaseName`, see [Tenant.cs](../../FinalLamaErp/src/Platform/LamaERP.Platform.MultiTenancy/Domain/Entities/Tenant.cs)) and per-tenant contact info (`Tenant.ContactNumber`). Asterisk itself has no native concept of "tenant" — that mapping needs to be decided and enforced at the ERP layer, not inside Asterisk config. Two options, in increasing order of isolation:

| Approach | How | When it fits |
|---|---|---|
| **Shared trunk, per-tenant CallerID** | One trunk, one dialplan; the ERP passes each tenant's registered CallerID/DID when it originates a call, stored in a new per-tenant `TelephonySettings` row (mirrors how `Tenant.ContactNumber` already exists). Requires a trunk/provider that allows CallerID-per-call, not just CallerID-per-trunk. | Default starting point — least infrastructure, works for most schools. |
| **Dedicated PJSIP context (or dedicated trunk) per tenant** | Separate Asterisk dialplan context, possibly a separate trunk/DID block, selected by a `TelephonySettings.AsteriskContext` field the ERP passes on originate. | Larger tenants that need their own DID range, distinct billing, or call-recording isolation. |

Either way, the ERP side owns the tenant → trunk/context/CallerID mapping (see the `TelephonySettings` entity sketched in [05-erp-integration.md](05-erp-integration.md)) — Asterisk/FreePBX just needs the corresponding trunk(s)/context(s) to exist. Don't let Asterisk config drift out of sync with what the ERP thinks exists; whichever side is authoritative (recommend the ERP, since it already owns tenant provisioning) should be the one that drives changes, with FreePBX as the executor.

## Next step

With trunks, extensions, and inbound routing in place, move to [04-asterisk-apis-ami-ari.md](04-asterisk-apis-ami-ari.md) to see how the ERP backend actually drives calls through this.
