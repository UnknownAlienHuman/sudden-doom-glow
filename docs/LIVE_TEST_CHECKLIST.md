# Live client checklist

For Sudden Doom Glow `1.4.7`, Retail 12.1.5, expected interface `120105`; current source recheck is build `70783`.

- [ ] Record `/sdglow status`, exact commit/package, client build/Interface, date, character/spec, bar implementation, Cooldown Viewer layout, and addon stack.
- [ ] Test one/two stacks, consumption, expiry, and immediate reacquisition.
- [ ] Capture ordinary and opaque overlay payloads plus immediate/next-frame/post-grace query results; verify decisive immediate reads suppress duplicate delayed queries while complete readable all-false remains required for OFF.
- [ ] Change one action slot and verify one query per unique slot and no unrelated button work; verify explicit slot `0` is broad while denied/malformed payloads do nothing, then exercise pages, modifiers, vehicle/override states during combat.
- [ ] Exercise all four Cooldown Viewer surfaces through data-ready, acquire, reset, reuse, reorder, Edit Mode, spec/talent, and hotfix paths.
- [ ] Confirm mapping invalidation does not visibly clear/restart a valid proc.
- [ ] Confirm pending hide, active-alert/animation revalidation, render-target size-hook, frame-level read/write, and geometry-generation recovery when access returns, including a scale change while the button is inaccessible or the addon is disabled.
- [ ] Replace a render target and confirm its old size hook becomes inert; resize the current target and confirm geometry completes without a persistent dirty owner.
- [ ] Observe `loadedOrLoading=true, loaded=false`, then completed load for Bartender4, Dominos, ElvUI, and Cooldown Viewer; confirm discovery begins only after the exact second result is true.
- [ ] Confirm inaccessible/throwing foreign member reads, incomplete item lifecycle hooks, failed viewer hooks, and an inaccessible assigned icon fail closed without retry loops, parent fallback, false hook success, stale presentation, or escaped Lua errors.
- [ ] Simulate timer-construction failure and confirm delayed proc evidence, test glow, action refresh, and rescan ownership all reach one terminal state.
- [ ] Confirm replacement-family growth stays within 128 resolved IDs and configured signal aliases remain present.
- [ ] Confirm target/signal list limits and Settings/slash synchronization.
- [ ] Check open world, encounter, Mythic+, arena, and battleground contexts where available.
- [ ] Record zero repeating Lua, taint, forbidden-object, or restricted-value errors.
- [ ] Measure CPU/allocation in one fixed repeatable scene.

Append evidence to `VALIDATION.md`. Source inspection and host stubs are not live-client passes.
