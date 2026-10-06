// User core. apf_top instantiates this and wires it to the Pocket's pins and
// the APF bridge. The template draws a grey 320x240 screen, plays silence,
// and answers host commands through core_bridge_cmd.

`default_nettype none

module core_top
  import core_pkg::*;
(
    // 74.25 MHz board clocks. They are not phase aligned, so treat each as its
    // own clock domain.
    input wire clk_74a,
    input wire clk_74b,

    // Cartridge slot, behind level translators. Each *_dir pin sets its
    // translator direction: 0 is input, 1 is output.
    inout  wire  [7:0] cart_tran_bank2,          // GBA AD[15:8]
    output logic       cart_tran_bank2_dir,
    inout  wire  [7:0] cart_tran_bank3,          // GBA AD[7:0]
    output logic       cart_tran_bank3_dir,
    inout  wire  [7:0] cart_tran_bank1,          // GBA A[23:16]
    output logic       cart_tran_bank1_dir,
    inout  wire  [7:4] cart_tran_bank0,          // GBA PHI, WR#, RD#, CS1# from bit 7 down
    output logic       cart_tran_bank0_dir,
    inout  wire        cart_tran_pin30,          // GBA CS2#/RES#
    output wire        cart_tran_pin30_dir,
    // With a GBC cartridge inserted, holding this low or leaving it floating
    // pulls /RES low. Drive it high to let pin 30 control /RES.
    output logic       cart_pin30_pwroff_reset,
    inout  wire        cart_tran_pin31,          // GBA IRQ/DRQ
    output logic       cart_tran_pin31_dir,

    // Infrared transceiver
    input  wire  port_ir_rx,
    output logic port_ir_tx,
    output logic port_ir_rx_disable,

    // Link port, behind level translators
    inout  wire  port_tran_si,
    output logic port_tran_si_dir,
    inout  wire  port_tran_so,
    output logic port_tran_so_dir,
    inout  wire  port_tran_sck,
    output logic port_tran_sck_dir,
    inout  wire  port_tran_sd,
    output logic port_tran_sd_dir,

    // Two 128 Mbit cellular PSRAM chips
    output logic [21:16] cram0_a,
    inout  wire  [ 15:0] cram0_dq,
    input  wire          cram0_wait,
    output logic         cram0_clk,
    output logic         cram0_adv_n,
    output logic         cram0_cre,
    output logic         cram0_ce0_n,
    output logic         cram0_ce1_n,
    output logic         cram0_oe_n,
    output logic         cram0_we_n,
    output logic         cram0_ub_n,
    output logic         cram0_lb_n,

    output logic [21:16] cram1_a,
    inout  wire  [ 15:0] cram1_dq,
    input  wire          cram1_wait,
    output logic         cram1_clk,
    output logic         cram1_adv_n,
    output logic         cram1_cre,
    output logic         cram1_ce0_n,
    output logic         cram1_ce1_n,
    output logic         cram1_oe_n,
    output logic         cram1_we_n,
    output logic         cram1_ub_n,
    output logic         cram1_lb_n,

    // 512 Mbit SDRAM, 16 bits wide
    output logic [12:0] dram_a,
    output logic [ 1:0] dram_ba,
    inout  wire  [15:0] dram_dq,
    output logic [ 1:0] dram_dqm,
    output logic        dram_clk,
    output logic        dram_cke,
    output logic        dram_ras_n,
    output logic        dram_cas_n,
    output logic        dram_we_n,

    // 1 Mbit SRAM, 16 bits wide
    output logic [16:0] sram_a,
    inout  wire  [15:0] sram_dq,
    output logic        sram_oe_n,
    output logic        sram_we_n,
    output logic        sram_ub_n,
    output logic        sram_lb_n,

    input wire vblank,  // from the dock, for sync in some display modes

    // UART on the 6515D USB breakout
    output wire dbg_tx,
    input  wire dbg_rx,

    // Pads near the JTAG connector, free to solder to
    output wire user1,
    input  wire user2,

    // Internal I2C bus, reserved
    inout  wire aux_sda,
    output wire aux_scl,

    output wire vpll_feed,  // reserved, do not use

    // Video to the scaler. video_rgb_clock_90 is the pixel clock shifted 90
    // degrees. Hold video_de high for visible pixels.
    output rgb_t video_rgb,
    output logic video_rgb_clock,
    output logic video_rgb_clock_90,
    output logic video_de,
    output logic video_skip,
    output logic video_vs,
    output logic video_hs,

    // I2S audio to the scaler
    output logic audio_mclk = 1'b0,
    input  wire  audio_adc,
    output logic audio_dac,
    output logic audio_lrck = 1'b0,

    // APF bridge bus, synchronous to clk_74a. Every device sees every write.
    // Reads go through the mux below.
    output logic        bridge_endian_little,
    input  wire  [31:0] bridge_addr,
    input  wire         bridge_rd,
    output logic [31:0] bridge_rd_data,
    input  wire         bridge_wr,
    input  wire  [31:0] bridge_wr_data,

    input cont_key_t  cont1_key,
    input cont_key_t  cont2_key,
    input cont_key_t  cont3_key,
    input cont_key_t  cont4_key,
    input cont_joy_t  cont1_joy,
    input cont_joy_t  cont2_joy,
    input cont_joy_t  cont3_joy,
    input cont_joy_t  cont4_joy,
    input cont_trig_t cont1_trig,
    input cont_trig_t cont2_trig,
    input cont_trig_t cont3_trig,
    input cont_trig_t cont4_trig
);

  // Unused I/O. The IR LED and receiver are off to save power, the cartridge
  // and link port translators face inward, and every memory is deselected.
  assign port_ir_tx              = 1'b0;
  assign port_ir_rx_disable      = 1'b1;

  assign cart_tran_bank3         = 'z;
  assign cart_tran_bank3_dir     = 1'b0;
  assign cart_tran_bank2         = 'z;
  assign cart_tran_bank2_dir     = 1'b0;
  assign cart_tran_bank1         = 'z;
  assign cart_tran_bank1_dir     = 1'b0;
  assign cart_tran_bank0         = 4'hF;
  assign cart_tran_bank0_dir     = 1'b1;
  assign cart_tran_pin30         = 1'b0;
  assign cart_tran_pin30_dir     = 1'bz;  // left to the hardware
  assign cart_pin30_pwroff_reset = 1'b0;
  assign cart_tran_pin31         = 1'bz;
  assign cart_tran_pin31_dir     = 1'b0;

  assign port_tran_so            = 1'bz;
  assign port_tran_so_dir        = 1'b0;
  assign port_tran_si            = 1'bz;
  assign port_tran_si_dir        = 1'b0;
  assign port_tran_sck           = 1'bz;
  assign port_tran_sck_dir       = 1'b0;
  assign port_tran_sd            = 1'bz;
  assign port_tran_sd_dir        = 1'b0;

  assign cram0_a                 = '0;
  assign cram0_dq                = 'z;
  assign cram0_clk               = 1'b0;
  assign cram0_adv_n             = 1'b1;
  assign cram0_cre               = 1'b0;
  assign cram0_ce0_n             = 1'b1;
  assign cram0_ce1_n             = 1'b1;
  assign cram0_oe_n              = 1'b1;
  assign cram0_we_n              = 1'b1;
  assign cram0_ub_n              = 1'b1;
  assign cram0_lb_n              = 1'b1;

  assign cram1_a                 = '0;
  assign cram1_dq                = 'z;
  assign cram1_clk               = 1'b0;
  assign cram1_adv_n             = 1'b1;
  assign cram1_cre               = 1'b0;
  assign cram1_ce0_n             = 1'b1;
  assign cram1_ce1_n             = 1'b1;
  assign cram1_oe_n              = 1'b1;
  assign cram1_we_n              = 1'b1;
  assign cram1_ub_n              = 1'b1;
  assign cram1_lb_n              = 1'b1;

  assign dram_a                  = '0;
  assign dram_ba                 = '0;
  assign dram_dq                 = 'z;
  assign dram_dqm                = '0;
  assign dram_clk                = 1'b0;
  assign dram_cke                = 1'b0;
  assign dram_ras_n              = 1'b1;
  assign dram_cas_n              = 1'b1;
  assign dram_we_n               = 1'b1;

  assign sram_a                  = '0;
  assign sram_dq                 = 'z;
  assign sram_oe_n               = 1'b1;
  assign sram_we_n               = 1'b1;
  assign sram_ub_n               = 1'b1;
  assign sram_lb_n               = 1'b1;

  assign dbg_tx                  = 1'bz;
  assign user1                   = 1'bz;
  assign aux_sda                 = 1'bz;
  assign aux_scl                 = 1'bz;
  assign vpll_feed               = 1'bz;

  // The PLL makes the 12.288 MHz pixel clock. Its lock signal, synced to
  // clk_74a, tells the host the core has booted.
  logic clk_core_12288;
  logic clk_core_12288_90deg;
  logic pll_core_locked;
  logic pll_core_locked_s;

  mf_pllbase pll (
      .refclk(clk_74a),
      .rst   (1'b0),

      .outclk_0(clk_core_12288),
      .outclk_1(clk_core_12288_90deg),

      .locked(pll_core_locked)
  );

  synch_3 pll_locked_sync (
      .i  (pll_core_locked),
      .o  (pll_core_locked_s),
      .clk(clk_74a)
  );

  // Bridge read mux. Give each new device its own address region and return
  // its read data here.
  logic [31:0] cmd_bridge_rd_data;

  assign bridge_endian_little = 1'b0;

  always_comb begin
    unique case (bridge_addr[31:24])
      // 8'h10: bridge_rd_data = example_device_data;
      8'hF8:   bridge_rd_data = cmd_bridge_rd_data;
      default: bridge_rd_data = '0;
    endcase
  end

  // Host command handler. The host drives reset_n to start and stop the core.
  // The tie-offs below accept every data slot request and turn off savestates
  // and target commands. Replace them as the core needs each feature.
  logic reset_n;
  rtc_t rtc;
  logic rtc_valid;
  logic osnotify_inmenu;
  logic [31:0] datatable_q;

  dataslot_if dataslot ();
  savestate_if savestate ();
  target_dataslot_if target_dataslot ();

  assign dataslot.requestread_ack = 1'b1;
  assign dataslot.requestread_ok = 1'b1;
  assign dataslot.requestwrite_ack = 1'b1;
  assign dataslot.requestwrite_ok = 1'b1;

  assign savestate.supported = 1'b0;
  assign savestate.addr = '0;
  assign savestate.size = '0;
  assign savestate.maxloadsize = '0;
  assign savestate.start_status = '0;
  assign savestate.load_status = '0;

  assign target_dataslot.read = 1'b0;
  assign target_dataslot.write = 1'b0;
  assign target_dataslot.getfile = 1'b0;
  assign target_dataslot.openfile = 1'b0;
  assign target_dataslot.id = '0;
  assign target_dataslot.slotoffset = '0;
  assign target_dataslot.bridgeaddr = '0;
  assign target_dataslot.length = '0;
  assign target_dataslot.buffer_param_struct = '0;
  assign target_dataslot.buffer_resp_struct = '0;

  core_bridge_cmd bridge_cmd (
      .clk    (clk_74a),
      .reset_n(reset_n),

      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd           (bridge_rd),
      .bridge_rd_data      (cmd_bridge_rd_data),
      .bridge_wr           (bridge_wr),
      .bridge_wr_data      (bridge_wr_data),

      .status_boot_done (pll_core_locked_s),
      .status_setup_done(pll_core_locked_s),
      .status_running   (reset_n),

      .dataslot (dataslot),
      .savestate(savestate),
      .target   (target_dataslot),

      .rtc            (rtc),
      .rtc_valid      (rtc_valid),
      .osnotify_inmenu(osnotify_inmenu),

      .datatable_addr('0),
      .datatable_wren(1'b0),
      .datatable_data('0),
      .datatable_q   (datatable_q)
  );

  // Video timing. At 12.288 MHz, a 60 Hz frame is 204,800 clocks: 512 lines
  // of 400 clocks. 320x240 of that is visible and the rest is blanking.
  localparam int VID_V_BPORCH = 10;
  localparam int VID_V_ACTIVE = 240;
  localparam int VID_V_TOTAL = 512;
  localparam int VID_H_BPORCH = 10;
  localparam int VID_H_ACTIVE = 320;
  localparam int VID_H_TOTAL = 400;

  logic       video_reset_n;
  logic [9:0] x_count;
  logic [9:0] y_count;

  assign video_rgb_clock = clk_core_12288;
  assign video_rgb_clock_90 = clk_core_12288_90deg;

  synch_3 video_reset_sync (
      .i  (reset_n),
      .o  (video_reset_n),
      .clk(clk_core_12288)
  );

  always_ff @(posedge clk_core_12288) begin
    if (!video_reset_n) begin
      x_count <= '0;
      y_count <= '0;
      video_rgb <= '0;
      video_de <= 1'b0;
      video_skip <= 1'b0;
      video_vs <= 1'b0;
      video_hs <= 1'b0;
    end else begin
      video_rgb <= '0;
      video_de <= 1'b0;
      video_skip <= 1'b0;
      video_vs <= 1'b0;
      video_hs <= 1'b0;

      x_count <= x_count + 1'b1;

      if (x_count == VID_H_TOTAL - 1) begin
        x_count <= '0;
        y_count <= y_count + 1'b1;

        if (y_count == VID_V_TOTAL - 1) begin
          y_count <= '0;
        end
      end

      // Both syncs pulse in the back porch. HS trails VS by 3 clocks so the
      // two never land on the same cycle.
      if (x_count == 0 && y_count == 0) begin
        video_vs <= 1'b1;
      end

      if (x_count == 3) begin
        video_hs <= 1'b1;
      end

      if (x_count >= VID_H_BPORCH && x_count < VID_H_ACTIVE + VID_H_BPORCH
            && y_count >= VID_V_BPORCH && y_count < VID_V_ACTIVE + VID_V_BPORCH) begin
        video_de  <= 1'b1;
        video_rgb <= '{r: 8'd60, g: 8'd60, b: 8'd60};
      end
    end
  end

  // Silent I2S audio, timed from clk_74a with clock enables so there are no
  // derived clocks to constrain. MCLK toggles whenever the fractional
  // accumulator wraps: 74.25 MHz * 245,760 / 742,500 is 24.576 million
  // toggles a second, so MCLK is 12.288 MHz. SCLK is MCLK / 4 and has no pin.
  // Each channel is 32 SCLK bits, 16 of data then 16 of padding, so LRCK runs
  // at 48 kHz. To play sound, shift the next DAC bit out on sclk_fall.
  localparam int MCLK_STEP = 245_760;
  localparam int MCLK_WRAP = 742_500;
  localparam int MCLK_ACCUM_BITS = $clog2(MCLK_WRAP + MCLK_STEP);

  logic [MCLK_ACCUM_BITS-1:0] mclk_accum = '0;
  logic                       mclk_rise;
  logic [                1:0] sclk_div = '0;
  logic                       sclk_fall;
  logic [                4:0] bit_count = '0;

  assign mclk_rise = mclk_accum >= MCLK_WRAP && !audio_mclk;
  assign sclk_fall = mclk_rise && sclk_div == 2'd3;
  assign audio_dac = 1'b0;

  always_ff @(posedge clk_74a) begin
    if (mclk_accum >= MCLK_WRAP) begin
      audio_mclk <= !audio_mclk;
      mclk_accum <= MCLK_ACCUM_BITS'(mclk_accum - MCLK_WRAP + MCLK_STEP);
    end else begin
      mclk_accum <= MCLK_ACCUM_BITS'(mclk_accum + MCLK_STEP);
    end

    if (mclk_rise) begin
      sclk_div <= sclk_div + 1'b1;
    end

    if (sclk_fall) begin
      bit_count <= bit_count + 1'b1;

      if (bit_count == 5'd31) begin
        audio_lrck <= !audio_lrck;
      end
    end
  end

endmodule
