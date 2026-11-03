# TODO

Release `1.4.1` targets Retail 12.1.5, expected interface `120105`. The selected source pin is build `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`, checked 2026-11-03. Client validation is **NOT-RUN**.

## Before calling the current patch live-validated

- [ ] Capture the Retail client build and interface from `/sdglow status` and record the test date.
- [ ] Verify one- and two-stack Sudden Doom behavior, consumption, and natural expiry.
- [ ] Capture live overlay payload IDs and confirm the configured target/signal family handles current replacements.
- [ ] Exercise action paging and state-driver changes; confirm stale or unreadable assignments do not receive a new glow.
- [ ] Exercise Essential, Utility, Tracked Buff Icon, and Buff Bar Cooldown Viewer items, including assignment, reset, pool reuse, reorder, and spec/talent changes.
- [ ] Check combat and restricted contexts, taint/forbidden-object errors, and the installed addon stack.
- [ ] Append results and failures to [VALIDATION.md](VALIDATION.md) without overwriting earlier evidence.

## Evidence maintenance

- [ ] Recheck the selected source pin after a Retail UI source update and update [API_CONTRACTS.md](docs/API_CONTRACTS.md) only from reviewed generated docs/source.
- [ ] Keep source-contract evidence separate from client results; do not mark a live check complete from source inspection or the stub harness.
