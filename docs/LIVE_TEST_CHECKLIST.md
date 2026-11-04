# Live client checklist

For Sudden Doom Glow `1.4.2`, Retail 12.1.5, expected interface `120105`. Current source recheck is build `70783`; runtime status remains **NOT-RUN**.

- [ ] Record `/sdglow status`, exact addon commit/package, client build/Interface, date, character/spec, and addon stack.
- [ ] Test one and two stacks, consumption, expiry, and immediate reacquisition.
- [ ] Capture overlay payload IDs and immediate/next-frame/post-grace query results.
- [ ] Change action pages, modifiers, vehicle/override states, and assignments during combat; verify current assignments only.
- [ ] Load unrelated addons and supported bar addons; confirm only supported integrations trigger mapping recovery.
- [ ] Exercise all four Cooldown Viewer surfaces through data-ready/acquire/reset/reuse/reorder/Edit Mode/spec/talent/table-hotfix paths.
- [ ] Confirm CDM table hotfix and talent/spell invalidations do not visibly clear/restart an active proc or retain stale overrides.
- [ ] Confirm delayed alert hide and missed animation start recover after access returns, including while disabled.
- [ ] Check open world, encounter, Mythic+, arena, and battleground contexts where available.
- [ ] Check Lua, taint, forbidden-object, and restricted-value errors with the addon alone and in the normal stack.
- [ ] Measure CPU/allocation in one fixed repeatable scene.

Append evidence to `VALIDATION.md`. Source inspection and stub tests are not live-client passes.
