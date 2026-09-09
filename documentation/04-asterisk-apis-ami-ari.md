# Asterisk APIs: AMI vs ARI

Two different APIs, both useful, for different jobs. AMI and ARI credentials from [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md) are what's used here.

## AMI — Asterisk Manager Interface

A plain-text, line-based protocol over a persistent TCP socket (port 5038). Good for **management and monitoring**: originating calls, watching channel/queue/hangup events, reading status. It cannot steer an in-progress call's media/flow — no "play this prompt now, then wait for a DTMF digit" logic. ([vicistack.com](https://vicistack.com/blog/asterisk-manager-interface-guide/))

**Auth**: login action with the username/secret from `manager.conf`.

```
Action: Login
Username: lamaerp
Secret: <secret>

Action: Originate
Channel: PJSIP/<staff_extension>
Context: from-internal
Exten: <parent_phone_number>
Priority: 1
CallerID: "<Tenant Name>" <tenant-caller-id>
Timeout: 30000
Async: true
```

This is exactly the **click-to-call** flow: staff extension rings first, and once the staff member answers, Asterisk continues the dialplan to dial the parent's number and bridge the two legs.

AMI also streams events (`Newchannel`, `Hangup`, `BridgeEnter`, `QueueCallerJoin`, etc.) over the same socket once logged in — this is how the ERP backend finds out a call ended, its duration, and its hangup cause, to write a `CallLog` row (see [05-erp-integration.md](05-erp-integration.md)).

## ARI — Asterisk REST Interface

A REST API (HTTPS) plus a WebSocket event stream, giving an external application **full control of a channel's media and flow** in real time — Asterisk becomes application-driven instead of dialplan-driven for whatever's routed into your Stasis app. ([docs.asterisk.org](https://docs.asterisk.org/Configuration/Interfaces/Asterisk-REST-Interface-ARI/))

This is the right tool for anything with branching logic mid-call — most notably, **automated voice campaigns with DTMF capture** (e.g. "Your fee of Rs. X is due. Press 1 if already paid, press 2 to speak to someone.").

**Auth**: HTTP Basic Auth using the ARI user/password from `ari.conf`, always over TLS in production.

```bash
# Originate a call into a Stasis application
curl -u lamaerp:<secret> -X POST \
  "https://pbx.internal.<datahub-domain>:8089/ari/channels" \
  -d "endpoint=PJSIP/<trunk-or-context>/<parent_phone_number>" \
  -d "app=lamaerp-ivr" \
  -d "callerId=<Tenant Name> <tenant-caller-id>"
```

The app (`lamaerp-ivr`) is whatever's listening on the ARI WebSocket for `StasisStart` events on that channel, then drives it: `POST /channels/{id}/play` to play a prompt (recorded or TTS-generated), `POST /channels/{id}/answer`, listen for `ChannelDtmfReceived` on the WebSocket, then decide what to play/do next, and finally `DELETE /channels/{id}` to hang up.

WebSocket connection for events:

```
wss://pbx.internal.<datahub-domain>:8089/ari/events?api_key=lamaerp:<secret>&app=lamaerp-ivr
```

## Which one for which LamaERP use case

| Use case | API | Why |
|---|---|---|
| Click-to-call (staff → parent) | AMI `Originate` | No mid-call branching needed — just connect two legs. |
| Call ended / duration / hangup cause → `CallLog` | AMI events (or ARI `StasisEnd`/`ChannelDestroyed` if already in an ARI app) | Either works; AMI is simpler if the call wasn't otherwise using ARI. |
| Automated fee-reminder / attendance-alert IVR campaign, with DTMF response capture | ARI | Needs to play a prompt, wait for a keypress, and branch. |
| Inbound queue/IVR built inside FreePBX (menus, ring groups) | Neither — configured once in FreePBX (see [03](03-freepbx-configuration.md)) | Static routing doesn't need runtime API control. |
| Screen-pop ("this parent is calling") | AMI events or ARI WebSocket, whichever the app is already consuming | Just needs the caller-ID + which extension/queue the call landed on. |

## .NET client considerations

There's no official Asterisk .NET SDK. Two viable approaches for the new `LamaERP.Platform.Telephony` module (see [05-erp-integration.md](05-erp-integration.md)):

1. **Hand-roll thin clients.** AMI's protocol is simple newline-delimited text over `System.Net.Sockets.TcpClient` — not much code to own. ARI is `HttpClient` for the REST calls plus `System.Net.WebSockets.ClientWebSocket` for the event stream. This keeps the dependency footprint at zero and matches the codebase's general preference for owning small integrations directly.
2. **AsterNET** (open-source, MIT-licensed .NET library with both an AMI client and an ARI client) if hand-rolling turns out to be more code than it's worth once the real requirements (reconnect/backoff behavior, ARI model classes, etc.) are known. Evaluate this once the Telephony module's actual surface area is clearer — don't pull it in speculatively.

Either way, the Infrastructure layer of the Telephony module is the only place that should know these protocol details, exactly the same boundary the Notifications module keeps around its channel senders.

## Next step

[05-erp-integration.md](05-erp-integration.md) — how this plugs into the ERP's existing Clean Architecture module structure.
