// Data slot requests from the host, passed on by core_bridge_cmd. Synchronous
// to clk_74a.

`default_nettype none

interface dataslot_if;

  // Host asks to read a slot. Hold ack, with ok set if the slot can be read.
  logic        requestread = 1'b0;
  logic [15:0] requestread_id;
  logic        requestread_ack;
  logic        requestread_ok;

  // Host asks to write a slot. Hold ack, with ok set if the slot can be written.
  logic        requestwrite = 1'b0;
  logic [15:0] requestwrite_id;
  logic [31:0] requestwrite_size;
  logic        requestwrite_ack;
  logic        requestwrite_ok;

  // Host changed a deferload slot. Detect the rising edge.
  logic        update = 1'b0;
  logic [15:0] update_id;
  logic [31:0] update_size;

  // Host finished loading all slots
  logic        allcomplete = 1'b0;

  modport bridge(
      output requestread, requestread_id,
      input requestread_ack, requestread_ok,
      output requestwrite, requestwrite_id, requestwrite_size,
      input requestwrite_ack, requestwrite_ok,
      output update, update_id, update_size,
      output allcomplete
  );

  modport core(
      input requestread, requestread_id,
      output requestread_ack, requestread_ok,
      input requestwrite, requestwrite_id, requestwrite_size,
      output requestwrite_ack, requestwrite_ok,
      input update, update_id, update_size,
      input allcomplete
  );

endinterface
