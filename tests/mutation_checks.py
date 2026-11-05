from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
lua = sys.argv[2] if len(sys.argv) > 2 else "lua5.1"
core_path = root / "Core.lua"
regression_path = root / "tests" / "runtime_regression.lua"
core = core_path.read_text(encoding="utf-8")

mutations = {
    "loading-is-not-loaded": (
        'return ok and IsAccessible(loaded) and type(loaded) == "boolean" and loaded == true',
        'return ok and ((IsAccessible(loaded) and type(loaded) == "boolean" and loaded == true) '
        'or (IsAccessible(_loadedOrLoading) and _loadedOrLoading == true))',
    ),
    "inaccessible-icon-parent-fallback": (
        "if not FrameCanBeUsed(iconFrame) then return nil end",
        "if not FrameCanBeUsed(iconFrame) then return frame end",
    ),
    "retain-stale-assignments": (
        "    InvalidateObservedAssignments()\n    RebuildSpellFamilies()",
        "    RebuildSpellFamilies()",
    ),
    "drop-required-rescan-on-timer-failure": (
        '    CompleteRescanRequest(self, reason)\n    return true, "completed"',
        "    R.rescanDeep = false\n    R.rescanReason = nil\n    return false",
    ),
    "authorize-partial-cdm-hook": (
        "            if not ok then\n                SuspendCDMFrame(frame)\n"
        "                return false\n            end\n            hooked[name] = true",
        "            if not ok then return true end\n            hooked[name] = true",
    ),
    "unguarded-chat-member-read": (
        '    local chatFrame, frameKnown = ReadMember(_G, "DEFAULT_CHAT_FRAME")\n'
        "    if not frameKnown or not FrameCanBeUsed(chatFrame) then return end\n"
        '    local addMessage, methodKnown = ReadMember(chatFrame, "AddMessage")\n'
        '    if methodKnown and type(addMessage) == "function" then\n'
        '        pcall(addMessage, chatFrame, "|cff66ccffSuddenDoomGlow|r: " .. text)\n'
        "    end",
        "    local chatFrame = _G.DEFAULT_CHAT_FRAME\n"
        "    if chatFrame and chatFrame.AddMessage then chatFrame:AddMessage(text) end",
    ),
}

with tempfile.TemporaryDirectory(prefix="sdg-mutations-") as temp_dir:
    temp = Path(temp_dir)
    for name, (old, new) in mutations.items():
        count = core.count(old)
        if count != 1:
            raise AssertionError(f"{name}: expected one mutation anchor, found {count}")
        mutated_path = temp / f"Core-{name}.lua"
        mutated_path.write_text(core.replace(old, new, 1), encoding="utf-8")
        result = subprocess.run(
            [lua, str(regression_path), str(mutated_path)],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            raise AssertionError(f"{name}: regression suite did not detect the mutation")
        print(f"mutation detected: {name}")

print(f"mutation checks: PASS ({len(mutations)} mutations)")
