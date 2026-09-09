# ERP Application Integration

How `LamaERP` (in `../../FinalLamaErp`) connects to the Asterisk server from [02](02-asterisk-freepbx-installation.md)/[03](03-freepbx-configuration.md), using the AMI/ARI surface from [04-asterisk-apis-ami-ari.md](04-asterisk-apis-ami-ari.md).

This is a design proposal, not yet implemented — no `Telephony` module exists in the ERP repo today. It's written to follow the conventions already established by the sibling `LamaERP.Platform.Notifications` module.

## Where this fits: a new Platform module

The repo's [ARCHITECTURE.md](../../FinalLamaErp/ARCHITECTURE.md) mandates strict Clean Architecture per module: `Domain` → `Application` → `Infrastructure` → `API`, each only depending on the layer(s) inward of it. A new `LamaERP.Platform.Telephony` module (name TBD) follows the same shape as `LamaERP.Platform.Notifications`:

```
LamaERP.Platform.Telephony/
├── Domain/
│   ├── Entities/        CallLog, TelephonySettings, CallCampaign, CallCampaignTarget
│   └── Enums/           CallDirection, CallStatus, CallPurpose, CallOutcome
├── Application/
│   ├── Interfaces/      ITelephonyDispatcher, IAmiClient, IAriClient, ICallTargetResolver
│   ├── Commands/         PlaceClickToCallCommand, StartVoiceCampaignCommand
│   ├── Queries/          GetCallLogQuery, GetCallCampaignStatusQuery
│   └── Handlers/
├── Infrastructure/
│   ├── Ami/              AsteriskAmiClient (TCP socket client from 04)
│   ├── Ari/               AsteriskAriClient (HTTP + WebSocket client from 04)
│   ├── Persistence/       CallDbContext, EF configs/migrations (own DB, same pattern as NotificationDbContext)
│   └── Services/          CallDispatchService, CallEventListenerService (background worker)
└── API/
    └── Endpoints/         TelephonyEndpoints (click-to-call action, campaign CRUD, call-log queries)
```

### Domain sketch

```csharp
public enum CallDirection { Outbound, Inbound }
public enum CallStatus { Queued, Ringing, Answered, Completed, NoAnswer, Busy, Failed }
public enum CallPurpose { ClickToCall, FeeReminder, AttendanceAlert, Admissions, Support }

public sealed class TelephonySettings
{
    public Guid TenantId { get; set; }
    public string TrunkOrContext { get; set; } = default!;   // maps to the Asterisk trunk/context chosen in 03
    public string CallerId { get; set; } = default!;          // tenant-specific outbound CallerID
    public bool RecordingEnabled { get; set; }
}

public sealed class CallLog
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public CallDirection Direction { get; set; }
    public CallPurpose Purpose { get; set; }
    public CallStatus Status { get; set; }
    public string FromNumber { get; set; } = default!;
    public string ToNumber { get; set; } = default!;
    public Guid? InitiatedByUserId { get; set; }      // staff member, for click-to-call
    public Guid? RelatedStudentId { get; set; }         // for screen-pop / CRM-style lookup
    public string? AsteriskChannelId { get; set; }
    public DateTime StartedAtUtc { get; set; }
    public DateTime? EndedAtUtc { get; set; }
    public int? DurationSeconds { get; set; }
    public string? RecordingUrl { get; set; }
}
```

`TelephonySettings` is the per-tenant row referenced in [03-freepbx-configuration.md](03-freepbx-configuration.md)'s multi-tenant mapping section — this is the authoritative source the ERP uses to pick which trunk/context/CallerID to originate through for a given tenant.

### Application layer — mirroring the Notifications dispatcher pattern

The existing [`INotificationDispatcher`](../../FinalLamaErp/src/Platform/LamaERP.Platform.Notifications/Application/Interfaces/INotificationDispatcher.cs) fans a persisted `Notification` out to per-recipient deliveries across channels. The Telephony module's equivalent:

```csharp
public interface ITelephonyDispatcher
{
    Task<CallLog> PlaceClickToCallAsync(
        Guid tenantId, Guid staffExtensionUserId, string parentNumber,
        Guid? relatedStudentId, CancellationToken ct = default);

    Task<int> StartVoiceCampaignAsync(
        Guid tenantId, CallPurpose purpose, IReadOnlyList<string> recipientNumbers,
        string promptAudioUrl, CancellationToken ct = default);
}
```

`Infrastructure` implements this against `IAmiClient` (click-to-call — see the `Originate` example in [04](04-asterisk-apis-ami-ari.md)) and `IAriClient` (voice campaigns — Stasis app with DTMF capture, also in 04).

**Cross-module boundary, same pattern as today:** `INotificationSenderResolver` is [implemented in the API host, not the Notifications project itself](../../FinalLamaErp/src/Platform/LamaERP.Platform.Notifications/Application/Interfaces/INotificationSenderResolver.cs), specifically to keep the Notifications platform project free of dependencies on Identity/HR/file-storage modules. The Telephony module should do the same: define `ICallTargetResolver` (student/parent phone lookup) in its own `Application/Interfaces`, and implement it in the API host where it can see the School/Attendance/Billing modules.

### Adding Voice as a notification channel (optional, later)

`NotifChannel` currently has `InApp, WebPush, Fcm, Sms, Email` ([NotificationEnums.cs](../../FinalLamaErp/src/Platform/LamaERP.Platform.Notifications/Domain/Enums/NotificationEnums.cs)). A `Voice` value could be added once the Telephony module exists, with an adapter (implemented at the API host composition root, not a direct project reference — Notifications must not depend on Telephony) that calls `ITelephonyDispatcher.StartVoiceCampaignAsync` when a notification's channel resolves to `Voice`. Don't do this on day one — get click-to-call and a single manual campaign flow working first, then decide if unifying under the Notifications pipeline is worth it versus keeping Telephony's campaign API separate.

### Background worker — call events → CallLog

Same shape as `NotificationDispatchService`/the notification outbox worker: a hosted service holds a persistent AMI connection (or ARI WebSocket, depending which leg placed the call), listens for `Hangup`/`StasisEnd` events, and updates the matching `CallLog` row by `AsteriskChannelId` (status, duration, hangup cause). This is also where a **live in-app event** gets pushed to the frontend for screen-pop / call-status UI — reuse whatever transport the Notifications module already uses to "push the live in-app event" (per the doc comment on `INotificationDispatcher`) rather than introducing a second real-time channel.

## Example flow: click-to-call

```
Staff clicks "Call Parent" in frontend/tenant
        │
        ▼
POST /api/telephony/click-to-call  { studentId, staffExtension }
        │
        ▼
TelephonyEndpoints → PlaceClickToCallCommand → handler
        │  resolves parent number via ICallTargetResolver
        │  resolves TelephonySettings for TenantId (trunk/context/CallerId)
        ▼
ITelephonyDispatcher.PlaceClickToCallAsync
        │
        ▼
IAmiClient.OriginateAsync(staffExtension, parentNumber, callerId, ...)
        │
        ▼
Asterisk: rings staff extension → on answer, dials parent → bridges
        │
        ▼
AMI events (Newchannel/Bridge/Hangup) ─→ CallEventListenerService ─→ updates CallLog
                                                    │
                                                    ▼
                                     live event → frontend call-status UI
```

## Example flow: automated fee-reminder voice campaign

```
Accounts staff (or a scheduled job) starts a campaign for tenant X's
overdue-fee list
        │
        ▼
StartVoiceCampaignCommand → ITelephonyDispatcher.StartVoiceCampaignAsync
        │  writes one CallCampaignTarget row per recipient (queued)
        ▼
CallDispatchService (background worker, rate-limited — do not blast the
trunk's concurrent-call limit) pops queued targets, one at a time / batched
        │
        ▼
IAriClient.OriginateIntoStasisAsync(number, app: "lamaerp-ivr", callerId)
        │
        ▼
Asterisk → StasisStart event on ARI WebSocket
        │
        ▼
lamaerp-ivr app: answer → play prompt ("fee of Rs. X is due...") →
  wait for DTMF → branch (1 = acknowledge, 2 = connect to accounts) → hang up
        │
        ▼
StasisEnd / ChannelDestroyed → CallEventListenerService → updates
CallCampaignTarget + CallLog with outcome (acknowledged / no-answer / etc.)
```

## Frontend (`frontend/tenant`)

- A "Call" action wherever a parent/guardian phone number is shown (student profile, admissions lead, fee ledger) — calls `POST /api/telephony/click-to-call`.
- A call-status indicator (ringing/connected/ended) fed by the same live-event transport Notifications already uses.
- A call log view per student/lead (from `CallLog`), and a campaign status view (sent/acknowledged/failed counts) for fee-reminder/attendance-alert campaigns — same shape as the existing notification delivery reporting.

## Next steps before writing code

1. Confirm the SIP trunk provider (affects trunk auth style, CallerID rules, concurrent-call limits — directly shapes `TelephonySettings` and campaign rate-limiting).
2. Decide AMI/ARI client approach (hand-rolled vs AsterNET — see [04](04-asterisk-apis-ami-ari.md)).
3. Decide whether recordings are needed at launch (compliance review first — see [06-security-hardening.md](06-security-hardening.md)).
4. Scaffold the module per [scaffold_folders.ps1](../../FinalLamaErp/scaffold_folders.ps1) conventions already used for other Platform modules.
