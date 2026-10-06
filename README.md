# Core Template
This is a template repository for a core which contains all of the core definition JSON files and FPGA starter code.

## Packaging
Compile `src/fpga/ap_core.qpf` in Quartus, then run:

```sh
python scripts/package_core.py
```

This writes `output/<author>.<shortname>_<version>_<date_release>.zip`, using the values in `core.json`. Extract the zip onto the root of the Pocket's SD card to install the core. Build outputs are not committed, so a fresh clone has no bitstream until you compile.

## Legal
Analogue’s Development program was created to further video game hardware preservation with FPGA technology. Analogue Developers have access to Analogue Pocket I/O’s so Developers can utilize cartridge adapters or interface with other pieces of original or bespoke hardware to support legacy media. Analogue does not support or endorse the unauthorized use or distribution of material protected by copyright or other intellectual property rights.
