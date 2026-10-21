# The Quartermaster — 2.0.6-Release

Changes since public release 2.0.5.

## Changes

- Played time now updates when you log in and when you open the window. It is never requested in combat, inside instances or during a Mythic+ key.

## Fixes

- Fixed "secret string value" Lua errors blamed on The Quartermaster during Mythic+ keys. Hiding the /played chat message no longer interferes with Blizzard's chat, and no longer adds System messages to chat tabs that did not show them.

## Known issues

- Existing transaction history is preserved, but older unclassified entries cannot be identified retrospectively without receipts.
