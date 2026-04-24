# README Writing Approach

This guide describes a safe, repeatable way to write or rewrite README content without losing actuarial correctness.

## Goals
- Keep one canonical source of truth in [README.md](../README.md).
- Avoid full-file rewrites when only targeted sections changed.
- Preserve finalized product rules (3 tiers, hard caps, Full-only trigger gates).

## Preferred Workflow
1. Identify exact stale sections via targeted search.
2. Patch only those sections.
3. Re-scan for known stale keywords.
4. Record changes in [CORRECTIONS.md](../CORRECTIONS.md).

## Canonical Guardrails
- Tier pricing: ₹35 / ₹49 / ₹79 weekly.
- Standard description: 3 base + 2 optional add-ons.
- Basic: automated-only, no manual claims, no add-ons.
- Full-only hard gates: Cyclone, Extreme Rain, Heavy Traffic.
- Standard-only add-ons: Bandh/Curfew (+₹15), Internet (+₹12).
- Add-ons are quarterly with cooling-off and lock-in constraints.

## Starter Script (Bash)
Use when drafting a fresh corrected README artifact before merging into [README.md](../README.md).

```bash
python3 << 'PYEOF'
from pathlib import Path

out = Path('README_corrected.md')
out.write_text(
    '# Hustlr README — Corrected Version\n\n'
    '<!-- All corrections from actuarial review applied -->\n\n'
    'See CORRECTIONS.md for the full list of changes made.\n',
    encoding='utf-8'
)
print(f'Wrote {out}')
PYEOF
```

## Starter Script (PowerShell, Windows)
Use this in Windows terminals where bash heredocs are unavailable.

```powershell
@'
from pathlib import Path

out = Path("README_corrected.md")
out.write_text(
    "# Hustlr README — Corrected Version\n\n"
    "<!-- All corrections from actuarial review applied -->\n\n"
    "See CORRECTIONS.md for the full list of changes made.\n",
    encoding="utf-8"
)
print(f"Wrote {out}")
'@ | python -
```

## Review Checklist Before Commit
- Trigger tables do not show the legacy Standard Shield label for Extreme Rain/Cyclone.
- No stale add-ons: legacy add-ons such as Cyclone, Accident Blockspot, and Heavy Traffic as purchasable entries.
- Business model numbers match latest COGS and margin assumptions.
- Plan-tier and manual-claim access rules are consistent in every section.
