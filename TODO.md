# TODO

Release `1.4.2` targets Retail 12.1.5, expected interface `120105`. Current live source was checked at build `70783`; relevant addon source slices are unchanged from the KB-selected `70688` baseline. Client validation remains **NOT-RUN**.

## Required live matrix

- [ ] Capture `/sdglow status`, client build, Interface, addon commit/package, date, and addon stack.
- [ ] Verify one- and two-stack Sudden Doom activation, consumption, natural expiry, and rapid reacquisition.
- [ ] Record actual overlay payload spell IDs and immediate/next-frame/post-grace query results.
- [ ] Exercise stock paging and the active third-party bar through slot `A → B → empty → A` in combat.
- [ ] Exercise Essential, Utility, Buff Icon, and Buff Bar viewers: acquire, reset, reuse, reorder, Edit Mode, spec/talent change, and table hotfix/recovery.
- [ ] Verify animation and hide recovery across combat/restriction transitions with zero taint, forbidden-object, or repeating Lua errors.
- [ ] Measure CPU/allocation in a fixed scene before claiming a performance improvement.
- [ ] Append results to `VALIDATION.md`; never replace failed or superseded evidence.

## Source maintenance

- [ ] Recheck the exact source slice after the next live UI-source update.
- [ ] Keep source evidence separate from named-client PASS/FAIL.
