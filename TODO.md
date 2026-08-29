# Sudden Doom Glow — live validation

The static/runtime harness is complete. The remaining items require a current Retail client and must not be marked complete from source inspection alone.

## Required 12.1 combat matrix

- [ ] Record build/interface and `/sdglow status` before testing.
- [ ] Verify one-stack Sudden Doom: immediate ON, full proc duration, immediate OFF after consumption/expiry.
- [ ] Verify two stacks: first Death Coil/Epidemic consumption must not clear the remaining proc.
- [ ] Verify simultaneous/rapid overlay SHOW/HIDE ordering does not flicker or stick.
- [ ] Verify current live payload IDs with debug enabled; add a signal ID only if the official query family cannot resolve it.
- [ ] Verify Death Coil -> Necrotic Coil and Epidemic -> current Graveyard replacement paths after talent changes.
- [ ] Verify Cooldown Viewer Essential, Utility, Tracked Buff Icon, and Buff Bar layouts during combat.
- [ ] Verify viewer reorder, edit-mode resize, spec/talent swap, zoning, and pool reuse.
- [ ] Verify Blizzard bars, ElvUI, Bartender4, Dominos, and the user's active UI stack.
- [ ] Verify combat page/state-driver transitions never glow an empty or unrelated button.
- [ ] Verify no blocked action, forbidden-object, taint, or secret-value errors with only this addon enabled and with the full addon stack.
- [ ] Profile event bursts and talent/page changes; confirm no visible hitch and no frame growth after repeated reload/rescan cycles.

## Evidence to capture

```text
build=
interface=
context=outside|combat|encounter|mythicplus|arena|battleground
payloadSpellID=
resolvedTargets=
resolvedSignals=
detection=
buttons=
cdm=
result=pass|fail
error=
```

When a failure is reproduced, preserve the exact build/context and `/sdglow status` output before changing defaults.
