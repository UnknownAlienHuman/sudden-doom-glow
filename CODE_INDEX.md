# Code index

| File | Responsibility |
| --- | --- |
| `Core.lua` | persistent settings, spell/button mapping, proc signals, render state, event dispatch, `/sdglow` |
| `Debug.lua` | debug window, log controls, aura/overlay checkboxes, rescan/test controls |

Primary anchors: `OnEvent`, the event-registration block, `SlashCmdList["SUDDEN_DOOM_GLOW"]`, local button overlay creation, and debug-frame construction.
