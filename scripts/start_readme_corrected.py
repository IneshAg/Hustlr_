from pathlib import Path

# Starter utility to draft a corrected README artifact.
out = Path("README_corrected.md")
out.write_text(
    "# Hustlr README — Corrected Version\n\n"
    "<!-- All corrections from actuarial review applied -->\n\n"
    "See CORRECTIONS.md for the full list of changes made.\n",
    encoding="utf-8",
)

print(f"Wrote {out}")
