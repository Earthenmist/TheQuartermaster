# The Quartermaster — 2.0.7-Release

Changes since public release 2.0.6.

## Fixes

- Fixed a "C_Timer.After duration is too large" Lua error at login on characters with long-lived mail in their mailbox. Mail expiry reminders work as before.

## Known issues

- Existing transaction history is preserved, but older unclassified entries cannot be identified retrospectively without receipts.
