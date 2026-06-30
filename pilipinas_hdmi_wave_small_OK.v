// (c) fpga4fun.com & KNJN LLC 2013-2023
// Modified for Gowin Tang Nano 9K HDMI
// Philippine flag — waving sine effect, 1:2 ratio (128×64 px, half-size), centred 640×480
// Wave rate halved vs original (full cycle ~1.0s instead of ~0.5s)
`default_nettype none
`define APICULA

module HDMI_test(
	input  clk,
	input  btn,
	output [3:0] led,
	output [2:0] tmds_d_p, tmds_d_n,
	output tmds_clk_p, tmds_clk_n
);

wire pixclk, clk_TMDS, lock;

reg [23:0] cnt = 0;
always @(posedge pixclk) cnt <= cnt + 1;
assign led = cnt[23:20];

`ifdef APICULA
wire clk_250;
pll_25 pll_25_inst(
	.clkin(clk), .clkout(clk_250), .clkoutd(pixclk), .lock(lock)
);
reg clk_250_r = 0;
always @(posedge clk_250) clk_250_r <= ~clk_250_r;
assign clk_TMDS = clk_250_r;
`else
pll_25 pll_25_inst(
	.clkin(clk), .clkout(clk_TMDS), .clkoutd(), .lock(lock)
);
clkdiv5 clkdiv5_inst(
	.hclkin(clk_TMDS), .clkout(pixclk), .resetn(lock)
);
`endif

////////////////////////////////////////////////////////////////////////
// VGA timing 640x480 @ 60Hz
////////////////////////////////////////////////////////////////////////
reg [9:0] CounterX = 0, CounterY = 0;
reg hSync, vSync, DrawArea;

always @(posedge pixclk) DrawArea <= (CounterX < 640) && (CounterY < 480);
always @(posedge pixclk) CounterX <= (CounterX == 799) ? 0 : CounterX + 1;
always @(posedge pixclk)
	if (CounterX == 799) CounterY <= (CounterY == 524) ? 0 : CounterY + 1;
always @(posedge pixclk) hSync <= (CounterX >= 656) && (CounterX < 752);
always @(posedge pixclk) vSync <= (CounterY >= 490) && (CounterY < 492);

reg vSync_d = 0;
always @(posedge pixclk) vSync_d <= vSync;

////////////////////////////////////////////////////////////////////////
// SINE WAVE ANIMATION
// 64-entry LUT, amplitude ±10 px (halved), wave period = 128 px across the
// half-size flag. wave_phase advances 1 per frame (half the original rate)
// -> full cycle in 64 frames (~1.0 s, twice as slow as before)
////////////////////////////////////////////////////////////////////////
reg [5:0] wave_phase = 0;
always @(posedge pixclk)
	if (vSync && !vSync_d) wave_phase <= wave_phase + 6'd1;

function automatic signed [6:0] sine_lut;
	input [5:0] idx;
	case (idx)
		6'd 0: sine_lut =  7'd0;   6'd 1: sine_lut =  7'd1;
		6'd 2: sine_lut =  7'd2;   6'd 3: sine_lut =  7'd3;
		6'd 4: sine_lut =  7'd4;   6'd 5: sine_lut =  7'd4;
		6'd 6: sine_lut =  7'd6;   6'd 7: sine_lut =  7'd6;
		6'd 8: sine_lut =  7'd7;   6'd 9: sine_lut =  7'd8;
		6'd10: sine_lut =  7'd8;   6'd11: sine_lut =  7'd9;
		6'd12: sine_lut =  7'd9;   6'd13: sine_lut =  7'd10;
		6'd14: sine_lut =  7'd10;  6'd15: sine_lut =  7'd10;
		6'd16: sine_lut =  7'd10;  6'd17: sine_lut =  7'd10;
		6'd18: sine_lut =  7'd10;  6'd19: sine_lut =  7'd10;
		6'd20: sine_lut =  7'd9;   6'd21: sine_lut =  7'd9;
		6'd22: sine_lut =  7'd8;   6'd23: sine_lut =  7'd8;
		6'd24: sine_lut =  7'd7;   6'd25: sine_lut =  7'd6;
		6'd26: sine_lut =  7'd6;   6'd27: sine_lut =  7'd4;
		6'd28: sine_lut =  7'd4;   6'd29: sine_lut =  7'd3;
		6'd30: sine_lut =  7'd2;   6'd31: sine_lut =  7'd1;
		6'd32: sine_lut =  7'd0;   6'd33: sine_lut = -7'd1;
		6'd34: sine_lut = -7'd2;   6'd35: sine_lut = -7'd3;
		6'd36: sine_lut = -7'd4;   6'd37: sine_lut = -7'd4;
		6'd38: sine_lut = -7'd6;   6'd39: sine_lut = -7'd6;
		6'd40: sine_lut = -7'd7;   6'd41: sine_lut = -7'd8;
		6'd42: sine_lut = -7'd8;   6'd43: sine_lut = -7'd9;
		6'd44: sine_lut = -7'd9;   6'd45: sine_lut = -7'd10;
		6'd46: sine_lut = -7'd10;  6'd47: sine_lut = -7'd10;
		6'd48: sine_lut = -7'd10;  6'd49: sine_lut = -7'd10;
		6'd50: sine_lut = -7'd10;  6'd51: sine_lut = -7'd10;
		6'd52: sine_lut = -7'd9;   6'd53: sine_lut = -7'd9;
		6'd54: sine_lut = -7'd8;   6'd55: sine_lut = -7'd8;
		6'd56: sine_lut = -7'd7;   6'd57: sine_lut = -7'd6;
		6'd58: sine_lut = -7'd6;   6'd59: sine_lut = -7'd4;
		6'd60: sine_lut = -7'd4;   6'd61: sine_lut = -7'd3;
		6'd62: sine_lut = -7'd2;   6'd63: sine_lut = -7'd1;
		default: sine_lut = 7'd0;
	endcase
endfunction

// wave_idx: relX/2 gives period of 128px across the half-size flag; wraps with phase for animation
// NOTE: relX is only valid inside in_flag_area, but wave_offset is computed combinatorially
// for every CounterX so we compute it unconditionally (using CounterX) and mask via in_flag_area.
wire [5:0] wave_idx = CounterX[6:1] + wave_phase;
wire signed [6:0] wave_offset = sine_lut(wave_idx);

////////////////////////////////////////////////////////////////////////
// FLAG GEOMETRY (half-size)
//
// Real Philippine flag proportion = 1:2, so at 64px tall -> 128px wide.
// Screen is 640x480; centre horizontally: left edge = (640-128)/2 = 256.
// Centre vertically:  top edge  = (480-64)/2 = 208.
//
// With ±10px wave amplitude the flag occupies Y=198..282, X=256..383.
//
// Chevron (white triangle):
//   base = flag height (64px) on the left edge, vertex at relX=32, relY=31.
//   relX <= relY AND relX <= (63-relY) AND relX < 64  — fires once, left side.
//
// Waving stripe boundary uses adj_Y so blue/red split waves with the flag.
////////////////////////////////////////////////////////////////////////
localparam signed [10:0] FLAG_Y      = 11'd208;  // top  edge at rest (centred for new size)
localparam        [9:0]  FLAG_HEIGHT = 10'd64;    // half of 128
localparam        [9:0]  FLAG_X      = 10'd256;   // left edge (centred, 1:2 ratio)
localparam        [9:0]  FLAG_WIDTH  = 10'd128;   // half of 256

// Wave-adjusted Y: subtract per-column sine offset so the flag silhouette waves
wire signed [10:0] adj_Y = $signed({1'b0, CounterY}) - wave_offset;

// Flag pixel test: constrained to 128×64, centred
wire in_flag_area = (CounterX >= FLAG_X) &&
                    (CounterX <  FLAG_X + FLAG_WIDTH) &&
                    (adj_Y    >= FLAG_Y) &&
                    (adj_Y    <  FLAG_Y + $signed({1'b0, FLAG_HEIGHT}));

// Flag-local coordinates: relX 0..127, relY 0..63
wire [9:0] relX = CounterX - FLAG_X;
wire [6:0] relY = adj_Y[6:0] - FLAG_Y[6:0];

// ---- CHEVRON (single, left portion) ----
// Vertex at relX=32, relY=31 (half of 64,63): relX <= relY AND relX <= (63-relY) AND relX < 64
wire is_triangle = (relX <= {2'b0, relY}) &&
                   (relX <= (10'd63 - {2'b0, relY})) &&
                   (relX < 10'd64);

// Blue/red stripe boundary — uses adj_Y so it waves with the flag edges
wire is_top_half = (adj_Y < FLAG_Y + 11'd32);

////////////////////////////////////////////////////////////////////////
// SUN — centred at triangle centroid (halved for smaller flag)
// Triangle vertices: (0,0), (0,63), (31,31)  -> centroid ~ (10, 31)
// Coordinates: relX (flag-local, 0..127) for horizontal, relY (0..63) for vertical
////////////////////////////////////////////////////////////////////////
wire [9:0] sun_dx = (relX > 10'd10) ? (relX - 10'd10) : (10'd10 - relX);
wire [6:0] sun_dy = (relY  > 7'd31) ? (relY  - 7'd31) : (7'd31  - relY);

wire sun_core = (sun_dx <= 10'd3 && sun_dy <= 7'd3) && (sun_dx + sun_dy <= 10'd4);

wire sun_rays =
	(sun_dx <= 10'd0  && sun_dy >= 7'd2  && sun_dy <= 7'd7)   ||   // vertical
	(sun_dy <= 7'd0   && sun_dx >= 10'd2 && sun_dx <= 10'd7)  ||  // horizontal
	((sun_dx[6:0] == sun_dy || sun_dx[6:0] == sun_dy + 7'd1 || sun_dy == sun_dx[6:0] + 7'd1)
	    && sun_dx >= 10'd2 && sun_dx <= 10'd5)                   ||  // diagonal
	((relX + {2'b0, relY} >= 10'd41) && (relX + {2'b0, relY} <= 10'd43)
	    && sun_dx >= 10'd2 && sun_dx <= 10'd5);                      // anti-diagonal

wire is_sun = sun_core || sun_rays;

////////////////////////////////////////////////////////////////////////
// THREE STARS — one at each triangle corner (halved for smaller flag)
// Coordinates in flag-local (relX 0..127, relY 0..63) space.
//   Top-left corner  (0,0)   -> centre (2, 5)
//   Bottom-left      (0,63)  -> centre (2, 58)
//   Apex             (31,31) -> centre (27, 32)
////////////////////////////////////////////////////////////////////////
wire [9:0] s1_dx = (relX > 10'd2)   ? (relX - 10'd2)   : (10'd2   - relX);
wire [6:0] s1_dy = (relY  > 7'd5)   ? (relY  - 7'd5)   : (7'd5    - relY);
wire is_star1 = (s1_dx + s1_dy <= 10'd2) ||
                (s1_dx <= 10'd0 && s1_dy <= 7'd2) ||
                (s1_dy <= 7'd0  && s1_dx <= 10'd2);

wire [9:0] s2_dx = (relX > 10'd2)   ? (relX - 10'd2)   : (10'd2   - relX);
wire [6:0] s2_dy = (relY  > 7'd58)  ? (relY  - 7'd58)  : (7'd58   - relY);
wire is_star2 = (s2_dx + s2_dy <= 10'd2) ||
                (s2_dx <= 10'd0 && s2_dy <= 7'd2) ||
                (s2_dy <= 7'd0  && s2_dx <= 10'd2);

wire [9:0] s3_dx = (relX > 10'd27) ? (relX - 10'd27) : (10'd27 - relX);
wire [6:0] s3_dy = (relY  > 7'd32) ? (relY  - 7'd32) : (7'd32  - relY);
wire is_star3 = (s3_dx + s3_dy <= 10'd2) ||
                (s3_dx <= 10'd0 && s3_dy <= 7'd2) ||
                (s3_dy <= 7'd0  && s3_dx <= 10'd2);

wire is_gold = is_sun || is_star1 || is_star2 || is_star3;

////////////////////////////////////////////////////////////////////////
// RENDERING
////////////////////////////////////////////////////////////////////////
reg [7:0] red, green, blue;

always @(posedge pixclk) begin
	if (in_flag_area) begin
		if (is_triangle) begin
			if (is_gold) begin
				red <= 8'hFC; green <= 8'hD1; blue <= 8'h16; // Philippine Gold
			end else begin
				red <= 8'hFF; green <= 8'hFF; blue <= 8'hFF; // White chevron
			end
		end else if (is_top_half) begin
			red <= 8'h00; green <= 8'h38; blue <= 8'hA8;     // Royal Blue
		end else begin
			red <= 8'hCE; green <= 8'h11; blue <= 8'h26;     // Scarlet Red
		end
	end else begin
		red <= 8'h00; green <= 8'h00; blue <= 8'h00;         // Black background
	end
end

////////////////////////////////////////////////////////////////////////
wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
TMDS_encoder encode_R(.clk(pixclk), .VD(red),   .CD(2'b00),         .VDE(DrawArea), .TMDS(TMDS_red));
TMDS_encoder encode_G(.clk(pixclk), .VD(green), .CD(2'b00),         .VDE(DrawArea), .TMDS(TMDS_green));
TMDS_encoder encode_B(.clk(pixclk), .VD(blue),  .CD({vSync,hSync}), .VDE(DrawArea), .TMDS(TMDS_blue));

wire [2:0] tmds_d;
OSER10 tmds_serdes[2:0] (
	.Q(tmds_d),
	.D0({TMDS_red[0], TMDS_green[0], TMDS_blue[0]}),
	.D1({TMDS_red[1], TMDS_green[1], TMDS_blue[1]}),
	.D2({TMDS_red[2], TMDS_green[2], TMDS_blue[2]}),
	.D3({TMDS_red[3], TMDS_green[3], TMDS_blue[3]}),
	.D4({TMDS_red[4], TMDS_green[4], TMDS_blue[4]}),
	.D5({TMDS_red[5], TMDS_green[5], TMDS_blue[5]}),
	.D6({TMDS_red[6], TMDS_green[6], TMDS_blue[6]}),
	.D7({TMDS_red[7], TMDS_green[7], TMDS_blue[7]}),
	.D8({TMDS_red[8], TMDS_green[8], TMDS_blue[8]}),
	.D9({TMDS_red[9], TMDS_green[9], TMDS_blue[9]}),
	.PCLK(pixclk),
	.FCLK(clk_TMDS),
	.RESET(~lock)
);

ELVDS_OBUF tmds_bufds[3:0] (
	.I({pixclk, tmds_d}),
	.O({tmds_clk_p, tmds_d_p}),
	.OB({tmds_clk_n, tmds_d_n})
);
endmodule

////////////////////////////////////////////////////////////////////////
module TMDS_encoder(
	input clk,
	input [7:0] VD,
	input [1:0] CD,
	input VDE,
	output reg [9:0] TMDS = 0
);
wire [3:0] Nb1s = VD[0]+VD[1]+VD[2]+VD[3]+VD[4]+VD[5]+VD[6]+VD[7];
wire XNOR = (Nb1s>4'd4) || (Nb1s==4'd4 && VD[0]==1'b0);
wire [8:0] q_m = {~XNOR, q_m[6:0] ^ VD[7:1] ^ {7{XNOR}}, VD[0]};
reg [3:0] balance_acc = 0;
wire [3:0] balance = q_m[0]+q_m[1]+q_m[2]+q_m[3]+q_m[4]+q_m[5]+q_m[6]+q_m[7] - 4'd4;
wire balance_sign_eq = (balance[3] == balance_acc[3]);
wire invert_q_m = (balance==0 || balance_acc==0) ? ~q_m[8] : balance_sign_eq;
wire [3:0] balance_acc_inc = balance - ({q_m[8] ^ ~balance_sign_eq} & ~(balance==0 || balance_acc==0));
wire [3:0] balance_acc_new = invert_q_m ? balance_acc-balance_acc_inc : balance_acc+balance_acc_inc;
wire [9:0] TMDS_data = {invert_q_m, q_m[8], q_m[7:0] ^ {8{invert_q_m}}};
wire [9:0] TMDS_code = CD[1] ? (CD[0] ? 10'b1010101011 : 10'b0101010100) : (CD[0] ? 10'b0010101011 : 10'b1101010100);
always @(posedge clk) TMDS <= VDE ? TMDS_data : TMDS_code;
always @(posedge clk) balance_acc <= VDE ? balance_acc_new : 4'h0;
endmodule

////////////////////////////////////////////////////////////////////////
module pll_25 (
	output clkout,
	output clkoutd,
	input  clkin,
	output lock
);
	rPLL pll (
		.CLKOUT(clkout), .CLKOUTD(clkoutd), .CLKIN(clkin),
		.CLKFB(0), .RESET_P(0), .RESET(0),
		.FBDSEL(0), .IDSEL(0), .ODSEL(0),
		.DUTYDA(0), .PSDA(0), .FDLY(0), .LOCK(lock)
	);
	defparam pll.DEVICE = "GW1NR-9";
	defparam pll.FCLKIN = "27";
`ifdef APICULA
	defparam pll.FBDIV_SEL = 36;
	defparam pll.IDIV_SEL  = 3;
	defparam pll.ODIV_SEL  = 4;
`else
	defparam pll.FBDIV_SEL = 36;
	defparam pll.IDIV_SEL  = 7;
	defparam pll.ODIV_SEL  = 8;
`endif
	defparam pll.CLKFB_SEL="internal";      defparam pll.CLKOUTD3_SRC="CLKOUT";
	defparam pll.CLKOUTD_BYPASS="false";    defparam pll.CLKOUTD_SRC="CLKOUT";
	defparam pll.CLKOUTP_BYPASS="false";    defparam pll.CLKOUTP_DLY_STEP=0;
	defparam pll.CLKOUTP_FT_DIR=1'b1;      defparam pll.CLKOUT_BYPASS="false";
	defparam pll.CLKOUT_DLY_STEP=0;        defparam pll.CLKOUT_FT_DIR=1'b1;
	defparam pll.DUTYDA_SEL="1000";        defparam pll.DYN_DA_EN="false";
	defparam pll.DYN_FBDIV_SEL="false";    defparam pll.DYN_IDIV_SEL="false";
	defparam pll.DYN_ODIV_SEL="false";     defparam pll.DYN_SDIV_SEL=10;
	defparam pll.PSDA_SEL="0000";
endmodule

////////////////////////////////////////////////////////////////////////
module clkdiv5 (
	output clkout,
	input  hclkin,
	input  resetn
);
	CLKDIV clkdiv_inst (
		.CLKOUT(clkout), .HCLKIN(hclkin), .RESETN(resetn), .CALIB(0)
	);
	defparam clkdiv_inst.DIV_MODE = "5";
	defparam clkdiv_inst.GSREN = "false";
endmodule
