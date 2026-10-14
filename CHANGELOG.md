# The Quartermaster — 2.0.2-Release

Changes since public release 2.0.1.

## Changes

- Wealth retains confirmed auction and crafting-order receipts when other gold changes happen in the same batch. Only the unmatched remainder is unclassified.
- Today’s gold graph shows bounded minute snapshots; longer periods retain daily history. Graph points include collection times.
- Added an income/spending graph and filters for deposits, transfers and unclassified changes.

## Fixes

- Fixed a bag-update error when checking newly obtained mounts, pets and toys on current Retail clients.
- Fixed a profession reagent-pin error after opening or reopening the Crafting Orders interface.

## Known issues

- Existing transaction history is preserved, but older unclassified entries cannot be identified retrospectively without receipts.
