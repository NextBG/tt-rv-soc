/*
 * Copyright (c) 2026 NextBG
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal multi-cycle RV32E core (base integer ISA, 16 registers).
 * FENCE / ECALL / EBREAK / CSR instructions execute as NOPs.
 * Reset vector is 0x00000000. Misaligned accesses are not supported.
 */

`default_nettype none

module rv_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire        mem_valid,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,   // 0 = read
    input  wire [31:0] mem_rdata,
    input  wire        mem_ready
);

  localparam S_FETCH = 2'd0, S_EXEC = 2'd1, S_MEM = 2'd2;

  localparam OP_LUI    = 5'b01101, OP_AUIPC  = 5'b00101, OP_JAL    = 5'b11011,
             OP_JALR   = 5'b11001, OP_BRANCH = 5'b11000, OP_LOAD   = 5'b00000,
             OP_STORE  = 5'b01000, OP_IMM    = 5'b00100, OP_OP     = 5'b01100;

  reg [1:0]  state;
  reg [31:0] pc;
  reg [31:0] ir;
  reg [31:0] ls_addr;
  reg [31:0] ls_wdata;
  reg [3:0]  ls_wstrb;

  reg [31:0] rf [1:15];

  wire _unused = &{ir[1:0], ld_sh[31:16], 1'b0};

  wire [4:0] opcode = ir[6:2];
  wire [3:0] rd     = ir[10:7];
  wire [2:0] f3     = ir[14:12];
  wire [3:0] rs1a   = ir[18:15];
  wire [3:0] rs2a   = ir[23:20];
  wire       f7b5   = ir[30];

  wire [31:0] rs1 = (rs1a == 4'd0) ? 32'd0 : rf[rs1a];
  wire [31:0] rs2 = (rs2a == 4'd0) ? 32'd0 : rf[rs2a];

  wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
  wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
  wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
  wire [31:0] imm_u = {ir[31:12], 12'b0};
  wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

  // ALU: one shared adder/subtractor and one shared right shifter
  wire        is_op     = (opcode == OP_OP);
  wire        is_branch = (opcode == OP_BRANCH);
  wire [31:0] op_b      = (is_op | is_branch) ? rs2 : imm_i;
  wire        use_sub   = is_branch | (is_op & f7b5) | (f3 == 3'd2) | (f3 == 3'd3);
  wire [32:0] addsub    = {1'b0, rs1} + {1'b0, op_b ^ {32{use_sub}}} + {32'd0, use_sub};
  wire        ltu       = ~addsub[32];
  wire        lt        = (rs1[31] ^ op_b[31]) ? rs1[31] : ltu;
  wire        eq        = (addsub[31:0] == 32'd0);
  wire [4:0]  shamt     = op_b[4:0];

  wire        shl       = (f3 == 3'd1);
  wire [31:0] rs1_rev;
  wire [31:0] shr_out;
  wire [31:0] shr_rev;
  genvar g;
  generate
    for (g = 0; g < 32; g = g + 1) begin : g_rev
      assign rs1_rev[g] = rs1[31-g];
      assign shr_rev[g] = shr_out[31-g];
    end
  endgenerate
  wire [31:0] shr_in  = shl ? rs1_rev : rs1;
  wire        shr_fill = f7b5 & ~shl & rs1[31];
  wire [63:0] shr_ext = {{32{shr_fill}}, shr_in} >> shamt;
  assign shr_out = shr_ext[31:0];
  wire _unused_shr = &{shr_ext[63:32], 1'b0};

  reg [31:0] alu;
  always @(*) begin
    case (f3)
      3'd0: alu = addsub[31:0];
      3'd1: alu = shr_rev;
      3'd2: alu = {31'd0, lt};
      3'd3: alu = {31'd0, ltu};
      3'd4: alu = rs1 ^ op_b;
      3'd5: alu = shr_out;
      3'd6: alu = rs1 | op_b;
      default: alu = rs1 & op_b;
    endcase
  end

  reg b_take;
  always @(*) begin
    case (f3)
      3'd0: b_take = eq;
      3'd1: b_take = ~eq;
      3'd4: b_take = lt;
      3'd5: b_take = ~lt;
      3'd6: b_take = ltu;
      3'd7: b_take = ~ltu;
      default: b_take = 1'b0;
    endcase
  end

  wire        is_store = (opcode == OP_STORE);
  wire [31:0] pc4      = pc + 32'd4;
  wire [31:0] agen     = rs1 + (is_store ? imm_s : imm_i);   // load/store address, JALR target
  wire [31:0] pc_off   = (opcode == OP_JAL) ? imm_j : is_branch ? imm_b : imm_u;
  wire [31:0] pc_tgt   = pc + pc_off;

  // Load data extraction
  wire [31:0] ld_sh = mem_rdata >> {ls_addr[1:0], 3'b000};
  reg  [31:0] ld_val;
  always @(*) begin
    case (f3)
      3'd0: ld_val = {{24{ld_sh[7]}}, ld_sh[7:0]};
      3'd1: ld_val = {{16{ld_sh[15]}}, ld_sh[15:0]};
      3'd4: ld_val = {24'd0, ld_sh[7:0]};
      3'd5: ld_val = {16'd0, ld_sh[15:0]};
      default: ld_val = mem_rdata;
    endcase
  end

  assign mem_valid = (state == S_FETCH) || (state == S_MEM);
  assign mem_addr  = (state == S_FETCH) ? pc : ls_addr;
  assign mem_wdata = ls_wdata;
  assign mem_wstrb = (state == S_FETCH) ? 4'b0000 : ls_wstrb;

  reg        wb_en;
  reg [31:0] wb_val;
  always @(*) begin
    wb_en  = 1'b0;
    wb_val = alu;
    if (state == S_EXEC) begin
      case (opcode)
        OP_LUI:   begin wb_en = 1'b1; wb_val = imm_u; end
        OP_AUIPC: begin wb_en = 1'b1; wb_val = pc_tgt; end
        OP_JAL, OP_JALR: begin wb_en = 1'b1; wb_val = pc4; end
        OP_IMM, OP_OP:   begin wb_en = 1'b1; wb_val = alu; end
        default: ;
      endcase
    end else if (state == S_MEM && mem_ready && ls_wstrb == 4'b0000) begin
      wb_en  = 1'b1;
      wb_val = ld_val;
    end
  end

  always @(posedge clk) begin
    if (wb_en && rd != 4'd0) rf[rd] <= wb_val;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state    <= S_FETCH;
      pc       <= 32'd0;
      ir       <= 32'h0000_0013;
      ls_addr  <= 32'd0;
      ls_wdata <= 32'd0;
      ls_wstrb <= 4'd0;
    end else begin
      case (state)
        S_FETCH: if (mem_ready) begin
          ir    <= mem_rdata;
          state <= S_EXEC;
        end
        S_EXEC: begin
          state <= S_FETCH;
          pc    <= pc4;
          case (opcode)
            OP_JAL:    pc <= pc_tgt;
            OP_JALR:   pc <= {agen[31:1], 1'b0};
            OP_BRANCH: if (b_take) pc <= pc_tgt;
            OP_LOAD: begin
              pc       <= pc;
              ls_addr  <= agen;
              ls_wstrb <= 4'b0000;
              state    <= S_MEM;
            end
            OP_STORE: begin
              pc      <= pc;
              ls_addr <= agen;
              state   <= S_MEM;
              case (f3[1:0])
                2'd0: begin
                  ls_wdata <= {4{rs2[7:0]}};
                  ls_wstrb <= 4'b0001 << agen[1:0];
                end
                2'd1: begin
                  ls_wdata <= {2{rs2[15:0]}};
                  ls_wstrb <= agen[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                  ls_wdata <= rs2;
                  ls_wstrb <= 4'b1111;
                end
              endcase
            end
            default: ;
          endcase
        end
        S_MEM: if (mem_ready) begin
          pc    <= pc4;
          state <= S_FETCH;
        end
        default: state <= S_FETCH;
      endcase
    end
  end

endmodule
