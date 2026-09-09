# Rollout Checklist

Sequenced plan from nothing to a live, ERP-integrated voice channel. Each phase links back to the doc that covers it in detail.

## Phase 0 — Decisions (blocking, do first)

- [ ] Choose a SIP trunk provider (coverage, DID availability, IP-auth support, rate, concurrent-channel limits).
- [ ] Confirm DataHub can provide a private network path (or VPN) between the ERP backend and the new Asterisk server.
- [ ] Confirm call-recording legal/compliance requirements for the relevant jurisdiction(s) — see [06](06-security-hardening.md).
- [ ] Decide AMI/ARI .NET client approach: hand-rolled vs AsterNET — see [04](04-asterisk-apis-ami-ari.md).

## Phase 1 — Server

- [ ] Provision the DataHub server per [01-server-provisioning.md](01-server-provisioning.md) (sizing, OS, static private IP).
- [ ] Lock down firewall/security groups (default-deny, only the ports/sources listed in 01).
- [ ] Verify NTP is correct before proceeding.

## Phase 2 — Asterisk + FreePBX

- [ ] Run the FreePBX 17 installer per [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md).
- [ ] Set FreePBX admin credentials, apply module updates.
- [ ] TLS on the FreePBX admin UI (Certificate Manager or reverse-proxy TLS).
- [ ] Enable AMI, scoped to the ERP backend's private IP only.
- [ ] Enable ARI over TLS, scoped to the ERP backend's private IP only.
- [ ] Confirm from the ERP backend host that AMI (5038) and ARI (8089/443) are reachable, and confirm from an outside host that they are **not**.

## Phase 3 — FreePBX configuration

- [ ] Add the SIP trunk from Phase 0, verify registration/connectivity.
- [ ] Create extensions for the first pilot tenant's staff.
- [ ] Configure outbound routes (specific dial patterns, not wildcard).
- [ ] Configure inbound route + IVR for the pilot tenant's published number.
- [ ] Decide and configure call-recording scope, if any (per Phase 0 compliance decision).

## Phase 4 — Security hardening

- [ ] fail2ban enabled and tested (deliberately fail a registration a few times from an unlisted IP, confirm the ban).
- [ ] Concurrent-call caps set on trunk and extensions.
- [ ] AMI/ARI secrets stored per environment in the ERP's existing secrets mechanism, not committed to source.
- [ ] Monitoring/alerting wired for fail2ban events, security log, disk usage, trunk registration state (see [06](06-security-hardening.md)).

## Phase 5 — ERP module

- [ ] Scaffold `LamaERP.Platform.Telephony` per [05-erp-integration.md](05-erp-integration.md), following the existing Clean Architecture layout ([ARCHITECTURE.md](../../FinalLamaErp/ARCHITECTURE.md)).
- [ ] Implement `IAmiClient` (Originate + event stream) and, if campaigns are in scope for launch, `IAriClient` (Stasis app for IVR/DTMF).
- [ ] Implement `TelephonySettings` (per-tenant trunk/context/CallerId) and wire tenant provisioning to populate it.
- [ ] Implement `ITelephonyDispatcher.PlaceClickToCallAsync` + endpoint + `CallLog` persistence.
- [ ] Implement the background event listener that updates `CallLog` from AMI/ARI events and pushes live status to the frontend.

## Phase 6 — Pilot (click-to-call only)

- [ ] Enable click-to-call for one pilot tenant's staff.
- [ ] Verify: staff extension rings → answer → parent leg dials → bridges → `CallLog` populated correctly (status, duration).
- [ ] Verify screen-pop / call-status UI in `frontend/tenant`.
- [ ] Run for a defined period (e.g. 1–2 weeks) before expanding — this is the cheapest phase to catch trunk/config issues in, with the smallest blast radius.

## Phase 7 — Automated voice campaigns

- [ ] Implement `StartVoiceCampaignAsync` + `lamaerp-ivr` ARI Stasis app (prompt playback, DTMF capture).
- [ ] Rate-limit campaign dispatch against the trunk's concurrent-call cap — never let a campaign job try to blast every recipient at once.
- [ ] Pilot a small fee-reminder or attendance-alert campaign for one tenant; verify outcomes land correctly in `CallCampaignTarget`/`CallLog`.
- [ ] Decide whether to unify under `NotifChannel.Voice` in the Notifications module (optional — see [05](05-erp-integration.md)) once the standalone flow is proven.

## Phase 8 — Security review + general availability

- [ ] Re-review Phase 4 hardening against actual production traffic patterns.
- [ ] Confirm call-recording retention/deletion job is running (if recording is enabled).
- [ ] Confirm alerting has actually fired correctly at least once in a drill (don't trust an alert path that's never been tested).
- [ ] Roll out to remaining tenants, `TelephonySettings` populated per tenant as they're onboarded.
