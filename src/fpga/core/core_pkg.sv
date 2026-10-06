// Types and constants shared across the core

`default_nettype none

package core_pkg;

  // Controller button bitmap, one per cont*_key input
  typedef struct packed {
    logic [3:0]  kind;         // controller type
    logic [11:0] unused;
    logic        face_start;
    logic        face_select;
    logic        trig_r3;
    logic        trig_l3;
    logic        trig_r2;
    logic        trig_l2;
    logic        trig_r1;
    logic        trig_l1;
    logic        face_y;
    logic        face_x;
    logic        face_b;
    logic        face_a;
    logic        dpad_right;
    logic        dpad_left;
    logic        dpad_down;
    logic        dpad_up;
  } cont_key_t;

  // Analog stick positions, unsigned
  typedef struct packed {
    logic [7:0] rstick_y;
    logic [7:0] rstick_x;
    logic [7:0] lstick_y;
    logic [7:0] lstick_x;
  } cont_joy_t;

  // Analog trigger positions, unsigned
  typedef struct packed {
    logic [7:0] rtrig;
    logic [7:0] ltrig;
  } cont_trig_t;

  typedef struct packed {
    logic [7:0] r;
    logic [7:0] g;
    logic [7:0] b;
  } rgb_t;

  // Real-time clock data sent by the host after boot
  typedef struct packed {
    logic [31:0] epoch_seconds;
    logic [31:0] date_bcd;
    logic [31:0] time_bcd;
  } rtc_t;

  // Core progress through a savestate save or load
  typedef struct packed {
    logic ack;   // pulse for at least 1 cycle after seeing the request rise
    logic busy;  // hold while in progress after ack
    logic ok;    // hold when done, clear when a new request starts
    logic err;   // hold on error, clear when a new request starts
  } savestate_status_t;

  // Status word tags. The host and core write these into the upper half of
  // the host (0xF8xx0000) and target (0xF8xx1000) command registers.
  localparam logic [15:0] HOST_TAG_COMMAND = "CM";
  localparam logic [15:0] HOST_TAG_BUSY = "BU";
  localparam logic [15:0] HOST_TAG_OK = "OK";
  localparam logic [15:0] TARGET_TAG_COMMAND = "cm";
  localparam logic [15:0] TARGET_TAG_BUSY = "bu";
  localparam logic [15:0] TARGET_TAG_OK = "ok";

  // Commands the host sends to the core
  typedef enum logic [15:0] {
    HOST_CMD_REQUEST_STATUS    = 16'h0000,
    HOST_CMD_RESET_ENTER       = 16'h0010,
    HOST_CMD_RESET_EXIT        = 16'h0011,
    HOST_CMD_DATASLOT_READ     = 16'h0080,
    HOST_CMD_DATASLOT_WRITE    = 16'h0082,
    HOST_CMD_DATASLOT_UPDATE   = 16'h008A,
    HOST_CMD_DATASLOT_COMPLETE = 16'h008F,
    HOST_CMD_RTC               = 16'h0090,
    HOST_CMD_SAVESTATE_START   = 16'h00A0,
    HOST_CMD_SAVESTATE_LOAD    = 16'h00A4,
    HOST_CMD_OSNOTIFY_MENU     = 16'h00B0
  } host_cmd_e;

  // Commands the core sends to the host
  typedef enum logic [15:0] {
    TARGET_CMD_READY_TO_RUN      = 16'h0140,
    TARGET_CMD_DATASLOT_READ     = 16'h0180,
    TARGET_CMD_DATASLOT_WRITE    = 16'h0184,
    TARGET_CMD_DATASLOT_GETFILE  = 16'h0190,
    TARGET_CMD_DATASLOT_OPENFILE = 16'h0192
  } target_cmd_e;

endpackage
