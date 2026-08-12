# Architecture

`Core.lua` contains the addon’s state and event loop, arranged into local functional areas named Buttons, Aura, Signals, Render, and Events in the existing documentation. It stores configuration and diagnostics in `SuddenDoomGlowDB`, maps target spells to action buttons, derives proc state from aura/secondary signal paths, and updates local button or cooldown-viewer presentation. `Debug.lua` provides a debug frame and controls over stored debug/aura/overlay settings.

The TOC loads `Core.lua` before `Debug.lua`. The optional Cooldown Manager relationship is declared in the TOC; the repository's current rendering path is addon-local rather than a manager-call dependency.
