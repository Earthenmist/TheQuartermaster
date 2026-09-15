# The Quartermaster — 2.0.1-Release

Changes since public release 2.0.0.

## Changes
- Quest logs and achievements now collect only when you click Refresh current character on their pages. Existing records are preserved.

## Fixes
- Disabled automatic quest-log and achievement scans that could cause frame stutter and increased temporary memory use during normal play.
- Reduced manual collection batches and cancel pending collection when entering combat or loading another area.

## Known issues
- Quest and achievement records remain at their last collection state until manually refreshed. Manual collection can still take time; individual game API calls cannot be interrupted.
