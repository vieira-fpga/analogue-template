// Data slot commands from the core to the host, sent by core_bridge_cmd and
// synchronous to clk_74a. Set the parameters, then raise read, write, getfile,
// or openfile. ack holds while the host runs the command. done then holds,
// with the result in err, until the next command starts.

`default_nettype none

interface target_dataslot_if;

  // Set by the core
  logic        read;
  logic        write;
  logic        getfile;  // needs buffer_resp_struct mapped on the bridge
  logic        openfile;  // needs buffer_param_struct mapped on the bridge
  logic [15:0] id;
  logic [31:0] slotoffset;
  logic [31:0] bridgeaddr;
  logic [31:0] length;
  logic [31:0] buffer_param_struct;  // bridge address the host reads parameters from
  logic [31:0] buffer_resp_struct;  // bridge address the host writes its response to

  // Set by core_bridge_cmd
  logic        ack = 1'b0;
  logic        done = 1'b0;
  logic [ 2:0] err = '0;  // zero is OK

  modport bridge(
      input read, write, getfile, openfile,
      input id, slotoffset, bridgeaddr, length,
      input buffer_param_struct, buffer_resp_struct,
      output ack, done, err
  );

  modport core(
      output read, write, getfile, openfile,
      output id, slotoffset, bridgeaddr, length,
      output buffer_param_struct, buffer_resp_struct,
      input ack, done, err
  );

endinterface
