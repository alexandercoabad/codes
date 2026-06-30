// =============================================================
//  TYPEWRITER MABUHAY ANG PILIPINAS! — Bitmap Font Display
//  Tang Nano 9K HDMI  |  Top module: HDMI_test
//  Font: custom 8x12 sans-serif (Arial-like), fully readable M
// =============================================================
`default_nettype none
`define APICULA

// =============================================================
//  VGA Sync Generator
// =============================================================
module vga_sync_generator (clk, reset, hsync, vsync, display_on, hpos, vpos);
  input clk, reset;
  output reg hsync, vsync;
  output display_on;
  output reg [9:0] hpos, vpos;

  parameter H_DISPLAY=640, H_BACK=48, H_FRONT=16, H_SYNC=96;
  parameter V_DISPLAY=480, V_TOP=33,  V_BOTTOM=10, V_SYNC=2;
  parameter H_SYNC_START=H_DISPLAY+H_FRONT;
  parameter H_SYNC_END  =H_DISPLAY+H_FRONT+H_SYNC-1;
  parameter H_MAX       =H_DISPLAY+H_BACK+H_FRONT+H_SYNC-1;
  parameter V_SYNC_START=V_DISPLAY+V_BOTTOM;
  parameter V_SYNC_END  =V_DISPLAY+V_BOTTOM+V_SYNC-1;
  parameter V_MAX       =V_DISPLAY+V_TOP+V_BOTTOM+V_SYNC-1;

  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

  always @(posedge clk or posedge reset) begin
    if (reset) begin hpos<=0; vpos<=0; end
    else begin
      if (hpos==H_MAX) begin hpos<=0; vpos<=(vpos==V_MAX)?0:vpos+1; end
      else hpos<=hpos+1;
    end
  end
  always @(posedge clk or posedge reset) begin
    if (reset) begin hsync<=0; vsync<=0; end
    else begin
      hsync <= (hpos>=H_SYNC_START)&&(hpos<=H_SYNC_END);
      vsync <= (vpos>=V_SYNC_START)&&(vpos<=V_SYNC_END);
    end
  end
endmodule

// =============================================================
//  Top Module
// =============================================================
module HDMI_test (
    input  wire        clk,
    input  wire        btn,
    output wire [3:0]  led,
    output wire [2:0]  tmds_d_p, tmds_d_n,
    output wire        tmds_clk_p, tmds_clk_n
);

  wire pixclk, clk_TMDS, lock;

`ifdef APICULA
  wire clk_250;
  pll_25 pll_25_inst (.clkin(clk),.clkout(clk_250),.clkoutd(pixclk),.lock(lock));
  reg clk_250_r = 0;
  always @(posedge clk_250) clk_250_r <= ~clk_250_r;
  assign clk_TMDS = clk_250_r;
`else
  pll_25 pll_25_inst (.clkin(clk),.clkout(clk_TMDS),.clkoutd(),.lock(lock));
  clkdiv5 clkdiv5_inst (.hclkin(clk_TMDS),.clkout(pixclk),.resetn(lock));
`endif

  reg [23:0] frame_counter = 0;
  always @(posedge pixclk) frame_counter <= frame_counter + 1;
  assign led = frame_counter[23:20] ^ {4{btn}};

  reg [3:0] reset_cnt = 0;
  wire sys_rst = !reset_cnt[3];
  always @(posedge pixclk or negedge lock) begin
    if (!lock) reset_cnt <= 0;
    else if (!reset_cnt[3]) reset_cnt <= reset_cnt + 1;
  end

  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  vga_sync_generator vga_sync_gen (
    .clk(pixclk),.reset(sys_rst),
    .hsync(hsync),.vsync(vsync),
    .display_on(video_active),.hpos(pix_x),.vpos(pix_y)
  );

  // -------------------------------------------------------
  // BITMAP FONT DATA
  // "MABUHAY ANG PILIPINAS" — 21 chars, each 8x12 pixels
  // Packed as 21*12*8 = 2016 bits, MSB = top-left of char 0
  // Char order: M A B U H A Y   A N G   P I L I P I N A S
  // Only 24 unique byte values — safe for gowin_pack compression
  // -------------------------------------------------------
  // Now 22 chars (added '!' as index 21, after PILIPINAS) = 22*96 = 2112 bits
  localparam [2111:0] FONT_DATA = 2112'hc3c3e7e7dbdbc3c3c3c300003c66c3c3ffc3c3c3c3c300003f63c3633f63c3c3633f0000c3c3c3c3c3c3c3c3663c0000c3c3c3c3ffc3c3c3c3c300003c66c3c3ffc3c3c3c3c30000c3c3663c18181818181800000000000000000000000000003c66c3c3ffc3c3c3c3c30000c3c7cfdbf3e3c3c3c3c300003c66c30303f3c3c3663c00000000000000000000000000003f63c3c3633f0303030300007e18181818181818187e0000030303030303030303ff00007e18181818181818187e00003f63c3c3633f0303030300007e18181818181818187e0000c3c7cfdbf3e3c3c3c3c300003c66c3c3ffc3c3c3c3c300007cc683031e78c0c1633e0000181818181818181800181800;
  // index 21 = '!' glyph

  // -------------------------------------------------------
  // TYPEWRITER ANIMATION  (single master counter, fully looping)
  //
  // Sequence:
  //   1) Single line "MABUHAY ANG PILIPINAS!" types out, letter by letter.
  //   2) Hold (read the single line for a bit).
  //   3) Switch to 3-line layout: MABUHAY types out on line 1, then ANG on
  //      line 2, then PILIPINAS! on line 3 — typed like a paragraph, none
  //      of the lines disappear once written.
  //   4) Short hold after PILIPINAS! finishes.
  //   5) Loop back to step 1.
  //
  // All timing below is in vsyncs (~60 per second) and easy to retune.
  // -------------------------------------------------------
  localparam CHAR_TICK      = 11'd6;    // vsyncs per letter typed (speed)

  localparam P0_CHARS       = 11'd22;   // "MABUHAY ANG PILIPINAS!" letters
  localparam P0_TYPE_END    = P0_CHARS * CHAR_TICK;                  // 132
  localparam P0_HOLD        = 11'd90;                                // ~1.5s hold after typed
  localparam P0_END         = P0_TYPE_END + P0_HOLD;                 // 222

  localparam L1_CHARS       = 11'd7;    // MABUHAY
  localparam L2_CHARS       = 11'd3;    // ANG
  localparam L3_CHARS       = 11'd10;   // PILIPINAS!
  localparam L1_END         = P0_END + L1_CHARS * CHAR_TICK;         // 222+42=264
  localparam L2_END         = L1_END  + L2_CHARS * CHAR_TICK;        // 264+18=282
  localparam L3_END         = L2_END  + L3_CHARS * CHAR_TICK;        // 282+60=342
  localparam L3_HOLD        = 11'd30;   // short hold after PILIPINAS! finishes
  localparam CYCLE_END      = L3_END + L3_HOLD;                      // 372 -> loop

  reg [10:0] seg_counter = 0;
  always @(posedge vsync or posedge sys_rst) begin
    if (sys_rst) seg_counter <= 0;
    else if (seg_counter >= CYCLE_END) seg_counter <= 0;
    else seg_counter <= seg_counter + 1;
  end

  wire stage0_active = (seg_counter < P0_END);

  // --- Stage 0: single combined line, letter-by-letter ---
  wire [10:0] p0_elapsed = (seg_counter >= P0_TYPE_END) ? P0_TYPE_END : seg_counter;
  wire [4:0]  vis_p0 = p0_elapsed / CHAR_TICK; // chars revealed, caps at 22

  // --- Stage 1: 3-line layout, letter-by-letter, lines chained in sequence ---
  wire [10:0] s1_t = (seg_counter > P0_END) ? (seg_counter - P0_END) : 11'd0;

  wire [4:0] vis_p1 = (s1_t >= L1_CHARS*CHAR_TICK) ? L1_CHARS[4:0] :
                      (s1_t / CHAR_TICK);
  wire [4:0] vis_p2 = (s1_t < L1_CHARS*CHAR_TICK) ? 5'd0 :
                      (s1_t >= L2_CHARS*CHAR_TICK + L1_CHARS*CHAR_TICK) ? L2_CHARS[4:0] :
                      ((s1_t - L1_CHARS*CHAR_TICK) / CHAR_TICK);
  wire [4:0] vis_p3 = (s1_t < L1_CHARS*CHAR_TICK + L2_CHARS*CHAR_TICK) ? 5'd0 :
                      (s1_t >= L1_CHARS*CHAR_TICK + L2_CHARS*CHAR_TICK + L3_CHARS*CHAR_TICK) ? L3_CHARS[4:0] :
                      ((s1_t - L1_CHARS*CHAR_TICK - L2_CHARS*CHAR_TICK) / CHAR_TICK);

  // -------------------------------------------------------
  // FONT DATA  (unchanged — 21 chars packed)
  // Char order in FONT_DATA: M A B U H A Y   A N G   P I L I P I N A S
  //   indices 0-6  = MABUHAY
  //   indices 7    = space
  //   indices 8-10 = ANG
  //   index  11    = space
  //   indices 12-20= PILIPINAS
  // -------------------------------------------------------

  // -------------------------------------------------------
  // LAYOUT CONSTANTS
  // Each glyph: 8 cols * 3px = 24px wide, 12 rows * 3px = 36px tall
  // CHAR_STEP = 26px (24 + 2 gap)
  //
  // Phase 0 (single line):
  //   x_start = 48,  y_start = 222
  //
  // Phase 1 (MABUHAY, 7 chars):
  //   x_start = 230, y_start = 174
  //
  // Phase 2 (ANG, 3 chars):
  //   x_start = 282, y_start = 222  (middle row)
  //
  // Phase 3 (PILIPINAS!, 10 chars):
  //   x_start = 191, y_start = 270   (shifted left 13px to stay centred: 10*26-2=258 wide)
  // -------------------------------------------------------

  // Pixel active row/col for current phase
  // We compute whether (pix_x, pix_y) hits a glyph pixel in the active phase.

  // Helper function: is pixel (px,py) a lit glyph pixel for char index c_idx?
  // char pixel at glyph row fr, col fc:
  //   bit_addr = c_idx*96 + fr*8 + (7-fc)
  //   lit = FONT_DATA[2015 - bit_addr]

  // For each phase, check if pixel falls in that phase's text area.
  // Then extract char index, font row, font col, look up FONT_DATA.

  // --- Phase 0: single centred line (22 chars incl '!') ---
  // x in [35 .. 35+22*26-2=607], y in [222..257]
  wire in_p0_y = (pix_y >= 10'd222) && (pix_y < 10'd258);
  wire in_p0_x = (pix_x >= 10'd35)  && (pix_x < 10'd607);
  wire [9:0] p0_relx = pix_x - 10'd35;
  wire [4:0] p0_char_off = (p0_relx < 10'd26)  ? 5'd0  : (p0_relx < 10'd52)  ? 5'd1  :
                       (p0_relx < 10'd78)  ? 5'd2  : (p0_relx < 10'd104) ? 5'd3  :
                       (p0_relx < 10'd130) ? 5'd4  : (p0_relx < 10'd156) ? 5'd5  :
                       (p0_relx < 10'd182) ? 5'd6  : (p0_relx < 10'd208) ? 5'd7  :
                       (p0_relx < 10'd234) ? 5'd8  : (p0_relx < 10'd260) ? 5'd9  :
                       (p0_relx < 10'd286) ? 5'd10 : (p0_relx < 10'd312) ? 5'd11 :
                       (p0_relx < 10'd338) ? 5'd12 : (p0_relx < 10'd364) ? 5'd13 :
                       (p0_relx < 10'd390) ? 5'd14 : (p0_relx < 10'd416) ? 5'd15 :
                       (p0_relx < 10'd442) ? 5'd16 : (p0_relx < 10'd468) ? 5'd17 :
                       (p0_relx < 10'd494) ? 5'd18 : (p0_relx < 10'd520) ? 5'd19 :
                       (p0_relx < 10'd546) ? 5'd20 : 5'd21;
  // offset 20 -> font index 20 (S of PILIPINAS), offset 21 -> font index 21 ('!')
  wire [4:0] p0_char    = (p0_char_off == 5'd21) ? 5'd21 : p0_char_off;
  wire [9:0] p0_xinchar = p0_relx - p0_char_off * 10'd26;
  wire [9:0] p0_rely    = pix_y - 10'd222;

  // --- Phase 1: MABUHAY, chars 0-6, y=174..209 ---
  wire in_p1_y = (pix_y >= 10'd174) && (pix_y < 10'd210);
  wire in_p1_x = (pix_x >= 10'd230) && (pix_x < 10'd412); // 230+7*26-2=410->412
  wire [9:0] p1_relx = pix_x - 10'd230;
  wire [4:0] p1_char = (p1_relx < 10'd26) ? 5'd0 : (p1_relx < 10'd52) ? 5'd1 :
                       (p1_relx < 10'd78) ? 5'd2 : (p1_relx < 10'd104)? 5'd3 :
                       (p1_relx < 10'd130)? 5'd4 : (p1_relx < 10'd156)? 5'd5 : 5'd6;
  wire [9:0] p1_xinchar = p1_relx - p1_char * 10'd26;
  wire [9:0] p1_rely    = pix_y - 10'd174;

  // --- Phase 2: ANG, chars 8-10 in font, y=222..257 ---
  wire in_p2_y = (pix_y >= 10'd222) && (pix_y < 10'd258);
  wire in_p2_x = (pix_x >= 10'd282) && (pix_x < 10'd360); // 282+3*26-2=358->360
  wire [9:0] p2_relx    = pix_x - 10'd282;
  wire [4:0] p2_char_off= (p2_relx < 10'd26) ? 5'd0 : (p2_relx < 10'd52) ? 5'd1 : 5'd2;
  wire [4:0] p2_char    = p2_char_off + 5'd8; // font indices 8,9,10
  wire [9:0] p2_xinchar = p2_relx - p2_char_off * 10'd26;
  wire [9:0] p2_rely    = pix_y - 10'd222;

  // --- Phase 3: PILIPINAS!, chars 12-20 + '!'=21 in font, y=270..305 ---
  wire in_p3_y = (pix_y >= 10'd270) && (pix_y < 10'd306);
  wire in_p3_x = (pix_x >= 10'd191) && (pix_x < 10'd449); // 191+10*26-2=449
  wire [9:0] p3_relx    = pix_x - 10'd191;
  wire [4:0] p3_char_off= (p3_relx < 10'd26) ? 5'd0 : (p3_relx < 10'd52) ? 5'd1 :
                          (p3_relx < 10'd78) ? 5'd2 : (p3_relx < 10'd104)? 5'd3 :
                          (p3_relx < 10'd130)? 5'd4 : (p3_relx < 10'd156)? 5'd5 :
                          (p3_relx < 10'd182)? 5'd6 : (p3_relx < 10'd208)? 5'd7 :
                          (p3_relx < 10'd234)? 5'd8 : 5'd9;
  // offsets 0-8 -> font indices 12-20 (PILIPINAS), offset 9 -> font index 21 ('!')
  wire [4:0] p3_char    = (p3_char_off == 5'd9) ? 5'd21 : (p3_char_off + 5'd12);
  wire [9:0] p3_xinchar = p3_relx - p3_char_off * 10'd26;
  wire [9:0] p3_rely    = pix_y - 10'd270;

  // -------------------------------------------------------
  // Shared glyph lookup — pick active region
  // Regions occupy disjoint y-ranges, so a simple priority
  // mux based on which area the pixel falls in works fine.
  // Stage 0 area only active during stage0_active; the 3-line
  // areas are active for the rest of time (and stay drawn,
  // never vanishing, since their vis_p* counters hold at max).
  // -------------------------------------------------------
  wire [4:0] cur_char;
  wire [9:0] cur_xinchar, cur_rely;
  wire       cur_in_area;
  wire [4:0] cur_vis;

  wire sel_p0 = stage0_active  && in_p0_x && in_p0_y;
  wire sel_p1 = !stage0_active && in_p1_x && in_p1_y;
  wire sel_p2 = !stage0_active && in_p2_x && in_p2_y;
  wire sel_p3 = !stage0_active && in_p3_x && in_p3_y;

  assign cur_in_area = sel_p0 | sel_p1 | sel_p2 | sel_p3;

  assign cur_char    = sel_p0 ? p0_char :
                       sel_p1 ? p1_char :
                       sel_p2 ? p2_char :
                                p3_char;

  assign cur_xinchar = sel_p0 ? p0_xinchar :
                       sel_p1 ? p1_xinchar :
                       sel_p2 ? p2_xinchar :
                                p3_xinchar;

  assign cur_rely    = sel_p0 ? p0_rely :
                       sel_p1 ? p1_rely :
                       sel_p2 ? p2_rely :
                                p3_rely;

  assign cur_vis     = sel_p0 ? vis_p0 :
                       sel_p1 ? vis_p1 :
                       sel_p2 ? vis_p2 :
                                vis_p3;

  // Typewriter: which char index within its own line is this?
  wire [4:0] char_phase_idx = sel_p0 ? cur_char :
                              sel_p1 ? cur_char :         // 0-6 directly
                              sel_p2 ? cur_char - 5'd8 :  // 0-2
                              (cur_char == 5'd21) ? 5'd9 :       // '!' -> phase idx 9
                                              cur_char - 5'd12;  // 0-8 (PILIPINAS)

  wire char_visible = cur_in_area &&
                      (char_phase_idx < cur_vis) &&
                      (cur_xinchar < 10'd24);

  // Font row/col from pixel position within glyph (3x scale)
  wire [3:0] font_row_v = (cur_rely < 10'd3)  ? 4'd0  : (cur_rely < 10'd6)  ? 4'd1  :
                          (cur_rely < 10'd9)  ? 4'd2  : (cur_rely < 10'd12) ? 4'd3  :
                          (cur_rely < 10'd15) ? 4'd4  : (cur_rely < 10'd18) ? 4'd5  :
                          (cur_rely < 10'd21) ? 4'd6  : (cur_rely < 10'd24) ? 4'd7  :
                          (cur_rely < 10'd27) ? 4'd8  : (cur_rely < 10'd30) ? 4'd9  :
                          (cur_rely < 10'd33) ? 4'd10 : 4'd11;

  wire [2:0] font_col_v = (cur_xinchar < 10'd3)  ? 3'd0 : (cur_xinchar < 10'd6)  ? 3'd1 :
                          (cur_xinchar < 10'd9)  ? 3'd2 : (cur_xinchar < 10'd12) ? 3'd3 :
                          (cur_xinchar < 10'd15) ? 3'd4 : (cur_xinchar < 10'd18) ? 3'd5 :
                          (cur_xinchar < 10'd21) ? 3'd6 : 3'd7;

  wire [11:0] bit_addr  = cur_char * 8'd96 + {font_row_v, 3'b0} + (7 - font_col_v);
  wire        font_pixel = FONT_DATA[2111 - bit_addr];
  wire        text_pixel = char_visible && font_pixel;

  // -------------------------------------------------------
  // COLOUR — Philippine Gold on black
  // -------------------------------------------------------
  reg [7:0] red, green, blue;
  always @(posedge pixclk) begin
    if (video_active && text_pixel) begin
      red   <= 8'hFC;   // #FCD116  Philippine Gold
      green <= 8'hD1;
      blue  <= 8'h16;
    end else begin
      red <= 0; green <= 0; blue <= 0;
    end
  end

  // -------------------------------------------------------
  //  HDMI TMDS SIGNALLING
  // -------------------------------------------------------
  wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
  TMDS_encoder encode_R (.clk(pixclk),.VD(red),  .CD(2'b00),       .VDE(video_active),.TMDS(TMDS_red));
  TMDS_encoder encode_G (.clk(pixclk),.VD(green),.CD(2'b00),       .VDE(video_active),.TMDS(TMDS_green));
  TMDS_encoder encode_B (.clk(pixclk),.VD(blue), .CD({vsync,hsync}),.VDE(video_active),.TMDS(TMDS_blue));

  wire [2:0] tmds_serial;
  wire tmds_serial_clk;
  reg [9:0] TMDS_clk_word = 10'b0000011111;

  OSER10 ser_r (.Q(tmds_serial[2]),
    .D0(TMDS_red[0]),.D1(TMDS_red[1]),.D2(TMDS_red[2]),.D3(TMDS_red[3]),.D4(TMDS_red[4]),
    .D5(TMDS_red[5]),.D6(TMDS_red[6]),.D7(TMDS_red[7]),.D8(TMDS_red[8]),.D9(TMDS_red[9]),
    .PCLK(pixclk),.FCLK(clk_TMDS),.RESET(~lock));
  OSER10 ser_g (.Q(tmds_serial[1]),
    .D0(TMDS_green[0]),.D1(TMDS_green[1]),.D2(TMDS_green[2]),.D3(TMDS_green[3]),.D4(TMDS_green[4]),
    .D5(TMDS_green[5]),.D6(TMDS_green[6]),.D7(TMDS_green[7]),.D8(TMDS_green[8]),.D9(TMDS_green[9]),
    .PCLK(pixclk),.FCLK(clk_TMDS),.RESET(~lock));
  OSER10 ser_b (.Q(tmds_serial[0]),
    .D0(TMDS_blue[0]),.D1(TMDS_blue[1]),.D2(TMDS_blue[2]),.D3(TMDS_blue[3]),.D4(TMDS_blue[4]),
    .D5(TMDS_blue[5]),.D6(TMDS_blue[6]),.D7(TMDS_blue[7]),.D8(TMDS_blue[8]),.D9(TMDS_blue[9]),
    .PCLK(pixclk),.FCLK(clk_TMDS),.RESET(~lock));
  OSER10 ser_clk (.Q(tmds_serial_clk),
    .D0(TMDS_clk_word[0]),.D1(TMDS_clk_word[1]),.D2(TMDS_clk_word[2]),.D3(TMDS_clk_word[3]),.D4(TMDS_clk_word[4]),
    .D5(TMDS_clk_word[5]),.D6(TMDS_clk_word[6]),.D7(TMDS_clk_word[7]),.D8(TMDS_clk_word[8]),.D9(TMDS_clk_word[9]),
    .PCLK(pixclk),.FCLK(clk_TMDS),.RESET(~lock));

  ELVDS_OBUF tmds_bufds[2:0] (.I(tmds_serial),   .O(tmds_d_p),   .OB(tmds_d_n));
  ELVDS_OBUF tmds_clk_bufds  (.I(tmds_serial_clk),.O(tmds_clk_p),.OB(tmds_clk_n));

endmodule

// =============================================================
//  TMDS Encoder
// =============================================================
module TMDS_encoder (input wire clk, input wire [7:0] VD, input wire [1:0] CD,
                     input wire VDE, output reg [9:0] TMDS = 0);
  wire [3:0] Nb1s = VD[0]+VD[1]+VD[2]+VD[3]+VD[4]+VD[5]+VD[6]+VD[7];
  wire XNOR = (Nb1s>4'd4)||(Nb1s==4'd4&&VD[0]==1'b0);
  wire [8:0] q_m = {~XNOR,q_m[6:0]^VD[7:1]^{7{XNOR}},VD[0]};
  reg [3:0] balance_acc=0;
  wire [3:0] balance=q_m[0]+q_m[1]+q_m[2]+q_m[3]+q_m[4]+q_m[5]+q_m[6]+q_m[7]-4'd4;
  wire balance_sign_eq=(balance[3]==balance_acc[3]);
  wire invert_q_m=(balance==0||balance_acc==0)?~q_m[8]:balance_sign_eq;
  wire [3:0] balance_acc_inc=balance-({q_m[8]^~balance_sign_eq}&~(balance==0||balance_acc==0));
  wire [3:0] balance_acc_new=invert_q_m?balance_acc-balance_acc_inc:balance_acc+balance_acc_inc;
  wire [9:0] TMDS_data={invert_q_m,q_m[8],q_m[7:0]^{8{invert_q_m}}};
  wire [9:0] TMDS_code=CD[1]?(CD[0]?10'b1010101011:10'b0101010100):(CD[0]?10'b0010101011:10'b1101010100);
  always @(posedge clk) TMDS<=VDE?TMDS_data:TMDS_code;
  always @(posedge clk) balance_acc<=VDE?balance_acc_new:4'h0;
endmodule

// =============================================================
//  PLL
// =============================================================
module pll_25 (output wire clkout, output wire clkoutd, input wire clkin, output wire lock);
  rPLL pll (.CLKOUT(clkout),.CLKOUTD(clkoutd),.CLKIN(clkin),.CLKFB(1'b0),
            .RESET_P(1'b0),.RESET(1'b0),.FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),
            .DUTYDA(4'b0),.PSDA(4'b0),.FDLY(4'b0),.LOCK(lock));
  defparam pll.DEVICE="GW1NR-9"; defparam pll.FCLKIN="27";
`ifdef APICULA
  defparam pll.FBDIV_SEL=36; defparam pll.IDIV_SEL=3; defparam pll.ODIV_SEL=4;
`else
  defparam pll.FBDIV_SEL=36; defparam pll.IDIV_SEL=7; defparam pll.ODIV_SEL=8;
`endif
  defparam pll.CLKFB_SEL="internal";   defparam pll.CLKOUTD3_SRC="CLKOUT";
  defparam pll.CLKOUTD_BYPASS="false"; defparam pll.CLKOUTD_SRC="CLKOUT";
  defparam pll.CLKOUTP_BYPASS="false"; defparam pll.CLKOUTP_DLY_STEP=0;
  defparam pll.CLKOUTP_FT_DIR=1'b1;   defparam pll.CLKOUT_BYPASS="false";
  defparam pll.CLKOUT_DLY_STEP=0;     defparam pll.CLKOUT_FT_DIR=1'b1;
  defparam pll.DUTYDA_SEL="1000";     defparam pll.DYN_DA_EN="false";
  defparam pll.DYN_FBDIV_SEL="false"; defparam pll.DYN_IDIV_SEL="false";
  defparam pll.DYN_ODIV_SEL="false";  defparam pll.DYN_SDIV_SEL=10;
  defparam pll.PSDA_SEL="0000";
endmodule

module clkdiv5 (output wire clkout, input wire hclkin, input wire resetn);
  CLKDIV clkdiv_inst (.CLKOUT(clkout),.HCLKIN(hclkin),.RESETN(resetn),.CALIB(1'b0));
  defparam clkdiv_inst.DIV_MODE="5"; defparam clkdiv_inst.GSREN="false";
endmodule
