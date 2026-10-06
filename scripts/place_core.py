"""Install the core straight onto a Pocket SD card.

Build the bitstream in Quartus first, then pass the card's drive or mount point:

    python scripts/place_core.py E:

This packages the core with package_core.py, deletes the core's existing
Cores/<author>.<shortname>/ folder on the card so no stale files survive, and
extracts the zip onto the card. Eject the card safely before removing it.
"""

import argparse
import shutil
import sys
import zipfile
from pathlib import Path

from package_core import DEFAULT_RBF, ROOT, package


def place(zip_path: Path, card: Path) -> Path:
    """Extract zip_path onto card, replacing the core's folder. Return the
    core's folder on the card."""
    with zipfile.ZipFile(zip_path) as archive:
        core_dirs = {
            "/".join(name.split("/")[:2])
            for name in archive.namelist()
            if name.startswith("Cores/")
        }

        if len(core_dirs) != 1:
            raise ValueError(
                f"{zip_path.name} should hold 1 core folder, found {len(core_dirs)}"
            )

        core_dir = card / core_dirs.pop()

        if core_dir.exists():
            shutil.rmtree(core_dir)

        archive.extractall(card)

    return core_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "card", type=Path, help="SD card drive or mount point, such as E:"
    )
    parser.add_argument(
        "--rbf", type=Path, default=DEFAULT_RBF, help="Quartus .rbf to package"
    )
    args = parser.parse_args()

    # "E:" alone means the current folder on drive E, not its root
    card = Path(f"{args.card}/") if str(args.card).endswith(":") else args.card

    if not args.rbf.is_file():
        print(
            f"error: no bitstream at {args.rbf}. Compile the project in Quartus first.",
            file=sys.stderr,
        )
        return 1

    # The Pocket creates Cores/ when it sets up a card, so its absence means
    # this is probably the wrong drive.
    if not (card / "Cores").is_dir():
        print(
            f"error: {card} has no Cores folder. Is it a Pocket SD card?",
            file=sys.stderr,
        )
        return 1

    zip_path = package(args.rbf, ROOT / "output")
    core_dir = place(zip_path, card)
    print(f"placed {zip_path.name} on {card}, core in {core_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
