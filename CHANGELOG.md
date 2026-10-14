# The Quartermaster — 2.0.3-Release

Changes since public release 2.0.2.

## Changes

- Centralized item metadata access through the current-client compatibility layer across Equipment, storage, materials, recipes, watchlists, search, tooltips and related scanners.

## Fixes

- Fixed Equipment stopping partway through its first character row when item quality metadata was still loading.
- Added safe fallback handling when a Retail item metadata API is temporarily unavailable, preventing the same compatibility failure in adjacent item views.

## Known issues

- Existing transaction history is preserved, but older unclassified entries cannot be identified retrospectively without receipts.
