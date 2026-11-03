from pathlib import Path
import re
import sys


root = Path(sys.argv[1]).resolve()
toc = (root / "SuddenDoomGlow.toc").read_text(encoding="utf-8")


def metadata(name):
    match = re.search(rf"^## {re.escape(name)}:\s*(.*?)\s*$", toc, re.MULTILINE)
    assert match, f"TOC is missing ## {name}: metadata"
    return match.group(1)


interface = int(metadata("Interface"))
assert interface >= 120105, f"TOC interface {interface} is older than Retail 12.1.5"
version = metadata("Version")
assert re.fullmatch(r"\d+\.\d+\.\d+", version), f"invalid addon version: {version!r}"
assert metadata("OptionalDeps") == "Blizzard_CooldownViewer"

runtime_files = []
for line in toc.splitlines():
    line = line.strip()
    if not line or line.startswith("##") or line.startswith("#"):
        continue
    path = (root / line).resolve()
    assert path.parent == root and path.is_file(), f"TOC references missing/non-root runtime file: {line}"
    assert path.suffix.lower() == ".lua", f"unexpected runtime entry: {line}"
    runtime_files.append(path)

assert runtime_files, "TOC contains no runtime Lua files"
runtime_names = [path.name for path in runtime_files]
assert "Core.lua" in runtime_names, "Core.lua is not loaded by the TOC"
assert len(runtime_names) == len(set(runtime_names)), "TOC loads a runtime file more than once"
core_index = runtime_names.index("Core.lua")
assert all(name in runtime_names[core_index + 1 :] for name in ("Options.lua", "Debug.lua") if (root / name).exists()), (
    "Core.lua must load before addon UI/runtime extensions"
)

sources = {path.name: path.read_text(encoding="utf-8") for path in runtime_files}
all_runtime = "\n".join(sources.values())
core = sources["Core.lua"]

required_contracts = [
    "C_SpellActivationOverlay.IsSpellOverlayed",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "ActionButton.OnActionChanged",
    "ActionButtonSpellAlertTemplate",
    "NewWeakKeyTable",
    "OVERLAY_SHOW_GRACE",
    "EVENT_FALLBACK_TTL",
]
for token in required_contracts:
    assert token in all_runtime, f"missing required runtime contract: {token}"

for forbidden in [
    "C_UnitAuras",
    "UnitAura(",
    "GetSpellPowerCost",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "ActionButtonSpellAlertManager:",
]:
    assert forbidden not in all_runtime, f"forbidden legacy path remains in TOC-loaded runtime: {forbidden}"

assert "SetAttribute(" not in all_runtime, "runtime code must not mutate protected attributes"
assert not re.search(r"SetScript\(\s*[\"']OnUpdate", all_runtime), "polling OnUpdate introduced"
assert "WipeDB" not in all_runtime

# A secret value must be checked for accessibility before any nil/type/numeric
# comparison. This ordering is part of the client safety contract.
safe_number = re.search(r"local function SafeNumber\(value\)(.*?)\nend", core, re.DOTALL)
assert safe_number, "SafeNumber helper missing"
number_body = safe_number.group(1)
access_check = number_body.find("IsAccessible(value)")
nil_check = number_body.find("value == nil")
assert access_check >= 0 and (nil_check < 0 or access_check < nil_check), (
    "SafeNumber must check secret-value accessibility before comparing with nil"
)

print(f"static checks: PASS (interface={interface}, version={version}, runtime={', '.join(runtime_names)})")
