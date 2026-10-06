// Savestate handshake between core_bridge_cmd and the core, synchronous to
// clk_74a. start or load rises when the host asks the core to save or load,
// and stays high until the core sets ack in the matching status.

`default_nettype none

interface savestate_if;

  import core_pkg::*;

  // Set by the core
  logic                     supported;
  logic              [31:0] addr;  // bridge address of the savestate buffer
  logic              [31:0] size;
  logic              [31:0] maxloadsize;
  savestate_status_t        start_status;
  savestate_status_t        load_status;

  // Set by core_bridge_cmd
  logic                     start = 1'b0;
  logic                     load = 1'b0;

  modport bridge(
      input supported, addr, size, maxloadsize, start_status, load_status,
      output start, load
  );

  modport core(
      output supported, addr, size, maxloadsize, start_status, load_status,
      input start, load
  );

endinterface
