# Odoo VoIP ("Phone") — Research & How Our PBX Could Offer the Same Thing

Research into Odoo's VoIP module — renamed **"Phone"** as of Odoo 19.0 ([odoo.com/documentation/19.0](https://www.odoo.com/documentation/19.0/applications/productivity/phone.html)) — covering how it works, how a tenant sets it up, and how the Asterisk/FreePBX server this project already built ([documentation/10](../10-yetiappcloud-install-log.md)) could offer LamaERP tenants an equivalent feature.

## 1. What it is, how it works

Odoo's Phone app is an in-browser calling widget wired into Odoo's business apps (CRM, Helpdesk, contacts) — not a separate softphone application. A phone-shaped icon in the top navigation opens a persistent call widget that stays available while working in any other Odoo app.

**Core stack:** SIP (call signaling) over **WebRTC**, carried over a **WebSocket** connection straight from the browser to a PBX. No desktop app, no browser plugin — it's the same browser-native WebRTC that video-calling web apps use, just for voice/SIP instead of a proprietary video protocol.

**Backend options** (what the "PBX" actually is):
- **Axivox** — Odoo's most integrated option: call queues, dial plans, conference calling, dynamic caller ID, all configurable from within Odoo.
- **OnSIP**, **DIDWW** — other verified hosted SIP providers, credential- or domain-based setup.
- **Custom / self-hosted (Asterisk, FreePBX, etc.)** — Odoo's official docs include a dedicated "Configure your VoIP Asterisk server for Odoo" guide ([odoo.com/documentation/17.0/.../voip/asterisk.html](https://documentation.erptoancau.com/17.0/applications/general/voip/asterisk.html)). Any SIP server works as long as it exposes **WebSocket access + WebRTC support** — which is exactly the shape of a FreePBX/Asterisk box.

**What the self-hosted path technically requires on the Asterisk side** (this is the part that matters for us):
- `http.conf`: Asterisk's built-in mini web server enabled, with a TLS-bound listener (`wss://`, not plain `ws://` — Odoo's docs are explicit that a self-signed cert causes registration failures or mic-permission errors in the browser; a real cert, e.g. Let's Encrypt, is required).
- `pjsip.conf`: a `[transport-wss]` transport (`protocol=wss`, bound to the HTTP(S) listener), and each user's PJSIP endpoint configured for WebRTC: `webrtc=yes` (or explicitly `media_encryption=dtls`, `ice_support=yes`, `dtls_cert_file`/`dtls_private_key`, `rtcp_mux`).
- The WebSocket URL Odoo connects to is literally `wss://<pbx-host>:<port>/ws`.

**Features on top of the calling mechanics:**
- **Click-to-dial** from any CRM/Helpdesk/contact record — click a phone number, the widget dials it.
- Calls and messages get **logged against the customer record** automatically — call history lives on the contact/lead/ticket, not in a separate phone log.
- **Call recording and analytics** — volume, response time, per-agent stats.
- **Call queues / dial plans** for routing inbound support/sales calls.
- **Access roles**: No Access / Officer (view & report) / Administrator (manage settings) — notably, being a database admin doesn't automatically grant Phone-app admin rights; it's assigned separately.

## 2. Steps for a tenant (an Odoo company/database) to install and use it

1. **Install the Phone app** from the Odoo Apps menu (like installing any Odoo module).
2. **Settings → Phone/VoIP configuration** — pick the backend: Axivox / OnSIP / DIDWW, or enter custom SIP server details (PBX server address, WebSocket URL) for a self-hosted PBX.
3. **Assign access roles** to users (No Access / Officer / Administrator) — Settings → Users.
4. **Per-user SIP credentials** — each user's own Preferences → VoIP tab gets a **SIP Login** (their extension number) and **SIP Password** (the extension's secret) — these have to match an actual extension provisioned on the PBX side; Odoo doesn't create PBX extensions itself, an admin provisions them on the PBX and hands the credentials to Odoo.
5. **(Axivox specifically)** additional setup inside the Axivox portal: add users, configure call queues and dial plans, set dynamic caller ID.
6. **Use it**: click the phone icon in the top bar to open the widget; click-to-dial from any record with a phone number; incoming calls pop up the widget with the matching contact.

The pattern for a *self-hosted* backend is: **the PBX is the source of truth for extensions/credentials; Odoo is just a client that registers as one more SIP device per user, over WebRTC, and layers business-record integration on top.**

## 3. How our Asterisk/FreePBX server could offer LamaERP tenants the same thing

This maps directly onto the "custom/self-hosted" path above — **our PBX already is the kind of server Odoo's Phone app connects to.** Two different integration shapes are worth distinguishing, because they solve different problems:

### Option A (already designed) — server-side click-to-call

Covered in [documentation/05-erp-integration.md](../05-erp-integration.md): staff clicks "Call Parent" in the LamaERP UI → the backend calls AMI `Originate` → the staff's **registered SIP device** (a desk phone, or the Linphone softphone from [documentation/12](../12-linphone-extension-setup.md)) rings first → once answered, Asterisk dials the parent and bridges the call. No browser calling code needed — the frontend just fires an API call. This is simpler to build and already fits into the existing `LamaERP.Platform.Telephony` module design.

### Option B (Odoo-equivalent) — in-browser WebRTC calling widget

This is what would make LamaERP feel like Odoo's Phone app: a **calling widget embedded directly in the LamaERP frontend**, with no separate phone device required — staff just click a number and talk through their laptop mic/speakers, right there in the tab.

What this needs, mapped onto what's already built:

| Odoo's requirement | LamaERP/Asterisk equivalent |
|---|---|
| A PJSIP WebRTC endpoint per user | One PJSIP extension per staff member who wants browser calling — same extension mechanism as [doc 03](../03-freepbx-configuration.md)/[doc 12](../12-linphone-extension-setup.md), with FreePBX's per-extension **WebRTC** toggle enabled (sets `media_encryption=dtls`, `ice_support=yes`, `rtcp_mux` automatically) |
| `wss://` transport with a real cert | Already have the pieces: enable the **`wss`** transport toggle on the same "SIP Settings [chan_pjsip]" page used for `tls` in [doc 12](../12-linphone-extension-setup.md) §4, reusing the same Let's Encrypt cert for `sainowine.com.np` |
| A WebSocket URL for the client to connect to | `wss://sainowine.com.np:<port>/ws` — **see the port/proxy note below**, this needs care |
| A frontend client that speaks SIP-over-WebSocket | Not built yet — needs a JS SIP library (**SIP.js** or **JsSIP** — Odoo's own widget is built on the same class of library) embedded in `frontend/tenant`, registering with that staff member's extension credentials on page load |
| Click-to-dial tied to business records | Same idea as Odoo: a "Call" affordance next to a parent/guardian phone number on student/lead records, wired to the embedded widget instead of (or alongside) Option A's server-side Originate |
| Call logging tied to records | Already designed — the `CallLog` entity and AMI/ARI event listener from [doc 05](../05-erp-integration.md) capture this regardless of which option placed the call |

**Important port/security note — don't reuse the ARI port for this.** [Doc 04](../04-asterisk-apis-ami-ari.md) and [doc 09](../09-datahub-production-deployment.md) already put **ARI on 8089**, deliberately restricted to the ERP backend server's IP only (ARI has call-control power — origination, hangup — so it must never be broadly reachable). A public browser-facing WebRTC signaling path needs the opposite: reachable from every staff member's browser, wherever they are. Two ports sharing the same Asterisk HTTP(S) listener with different exposure requirements is a real conflict. The clean fix: put the public `/ws` path behind the **Apache instance already running on this box** (it's already serving the FreePBX admin UI on 443 with the same cert) as a reverse proxy to Asterisk's internal websocket listener — so `https://sainowine.com.np/ws` is public, while the raw ARI port stays firewalled to the ERP backend only, exactly as already documented. This needs an Apache `mod_proxy_wstunnel` vhost rule; not yet built.

**Multi-tenancy note.** Same shared-PBX model as [doc 03](../03-freepbx-configuration.md)'s default: each tenant's staff get extensions on the one shared Asterisk instance, distinguished by a numbering scheme (e.g. a tenant-scoped extension range) rather than a dedicated PBX per school — consistent with the cost reasoning in [documentation/08](../08-open-source-vs-paid-comparison.md).

### Recommendation

Build **Option A first** (it's already fully designed and reuses AMI, which is simpler and lower-risk) and treat **Option B as a later enhancement** once there's a concrete UX reason to want in-browser calling specifically (e.g. staff without desk phones, or wanting the literal "click and talk in the tab" feel Odoo has). Option B is real, proven-possible work — Odoo's own docs are effectively a spec for it — but it adds frontend SIP-client complexity and a reverse-proxy piece that Option A doesn't need.

## Sources

- [Odoo 19.0 Phone app documentation](https://www.odoo.com/documentation/19.0/applications/productivity/phone.html)
- [Odoo saas-19.3 Phone documentation](https://www.odoo.com/documentation/saas-19.3/applications/productivity/phone.html)
- [Configure your VoIP Asterisk server for Odoo — 17.0 mirror](https://documentation.erptoancau.com/17.0/applications/general/voip/asterisk.html)
- [Configure your VoIP Asterisk server for Odoo — saas-15.3](https://www.odoo.com/documentation/saas-15.3/applications/general/voip/asterisk.html)
