# Live client checklist

For Sudden Doom Glow `1.4.4`, Retail 12.1.5, expected interface `120105`; current source recheck is build `70783`.

- [ ] Record `/sdglow status`, exact commit/package, client build/Interface, date, character/spec, bar implementation, Cooldown Viewer layout, and addon stack.
- [ ] Test one/two stacks, consumption, expiry, and immediate reacquisition.
- [ ] Capture overlay payload IDs and immediate/next-frame/post-grace query results.
- [ ] Change assignments, pages, modifiers, vehicle/override states during combat; verify only current assignments glow.
- [ ] Exercise all four Cooldown Viewer surfaces through data-ready, acquire, reset, reuse, reorder, Edit Mode, spec/talent, and hotfix paths.
- [ ] Confirm mapping invalidation does not visibly clear/restart a valid proc.
- [ ] Confirm pending hide, animation, and geometry recovery when access returns, including while disabled.
- [ ] Confirm target/signal list limits and Settings/slash synchronization.
- [ ] Check open world, encounter, Mythic+, arena, and battleground contexts where available.
- [ ] Record zero repeating Lua, taint, forbidden-object, or restricted-value errors.
- [ ] Measure CPU/allocation in one fixed repeatable scene.

Append evidence to `VALIDATION.md`. Source inspection and host stubs are not live-client passes.
