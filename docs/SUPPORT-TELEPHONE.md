# Optional support notifications

This is an optional maintainer procedure for receiving a notification when a
user contacts support. It is not part of the app, and it should not expose a
private network service to the internet.

## 1. Dedicated support mailbox

- Use a dedicated mailbox or alias managed by the project, not a maintainer's
  personal address.
- Enable multi-factor authentication and create a mailbox-specific app
  password for the notification service.
- Configure `AppLinks.supportEmail` only after the project mailbox is ready.
- Keep mailbox credentials in the automation platform's secret store.

## 2. Optional notification channel

A self-hosted automation service such as n8n can poll the mailbox over IMAP
with TLS and send a short notification through a messaging provider. Keep the
automation service on a private network and use outbound connections only.

- Do not expose an inbound webhook or management port to the public internet.
- Store bot tokens, chat identifiers, and API credentials in the platform's
  secret store, never in workflow exports or this repository.
- Send only the subject and sender address in the notification; read the
  message in the dedicated mailbox.
- Do not forward diagnostic reports or message bodies to third-party channels.

## 3. Safe operation

- Test using fabricated messages and accounts.
- Review the app's support report before sharing it; it is optional.
- Delete support messages according to the published privacy policy.
- Export workflow definitions only after removing credentials and private
  deployment details.
