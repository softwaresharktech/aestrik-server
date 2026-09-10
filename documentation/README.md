# Asterisk × LamaERP Documentation

Plan for standing up [Asterisk](https://www.asterisk.org/) (with [FreePBX](https://www.asterisk.org/asteriskexchange/freepbx/) as the admin UI) on a new server in DataHub, and connecting it to the [LamaERP](../../FinalLamaErp) application via its call-control APIs. Read in order:

1. [00-overview.md](00-overview.md) — what Asterisk/FreePBX are, why LamaERP needs voice, architecture at a glance
2. [01-server-provisioning.md](01-server-provisioning.md) — sizing, network, firewall for the new DataHub server
3. [02-asterisk-freepbx-installation.md](02-asterisk-freepbx-installation.md) — installing Asterisk + FreePBX, enabling AMI/ARI
4. [03-freepbx-configuration.md](03-freepbx-configuration.md) — trunks, extensions, IVR, multi-tenant mapping
5. [04-asterisk-apis-ami-ari.md](04-asterisk-apis-ami-ari.md) — AMI vs ARI, auth, example call flows
6. [05-erp-integration.md](05-erp-integration.md) — the proposed `LamaERP.Platform.Telephony` module
7. [06-security-hardening.md](06-security-hardening.md) — toll-fraud prevention, secrets, network isolation, recording compliance
8. [07-rollout-checklist.md](07-rollout-checklist.md) — phased go-live plan
9. [08-open-source-vs-paid-comparison.md](08-open-source-vs-paid-comparison.md) — open-source core vs paid FreePBX modules vs CPaaS (Twilio/Vonage/Plivo) vs hosted PBX, with Nepal-specific cost numbers
10. [09-datahub-production-deployment.md](09-datahub-production-deployment.md) — the separate DataHub DB service, the bootstrap script, and the GitHub Actions CI/CD that actually ships this to production
11. [10-yetiappcloud-install-log.md](10-yetiappcloud-install-log.md) — **as-built log** of the real install on YetiApp Cloud: every wrong turn, the fix for each, and Jelastic-specific gotchas. Updated as the install progresses.
12. [11-deferred-steps.md](11-deferred-steps.md) — **TODO / deferred steps**: everything skipped, stubbed, or temporarily loosened during the install, grouped by area with checkboxes.
13. [12-linphone-extension-setup.md](12-linphone-extension-setup.md) — connecting a roaming softphone (Linphone) to an extension: fail2ban, TLS/SRTP transport, Jelastic firewall rules, client config, testing

**Status**: install in progress on YetiApp Cloud — Asterisk + FreePBX are installed and running; the admin UI is not yet reachable from outside. See [10-yetiappcloud-install-log.md](10-yetiappcloud-install-log.md) for the live state and remaining steps.

**Want to click through the real thing first?** [../local-dev](../local-dev) runs an actual FreePBX + Asterisk install locally in Docker — the genuine admin GUI at `http://localhost/admin`, not a mockup. See [../local-dev/README.md](../local-dev/README.md).
