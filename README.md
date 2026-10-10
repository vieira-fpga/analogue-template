<div align="center">
    <p>
        <a href="https://github.com/vieira-fpga" target="_blank">
            <picture>
                <source media="(prefers-color-scheme: dark)" srcset="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/logo-dark.svg" />
                <source media="(prefers-color-scheme: light)" srcset="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/logo-light.svg" />
                <img height="100" src="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/logo-light.svg" alt="Vieira FPGA" />
            </picture>
        </a>
        <br /> <br />
        <a href="https://x.com/morganvieira" target="_blank">
            <picture>
                <source media="(prefers-color-scheme: dark)" srcset="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/icons/twitter-dark.svg" />
                <source media="(prefers-color-scheme: light)" srcset="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/icons/twitter-light.svg" />
                <img width="24" src="https://github.com/vieira-fpga/.github/raw/HEAD/.github/assets/icons/twitter-light.svg" alt="X" />
            </picture>
        </a>
    </p>
</div>

___

# analogue-template
The starting point for every Vieira FPGA core on the Analogue Pocket | By [Vieira FPGA](https://github.com/vieira-fpga)

___

## Introduction
This template began as Analogue's core template and has since gone its own way. The user core in `src/fpga/core` is SystemVerilog, and Python scripts package the core and install it on an SD card. Out of the box it draws a gray 320x240 screen, plays silence, and answers the Pocket's bridge commands.

## Starting a new core
Create a repository from this template, then make the core your own:

1. In `core.json`, set `shortname`, `description`, `url`, `version` and `date_release`. The Pocket installs the core to `Cores/<author>.<shortname>/`.
2. Rename `dist/platforms/template.json` and `dist/platforms/_images/template.bin` to your platform's ID, and put the same ID in `platform_ids` in `core.json`.
3. Rewrite `info.txt`, which the Pocket shows in the core's info screen.
4. Replace the gray screen in `src/fpga/core/core_top.sv` with your core.

## Packaging
Compile `src/fpga/ap_core.qpf` in Quartus, then run:

```sh
python scripts/package_core.py
```

This writes `output/<author>.<shortname>_<version>_<date_release>.zip`, using the values in `core.json`. Extract the zip onto the root of the Pocket's SD card to install the core, or package and install in one step with the card's drive:

```sh
python scripts/place_core.py E:
```

This replaces the core's folder on the card, so files from an older build don't linger. Build outputs are not committed, so a fresh clone has no bitstream until you compile.

## Legal
Analogue's Development program was created to further video game hardware preservation with FPGA technology. Analogue Developers have access to Analogue Pocket I/O's so Developers can utilize cartridge adapters or interface with other pieces of original or bespoke hardware to support legacy media. Analogue does not support or endorse the unauthorized use or distribution of material protected by copyright or other intellectual property rights.

## Credits
- Morgan Vieira - [GitHub](https://github.com/morgan-vieira) | [X](https://x.com/morganvieira)
- Analogue (original core template and the APF framework in `src/fpga/apf`) - [Developer docs](https://www.analogue.co/developer)
