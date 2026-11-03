# Live client checklist

For release `1.4.0` targeting Retail 12.1.5 (expected interface `120105`). The selected source pin is build `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`, checked 2026-11-02; client status is **NOT-RUN**.

Record the actual client build/interface and addon status before testing. The expected TOC interface does not establish runtime compatibility. Append results to [VALIDATION.md](../VALIDATION.md).

- [ ] Test one and two Sudden Doom stacks, spell consumption, and natural expiry.
- [ ] Record overlay event payload IDs and confirm spell family resolution across current replacements.
- [ ] Change action page/state-driver assignments; verify stale and unreadable assignments do not glow.
- [ ] Test the four configured Cooldown Viewer types: Essential, Utility, Buff Icon, and Buff Bar.
- [ ] Exercise Cooldown Viewer reorder, edit mode, item assignment/reset, pool reuse, and spec/talent changes.
- [ ] Repeat in open world, encounter, Mythic+, arena, and battleground contexts where available.
- [ ] Check the Blizzard bars and the user's active third-party action bar.
- [ ] Check Lua, taint, forbidden-object, and restricted-value errors with the addon alone and in the user's addon stack.

Source inspection and the stubbed harness are not live-client passes. Current live status is **NOT-RUN**.
