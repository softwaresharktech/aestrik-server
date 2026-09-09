# Asterisk × LamaERP — Overview

## What Asterisk is

[Asterisk](https://www.asterisk.org/) is an open-source communications engine (C, Digium/Sangoma-maintained) that turns a regular server into a telephony platform: SIP registrar/proxy, call routing (dialplan), IVR, voicemail, conferencing, queues, call recording, and a programmable call-control surface. It speaks SIP/PJSIP to phones, softphones, and SIP trunk providers, and bridges calls between them (PSTN ⟷ PSTN, PSTN ⟷ app, app ⟷ app).

Asterisk itself has **no GUI** — it's configured via text files (`extensions.conf`, `pjsip.conf`, ...) or a management API. That's where FreePBX comes in.

## What FreePBX is

[FreePBX](https://www.asterisk.org/asteriskexchange/freepbx/) is the most widely used open-source web GUI for Asterisk (PHP/JS, modular). It manages extensions, trunks, inbound/outbound routing, IVRs, queues, recordings, and the manager/REST-API users — without hand-editing Asterisk config files. FreePBX 17+ installs directly on Debian and bundles a supported Asterisk LTS build. It's the recommended front end for whoever administers the phone system day to day (not something the ERP talks to at runtime — the ERP talks to Asterisk's own APIs, see [05](05-asterisk-apis-ami-ari.md)).

## Why LamaERP needs this

LamaERP ([FinalLamaErp](../../FinalLamaErp)) is a multi-tenant school ERP. Each tenant (school) already gets a `LamaERP.Platform.Notifications` module that dispatches `Announcement`, `FeeReminder`, `AttendanceAlert`, etc. over `InApp`, `WebPush`, `Fcm`, `Sms`, and `Email` channels (see `NotifChannel` in [NotificationEnums.cs](../../FinalLamaErp/src/Platform/LamaERP.Platform.Notifications/Domain/Enums/NotificationEnums.cs)). Voice is the channel that's missing, and it matters specifically for this domain:

- **Fee reminder / attendance alert voice calls** — many parents (especially in rural/older demographics) don't reliably read SMS or app notifications. An automated IVR call ("Your child was marked absent today. Press 1 to acknowledge.") reaches them.
- **Click-to-call** — front-office/admissions staff calling a parent directly from the ERP UI, with the call logged against the student/lead record.
- **Inbound IVR / queues** — a published school phone number that routes to admissions, accounts, or the front desk, with call recording for accountability.
- **Screen pop** — when a parent calls in, the staff UI can show who's calling (matched by phone number) before the call is answered.

## High-level architecture

```
┌─────────────────────┐        SIP trunk (PSTN)
│   ITSP / carrier     │◄───────────────────────────┐
└─────────────────────┘                              │
                                                       ▼
┌───────────────────────────────────────────────────────────────┐
│  DataHub server — Asterisk + FreePBX               (see 02, 03) │
│  - PJSIP endpoints, trunks, dialplan, IVR, recordings           │
│  - AMI (5038, internal only)  +  ARI (HTTPS, internal only)     │
└───────────────────────────────────────────────────────────────┘
              ▲ AMI (originate / events)   ▲ ARI (REST + WebSocket)
              │                             │
┌───────────────────────────────────────────────────────────────┐
│  LamaERP backend — new LamaERP.Platform.Telephony module        │
│  (Domain / Application / Infrastructure / API, same Clean        │
│   Architecture layering as every other module)      (see 06)    │
└───────────────────────────────────────────────────────────────┘
              ▲
              │ REST / SignalR-style live events
┌───────────────────────────────────────────────────────────────┐
│  frontend/tenant — "Call" button, screen-pop, call log UI        │
└───────────────────────────────────────────────────────────────┘
```

## Scope of this documentation set

| Doc | Covers |
|---|---|
| [00-overview.md](00-overview.md) | This file |
| [01-server-provisioning.md](01-server-provisioning.md) | Sizing, network, firewall for the new DataHub server |
| [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md) | Installing Asterisk + FreePBX from scratch |
| [03-freepbx-configuration.md](03-freepbx-configuration.md) | Trunks, extensions, IVR, queues, multi-tenant mapping |
| [04-asterisk-apis-ami-ari.md](04-asterisk-apis-ami-ari.md) | AMI vs ARI, auth, example call flows |
| [05-erp-integration.md](05-erp-integration.md) | New `LamaERP.Platform.Telephony` module design |
| [06-security-hardening.md](06-security-hardening.md) | Toll-fraud prevention, secrets, network isolation |
| [07-rollout-checklist.md](07-rollout-checklist.md) | Phased go-live plan |

This is a documentation-only pass — no server has been provisioned and no code has been written yet. Treat these as the plan to execute against, and update them as decisions are made (SIP trunk provider, actual DataHub server specs/IPs, module names, etc. are currently best-guess/placeholder).
