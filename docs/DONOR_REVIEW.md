# Donor implementation review

Reviewed 2026-11-04. These repositories are implementation evidence only. Blizzard source plus the engineering knowledge base remain authoritative for API, security, combat, and ownership decisions. No donor code or assets were copied.

## Pins

- WeakAuras: `WeakAuras/WeakAuras2@2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93`
- Bartender4: `Nevcairiel/Bartender4@2ced21c0415ce50374ec6c38283a20a284616d25`
- LibActionButton-1.0: `Nevcairiel/LibActionButton-1.0@bc1da7a581d21dad5d7da114263c6a513f448f32`
- Dominos: `tullamods/Dominos@6653640fe9d5106d38175ef4914c553490445ec3`
- ElvUI: `tukui-org/ElvUI@a2512baafc0cddea42406060d73284ab7aa53887`
- LibCustomGlow: `Stanzilla/LibCustomGlow@4f8f5c2607d7384b26df9175bb99fa3df891b015`

## Transferable decisions

### Glow ownership and cleanup

WeakAuras assigns each external glow an owner-specific key and retains an exact hide function for terminal cleanup. LibCustomGlow likewise keys proc glows per owner and releases pooled frames through a resetter that hides, clears anchors/scripts, and removes the parent association.

Sudden Doom Glow already uses one addon-owned alert per observed frame, weak-key metadata, idempotent show/hide, stopped animations on hide, and explicit pending-hide ownership. The review supports those lifecycle choices. It does not justify moving proc state into a generic glow library.

### Current assignment, not stale frame identity

LibActionButton derives presentation from each button's current state/action and centralizes broad events. Dominos tracks each secure button's current `action` attribute and targets `ACTIONBAR_SLOT_CHANGED` to buttons currently owning the changed slot.

Sudden Doom Glow keeps current assignment resolution authoritative and does not cache a frame as permanently representing one action.

### Exact third-party button families

- Bartender4 creates `BT4Button1..180`; the existing named adapter is correct.
- ElvUI creates buttons as `ElvUI_Bar<bar>Button<slot>`; the existing adapter is correct.
- Dominos uses both `DominosActionButtonN` and compatibility names such as `MultiBarRightActionButtonN`, `MultiBarBottomLeftActionButtonN`, and `MultiBar5ActionButtonN`. Version 1.4.3 did not enumerate the latter families. Version 1.4.4 adds those exact current names so their alert surfaces can be prepared outside combat without requiring a global frame scan.

### Why LibCustomGlow is not embedded

LibCustomGlow has useful pooled, keyed visual lifecycles, but embedding it would add a process-wide LibStub dependency and another shared-library arbitration surface. The current product needs one fixed proc presentation and already owns a smaller lifecycle. The library is therefore retained as donor evidence, not added as a runtime dependency.

## Rejected transfers

- No donor aura/resource reconstruction is used for proc detection.
- No donor private registry is treated as a public inter-addon API.
- No global action-button manager or native glow is replaced.
- No recurring per-button polling or generic callback framework is introduced.
- No donor secure-bar framework is copied into this decoration addon.
