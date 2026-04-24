"""
Train all local models into hustlr-ml/models/trained (consolidated location).
Run from anywhere: python hustlr-ml/scripts/train_all_local.py
"""

import subprocess
import sys
import os
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SCRIPTS = Path(__file__).resolve().parent

STEPS = [
    "train_model1_iss.py",
    "train_model3_fraud.py",
    "train_model4_nlp.py",
    "train_model5_blackout.py",
    "train_model6_traffic.py",
    "train_model7_prophet.py",
    "train_model8_gnn_fraud.py",
]


def main() -> int:
    env = os.environ.copy()
    services_path = str(Path(__file__).resolve().parent.parent / "services")
    existing_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = f"{services_path}{os.pathsep}{existing_pythonpath}" if existing_pythonpath else services_path

    for name in STEPS:
        path = SCRIPTS / name
        print(f"\n=== {name} ===\n")
        r = subprocess.run([sys.executable, str(path)], cwd=str(REPO), env=env)
        if r.returncode != 0:
            print(f"FAILED: {name} (exit {r.returncode})", file=sys.stderr)
            return r.returncode
    print("\nAll training steps finished.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
