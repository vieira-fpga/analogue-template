"""Package the core into a zip that installs by extracting onto a Pocket SD card.

Build the bitstream in Quartus first, then run from anywhere:

    python scripts/package_core.py

The zip lands in output/, named <author>.<shortname>_<version>_<date_release>.zip
from core.json, with this layout:

    Cores/<author>.<shortname>/   core definition JSON, info.txt, icon.bin, bitstream
    Platforms/                    dist/platforms
    Assets/                       dist/assets

See https://www.analogue.co/developer/docs/packaging-a-core.
"""

import argparse
import json
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RBF = ROOT / "src" / "fpga" / "output_files" / "ap_core.rbf"

CORE_FILES = [
    "audio.json",
    "core.json",
    "data.json",
    "input.json",
    "interact.json",
    "variants.json",
    "video.json",
    "info.txt",
]

# Placeholder files that keep empty folders in git
PLACEHOLDERS = {".gitkeep", ".keep"}

_REVERSED_BYTES = bytes(int(f"{i:08b}"[::-1], 2) for i in range(256))


def reverse_bits(data: bytes) -> bytes:
    """Return data with the bit order of every byte reversed, turning a Quartus
    .rbf into the .rbf_r format the Pocket loads. The conversion is its own
    inverse."""
    return data.translate(_REVERSED_BYTES)


def package(rbf: Path, out_dir: Path) -> Path:
    """Write the release zip for the core and return its path."""
    metadata = json.loads((ROOT / "core.json").read_text())["core"]
    info = metadata["metadata"]
    cores = metadata["cores"]

    if len(cores) != 1:
        raise ValueError(
            f"core.json lists {len(cores)} bitstreams, only 1 is supported"
        )

    # The Pocket only loads a core whose folder matches author.shortname
    # exactly, spaces included.
    core_id = f"{info['author']}.{info['shortname']}"
    zip_path = out_dir / f"{core_id}_{info['version']}_{info['date_release']}.zip"

    # Stamp every entry with the release date so rebuilding the same release
    # gives the same zip.
    released = date.fromisoformat(info["date_release"])
    timestamp = (released.year, released.month, released.day, 0, 0, 0)

    entries: list[tuple[str, bytes]] = []

    for name in CORE_FILES:
        entries.append((f"Cores/{core_id}/{name}", (ROOT / name).read_bytes()))

    entries.append(
        (f"Cores/{core_id}/icon.bin", (ROOT / "dist" / "icon.bin").read_bytes())
    )
    entries.append(
        (f"Cores/{core_id}/{cores[0]['filename']}", reverse_bits(rbf.read_bytes()))
    )

    for folder, prefix in [("platforms", "Platforms"), ("assets", "Assets")]:
        base = ROOT / "dist" / folder

        for path in sorted(base.rglob("*")):
            if path.is_file() and path.name not in PLACEHOLDERS:
                entries.append(
                    (f"{prefix}/{path.relative_to(base).as_posix()}", path.read_bytes())
                )

    out_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries:
            archive.writestr(
                zipfile.ZipInfo(name, timestamp),
                data,
                compress_type=zipfile.ZIP_DEFLATED,
            )

    return zip_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--rbf", type=Path, default=DEFAULT_RBF, help="Quartus .rbf to package"
    )
    parser.add_argument(
        "--out", type=Path, default=ROOT / "output", help="folder for the zip"
    )
    args = parser.parse_args()

    if not args.rbf.is_file():
        print(
            f"error: no bitstream at {args.rbf}. Compile the project in Quartus first.",
            file=sys.stderr,
        )
        return 1

    print(package(args.rbf, args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
