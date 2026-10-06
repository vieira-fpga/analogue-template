// Host and target command handler for the APF bridge, mapped at 0xF8xxxxxx.
// Adapted from Analogue's 2022 core_bridge_cmd. The APF spec also allows a
// soft CPU with block RAM, so replace this module if the core outgrows it.
//
// The host writes commands into the host registers, and this module passes
// them to the core through dataslot, savestate, rtc, and osnotify_inmenu.
// Target commands go the other way: the core raises a request on target and
// this module posts it for the host.
//
// Clock this from a board clock, never a PLL output, so it can report PLL lock
// to the host. Every port is synchronous to clk.
//
// Register map, as offsets from 0xF8xx0000:
//   0x0000          host command and status
//   0x0004, 0x0008  host parameter and response pointers, fixed at 0x20, 0x40
//   0x0020-0x002C   host command parameters
//   0x0040-0x004C   host command response
//   0x1000          target command and status
//   0x1004, 0x1008  target parameter and response pointers
//   0x1020-0x102C   target command parameters
//   0x2000-0x2FFF   data table

`default_nettype none

module core_bridge_cmd
  import core_pkg::*;
(
    input  wire  clk,
    output logic reset_n,

    input  wire         bridge_endian_little,
    input  wire  [31:0] bridge_addr,
    input  wire         bridge_rd,
    output logic [31:0] bridge_rd_data,
    input  wire         bridge_wr,
    input  wire  [31:0] bridge_wr_data,

    // Answers to the host's status query. A rising status_setup_done also
    // tells the host the core is ready to run.
    input wire status_boot_done,
    input wire status_setup_done,
    input wire status_running,

    dataslot_if.bridge        dataslot,
    savestate_if.bridge       savestate,
    target_dataslot_if.bridge target,

    // rtc_valid rises once, when the host sends the time
    output rtc_t rtc,
    output logic rtc_valid,

    output logic osnotify_inmenu,

    // Port A of the 1024 x 32 bit data table. The bridge uses port B.
    input  wire  [ 9:0] datatable_addr,
    input  wire         datatable_wren,
    input  wire  [31:0] datatable_data,
    output logic [31:0] datatable_q
);

  localparam logic [31:0] HOST_PARAM_PTR = 32'h20;
  localparam logic [31:0] HOST_RESP_PTR = 32'h40;

  // Result codes for HOST_CMD_REQUEST_STATUS
  localparam logic [15:0] STATUS_BOOTING = 16'd1;
  localparam logic [15:0] STATUS_SETUP = 16'd2;
  localparam logic [15:0] STATUS_IDLE = 16'd3;
  localparam logic [15:0] STATUS_RUNNING = 16'd4;

  typedef enum logic [2:0] {
    HOST_IDLE,
    HOST_PARSE,
    HOST_DONE_OK,
    HOST_DONE_CODE,
    HOST_DONE_ERR
  } host_state_e;

  typedef enum logic [2:0] {
    TARGET_IDLE,
    TARGET_READY_TO_RUN,
    TARGET_DATASLOT_OP,
    TARGET_WAIT_READY_TO_RUN,
    TARGET_WAIT_DATASLOT_OP
  } target_state_e;

  // Requests that start a target command, latched on their rising edge
  typedef struct packed {
    logic setup_done;
    logic read;
    logic write;
    logic getfile;
    logic openfile;
  } target_request_t;

  typedef struct packed {
    logic [7:0] region;
    logic [7:0] unused;
    logic [7:0] page;    // 0x00 host, 0x10 target, 0x20-0x2F data table
    logic [7:0] offset;
  } cmd_addr_t;

  // Result code for a savestate query: 0 idle, 1 busy, 2 done, 3 error
  function automatic logic [15:0] savestate_result(savestate_status_t status);
    if (status.err) begin
      return 16'd3;
    end

    if (status.ok) begin
      return 16'd2;
    end

    if (status.busy) begin
      return 16'd1;
    end

    return 16'd0;
  endfunction

  function automatic logic [31:0] byteswap(logic [31:0] word);
    return {word[7:0], word[15:8], word[23:16], word[31:24]};
  endfunction


  logic [31:0] bridge_wr_data_in;
  logic [31:0] bridge_rd_data_out;

  always_comb begin
    bridge_rd_data = bridge_endian_little ? byteswap(bridge_rd_data_out) : bridge_rd_data_out;
    bridge_wr_data_in = bridge_endian_little ? byteswap(bridge_wr_data) : bridge_wr_data;
  end

  cmd_addr_t addr;
  logic      host_sel;
  logic      target_sel;
  logic      datatable_sel;

  assign addr = bridge_addr;
  assign host_sel = addr.region == 8'hF8 && addr.page == 8'h00;
  assign target_sel = addr.region == 8'hF8 && addr.page == 8'h10;
  assign datatable_sel = addr.region == 8'hF8 && addr.page[7:4] == 4'h2;

  // Quartus ignores initial values on ports, so outputs that need a
  // power-up value come from these.
  logic reset_n_q = 1'b0;
  logic rtc_valid_q = 1'b0;
  logic osnotify_inmenu_q = 1'b0;

  assign reset_n = reset_n_q;
  assign rtc_valid = rtc_valid_q;
  assign osnotify_inmenu = osnotify_inmenu_q;

  logic            [31:0] host_status;
  logic            [31:0] host_param                 [4];
  logic            [31:0] host_resp                  [4] = '{default: '0};

  logic                   host_cmd_start = 1'b0;
  // Raw command words, not host_cmd_e. Quartus assumes an enum only holds
  // its listed values and would drop the default branch that answers
  // unknown commands.
  logic            [15:0] host_cmd_startval;
  logic            [15:0] host_cmd;
  logic            [15:0] host_resultcode;
  host_state_e            host_state = HOST_IDLE;

  logic            [31:0] target_status;
  logic            [31:0] target_param_ptr = 32'h20;
  logic            [31:0] target_resp_ptr = 32'h40;
  logic            [31:0] target_param               [4];
  target_state_e          target_state = TARGET_IDLE;

  target_request_t        target_request;
  target_request_t        target_request_prev = '0;
  target_request_t        target_request_queue = '0;

  assign target_request = '{
          setup_done: status_setup_done,
          read: target.read,
          write: target.write,
          getfile: target.getfile,
          openfile: target.openfile
      };

  logic [ 9:0] b_datatable_addr;
  logic        b_datatable_wren;
  logic [31:0] b_datatable_q;

  always_ff @(posedge clk) begin
    target_request_prev <= target_request;
    target_request_queue <= target_request_queue | (target_request & ~target_request_prev);

    b_datatable_wren <= bridge_wr && datatable_sel;
    b_datatable_addr <= bridge_addr[11:2];

    // Bridge register access
    if (bridge_wr && host_sel) begin
      unique case (addr.offset)
        8'h00: begin
          host_status <= bridge_wr_data_in;

          if (bridge_wr_data_in[31:16] == HOST_TAG_COMMAND) begin
            host_cmd_startval <= bridge_wr_data_in[15:0];
            host_cmd_start <= 1'b1;
          end
        end

        8'h20, 8'h24, 8'h28, 8'h2C: host_param[addr.offset[3:2]] <= bridge_wr_data_in;
        default: ;
      endcase
    end

    if (bridge_wr && target_sel) begin
      unique case (addr.offset)
        8'h00:   target_status <= bridge_wr_data_in;
        8'h04:   target_param_ptr <= bridge_wr_data_in;
        8'h08:   target_resp_ptr <= bridge_wr_data_in;
        default: ;
      endcase
    end

    if (bridge_rd && host_sel) begin
      unique case (addr.offset)
        8'h00: bridge_rd_data_out <= host_status;
        8'h04: bridge_rd_data_out <= HOST_PARAM_PTR;
        8'h08: bridge_rd_data_out <= HOST_RESP_PTR;
        8'h40, 8'h44, 8'h48, 8'h4C: bridge_rd_data_out <= host_resp[addr.offset[3:2]];
        default: ;
      endcase
    end

    if (bridge_rd && target_sel) begin
      unique case (addr.offset)
        8'h00: bridge_rd_data_out <= target_status;
        8'h04: bridge_rd_data_out <= target_param_ptr;
        8'h08: bridge_rd_data_out <= target_resp_ptr;
        8'h20, 8'h24, 8'h28, 8'h2C: bridge_rd_data_out <= target_param[addr.offset[3:2]];
        default: ;
      endcase
    end

    if (bridge_rd && datatable_sel) begin
      bridge_rd_data_out <= b_datatable_q;
    end

    // Host commands. The host writes "CM" and a command to host_status, then
    // polls until it reads "OK" and a result code. It never sends a second
    // command before the first finishes, so there is no queue.
    unique case (host_state)
      HOST_IDLE: begin
        dataslot.requestread <= 1'b0;
        dataslot.requestwrite <= 1'b0;
        dataslot.update <= 1'b0;
        savestate.start <= 1'b0;
        savestate.load <= 1'b0;

        if (host_cmd_start) begin
          host_cmd_start <= 1'b0;
          host_cmd <= host_cmd_startval;
          host_state <= HOST_PARSE;
        end
      end

      // Commands that wait on the core stay here until it acks
      HOST_PARSE: begin
        host_status <= {HOST_TAG_BUSY, host_cmd};

        unique case (host_cmd)
          HOST_CMD_REQUEST_STATUS: begin
            if (!status_boot_done) begin
              host_resultcode <= STATUS_BOOTING;
            end else if (status_setup_done) begin
              host_resultcode <= STATUS_IDLE;
            end else if (status_running) begin
              host_resultcode <= STATUS_RUNNING;
            end else begin
              host_resultcode <= STATUS_SETUP;
            end

            host_state <= HOST_DONE_CODE;
          end

          HOST_CMD_RESET_ENTER: begin
            reset_n_q  <= 1'b0;
            host_state <= HOST_DONE_OK;
          end

          HOST_CMD_RESET_EXIT: begin
            reset_n_q  <= 1'b1;
            host_state <= HOST_DONE_OK;
          end

          HOST_CMD_DATASLOT_READ: begin
            dataslot.allcomplete <= 1'b0;
            dataslot.requestread <= 1'b1;
            dataslot.requestread_id <= host_param[0][15:0];

            if (dataslot.requestread_ack) begin
              host_resultcode <= dataslot.requestread_ok ? 16'd0 : 16'd2;
              host_state <= HOST_DONE_CODE;
            end
          end

          HOST_CMD_DATASLOT_WRITE: begin
            dataslot.allcomplete <= 1'b0;
            dataslot.requestwrite <= 1'b1;
            dataslot.requestwrite_id <= host_param[0][15:0];
            dataslot.requestwrite_size <= host_param[1];

            if (dataslot.requestwrite_ack) begin
              host_resultcode <= dataslot.requestwrite_ok ? 16'd0 : 16'd2;
              host_state <= HOST_DONE_CODE;
            end
          end

          HOST_CMD_DATASLOT_UPDATE: begin
            dataslot.update <= 1'b1;
            dataslot.update_id <= host_param[0][15:0];
            dataslot.update_size <= host_param[1];
            host_state <= HOST_DONE_OK;
          end

          HOST_CMD_DATASLOT_COMPLETE: begin
            dataslot.allcomplete <= 1'b1;
            host_state <= HOST_DONE_OK;
          end

          HOST_CMD_RTC: begin
            rtc_valid_q <= 1'b1;
            rtc.epoch_seconds <= host_param[0];
            rtc.date_bcd <= host_param[1];
            rtc.time_bcd <= host_param[2];
            host_state <= HOST_DONE_OK;
          end

          // Bit 0 of the first parameter starts a save. Without it, the
          // command only reports progress.
          HOST_CMD_SAVESTATE_START: begin
            host_resp[0] <= 32'(savestate.supported);
            host_resp[1] <= savestate.addr;
            host_resp[2] <= savestate.size;
            host_resultcode <= savestate_result(savestate.start_status);

            if (host_param[0][0]) begin
              savestate.start <= 1'b1;

              if (savestate.start_status.ack) begin
                host_state <= HOST_DONE_CODE;
              end
            end else begin
              host_state <= HOST_DONE_CODE;
            end
          end

          // Same as HOST_CMD_SAVESTATE_START, for loading
          HOST_CMD_SAVESTATE_LOAD: begin
            host_resp[0] <= 32'(savestate.supported);
            host_resp[1] <= savestate.addr;
            host_resp[2] <= savestate.maxloadsize;
            host_resultcode <= savestate_result(savestate.load_status);

            if (host_param[0][0]) begin
              savestate.load <= 1'b1;

              if (savestate.load_status.ack) begin
                host_state <= HOST_DONE_CODE;
              end
            end else begin
              host_state <= HOST_DONE_CODE;
            end
          end

          HOST_CMD_OSNOTIFY_MENU: begin
            osnotify_inmenu_q <= host_param[0][0];
            host_state <= HOST_DONE_OK;
          end

          default: host_state <= HOST_DONE_ERR;
        endcase
      end

      HOST_DONE_OK: begin
        host_status <= {HOST_TAG_OK, 16'h0000};
        host_state  <= HOST_IDLE;
      end

      HOST_DONE_CODE: begin
        host_status <= {HOST_TAG_OK, host_resultcode};
        host_state  <= HOST_IDLE;
      end

      HOST_DONE_ERR: begin
        host_status <= {HOST_TAG_OK, 16'hFFFF};
        host_state  <= HOST_IDLE;
      end
    endcase

    // Target commands. A queued request fills the target parameters, then
    // "cm" in target_status hands it to the host. The host answers "bu" while
    // it works and "ok" with an error code when done.
    unique case (target_state)
      TARGET_IDLE: begin
        target.ack <= 1'b0;

        if (target_request_queue.setup_done) begin
          target_request_queue.setup_done <= 1'b0;
          target_state <= TARGET_READY_TO_RUN;
        end else if (target_request_queue.read) begin
          target_request_queue.read <= 1'b0;
          target_status[15:0] <= TARGET_CMD_DATASLOT_READ;
          target_param <= '{target.id, target.slotoffset, target.bridgeaddr, target.length};
          target_state <= TARGET_DATASLOT_OP;
        end else if (target_request_queue.write) begin
          target_request_queue.write <= 1'b0;
          target_status[15:0] <= TARGET_CMD_DATASLOT_WRITE;
          target_param <= '{target.id, target.slotoffset, target.bridgeaddr, target.length};
          target_state <= TARGET_DATASLOT_OP;
        end else if (target_request_queue.getfile) begin
          target_request_queue.getfile <= 1'b0;
          target_status[15:0] <= TARGET_CMD_DATASLOT_GETFILE;
          target_param[0] <= target.id;
          target_param[1] <= target.buffer_resp_struct;
          target_state <= TARGET_DATASLOT_OP;
        end else if (target_request_queue.openfile) begin
          target_request_queue.openfile <= 1'b0;
          target_status[15:0] <= TARGET_CMD_DATASLOT_OPENFILE;
          target_param[0] <= target.id;
          target_param[1] <= target.buffer_param_struct;
          target_state <= TARGET_DATASLOT_OP;
        end
      end

      TARGET_READY_TO_RUN: begin
        target_status <= {TARGET_TAG_COMMAND, TARGET_CMD_READY_TO_RUN};
        target_state  <= TARGET_WAIT_READY_TO_RUN;
      end

      TARGET_DATASLOT_OP: begin
        target_status[31:16] <= TARGET_TAG_COMMAND;
        target.done <= 1'b0;
        target.err <= '0;
        target_state <= TARGET_WAIT_DATASLOT_OP;
      end

      TARGET_WAIT_DATASLOT_OP: begin
        if (target_status[31:16] == TARGET_TAG_BUSY) begin
          target.ack <= 1'b1;
        end

        if (target_status[31:16] == TARGET_TAG_OK) begin
          target.err   <= target_status[2:0];
          target.done  <= 1'b1;
          target_state <= TARGET_IDLE;
        end
      end

      TARGET_WAIT_READY_TO_RUN: begin
        if (target_status[31:16] == TARGET_TAG_OK) begin
          target_state <= TARGET_IDLE;
        end
      end
    endcase
  end

  host_cmd_while_busy :
  assert property (
    @(posedge clk) bridge_wr && host_sel && addr.offset == 8'h00
        && bridge_wr_data_in[31:16] == HOST_TAG_COMMAND
        |-> host_state == HOST_IDLE && !host_cmd_start
  )
  else $error("host started command %h before the last one finished", bridge_wr_data_in[15:0]);

  mf_datatable datatable (
      .address_a(datatable_addr),
      .address_b(b_datatable_addr),
      .clock_a  (clk),
      .clock_b  (clk),
      .data_a   (datatable_data),
      .data_b   (bridge_wr_data_in),
      .wren_a   (datatable_wren),
      .wren_b   (b_datatable_wren),
      .q_a      (datatable_q),
      .q_b      (b_datatable_q)
  );

endmodule
