//------------------------------------------------------------------------------
// riscv_top.v - RV32I single-cycle processor (Harvard architecture)
//------------------------------------------------------------------------------
module riscv_top (
    input  wire        clk,
    input  wire        rst,            // synchronous, active-high
    output wire [31:0] pc_out,         // debug: current PC
    output wire [31:0] wb_data_out     // debug: current write-back value
);

    // Write-back select encodings
    localparam [1:0] WB_ALU = 2'd0;
    localparam [1:0] WB_MEM = 2'd1;
    localparam [1:0] WB_PC4 = 2'd2;

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    wire [31:0] pc, pc_plus4, pc_target, jalr_target, pc_next;
    wire [31:0] instr, imm;
    wire [31:0] rs1_data, rs2_data;
    wire [31:0] alu_a, alu_b, alu_result;
    wire [31:0] dmem_rdata;
    reg  [31:0] wb_data;

    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];

    wire        reg_write, alu_src_a, alu_src_b, mem_write;
    wire        branch, jal, jalr, cond_met, branch_taken;
    wire [1:0]  wb_sel;
    wire [3:0]  alu_ctrl;

    //--------------------------------------------------------------------------
    // Fetch
    //--------------------------------------------------------------------------
    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .pc_next (pc_next),
        .pc_out  (pc)
    );

    instr_mem u_imem (
        .addr  (pc),
        .instr (instr)
    );

    //--------------------------------------------------------------------------
    // Decode
    //--------------------------------------------------------------------------
    control_unit u_ctrl (
        .opcode    (opcode),
        .funct3    (funct3),
        .funct7    (funct7),
        .reg_write (reg_write),
        .alu_src_a (alu_src_a),
        .alu_src_b (alu_src_b),
        .mem_write (mem_write),
        .wb_sel    (wb_sel),
        .branch    (branch),
        .jal       (jal),
        .jalr      (jalr),
        .alu_ctrl  (alu_ctrl)
    );

    imm_gen u_immgen (
        .instr (instr),
        .imm   (imm)
    );

    regfile u_regfile (
        .clk      (clk),
        .rst      (rst),
        .we       (reg_write),
        .rs1_addr (rs1),
        .rs2_addr (rs2),
        .rd_addr  (rd),
        .rd_data  (wb_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    //--------------------------------------------------------------------------
    // Execute
    //--------------------------------------------------------------------------
    assign alu_a = alu_src_a ? pc  : rs1_data;
    assign alu_b = alu_src_b ? imm : rs2_data;

    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result)
    );

    branch_unit u_branch (
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .funct3   (funct3),
        .cond_met (cond_met)
    );

    //--------------------------------------------------------------------------
    // Memory
    //--------------------------------------------------------------------------
    data_mem u_dmem (
        .clk   (clk),
        .we    (mem_write),
        .addr  (alu_result),
        .wdata (rs2_data),
        .rdata (dmem_rdata)
    );

    //--------------------------------------------------------------------------
    // Write-back mux (combinational)
    //--------------------------------------------------------------------------
    always @(*) begin
        case (wb_sel)
            WB_ALU:  wb_data = alu_result;
            WB_MEM:  wb_data = dmem_rdata;
            WB_PC4:  wb_data = pc_plus4;
            default: wb_data = alu_result;
        endcase
    end

    //--------------------------------------------------------------------------
    // Next-PC logic (combinational)
    //--------------------------------------------------------------------------
    assign pc_plus4     = pc + 32'd4;
    assign pc_target    = pc + imm;
    assign jalr_target  = {alu_result[31:1], 1'b0};
    assign branch_taken = branch & cond_met;

    assign pc_next = jalr                ? jalr_target :
                     (jal | branch_taken) ? pc_target   :
                                           pc_plus4;

    //--------------------------------------------------------------------------
    // Debug outputs
    //--------------------------------------------------------------------------
    assign pc_out      = pc;
    assign wb_data_out = wb_data;

endmodule

// =============================================================================
// Submodules
// =============================================================================

module pc (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_out
);
    always @(posedge clk) begin
        if (rst)
            pc_out <= 32'b0;
        else
            pc_out <= pc_next;
    end
endmodule

module instr_mem (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    reg [31:0] mem [0:1023];

    assign instr = mem[addr[11:2]];
endmodule

module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] regs [0:31];
    integer i;

    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : regs[rs2_addr];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end
endmodule

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            7'b0010011, // I-type ALU
            7'b0000011, // I-type Load
            7'b1100111: // I-type JALR
                imm = {{20{instr[31]}}, instr[31:20]};

            7'b0100011: // S-type Store
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            7'b1100011: // B-type Branch
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

            7'b0110111, // U-type LUI
            7'b0010111: // U-type AUIPC
                imm = {instr[31:12], 12'b0};

            7'b1101111: // J-type JAL
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

            default:
                imm = 32'b0;
        endcase
    end
endmodule

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        alu_src_a,
    output reg        alu_src_b,
    output reg        mem_write,
    output reg  [1:0] wb_sel,
    output reg        branch,
    output reg        jal,
    output reg        jalr,
    output reg  [3:0] alu_ctrl
);
    localparam [1:0] WB_ALU = 2'd0;
    localparam [1:0] WB_MEM = 2'd1;
    localparam [1:0] WB_PC4 = 2'd2;

    always @(*) begin
        reg_write = 1'b0;
        alu_src_a = 1'b0;
        alu_src_b = 1'b0;
        mem_write = 1'b0;
        wb_sel    = WB_ALU;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;
        alu_ctrl  = 4'b0000;

        case (opcode)
            7'b0110011: begin // R-type
                reg_write = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b0;
                wb_sel    = WB_ALU;
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? 4'b0001 : 4'b0000; // sub : add
                    3'b001: alu_ctrl = 4'b0101;                         // sll
                    3'b010: alu_ctrl = 4'b1000;                         // slt
                    3'b011: alu_ctrl = 4'b1001;                         // sltu
                    3'b100: alu_ctrl = 4'b0100;                         // xor
                    3'b101: alu_ctrl = (funct7[5]) ? 4'b0111 : 4'b0110; // sra : srl
                    3'b110: alu_ctrl = 4'b0011;                         // or
                    3'b111: alu_ctrl = 4'b0010;                         // and
                    default: alu_ctrl = 4'b0000;
                endcase
            end

            7'b0010011: begin // I-type ALU
                reg_write = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                wb_sel    = WB_ALU;
                case (funct3)
                    3'b000: alu_ctrl = 4'b0000;                         // addi
                    3'b001: alu_ctrl = 4'b0101;                         // slli
                    3'b010: alu_ctrl = 4'b1000;                         // slti
                    3'b011: alu_ctrl = 4'b1001;                         // sltiu
                    3'b100: alu_ctrl = 4'b0100;                         // xori
                    3'b101: alu_ctrl = (funct7[5]) ? 4'b0111 : 4'b0110; // srai : srli
                    3'b110: alu_ctrl = 4'b0011;                         // ori
                    3'b111: alu_ctrl = 4'b0010;                         // andi
                    default: alu_ctrl = 4'b0000;
                endcase
            end

            7'b0000011: begin // lw
                reg_write = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                alu_ctrl  = 4'b0000;
                wb_sel    = WB_MEM;
                mem_write = 1'b0;
            end

            7'b0100011: begin // sw
                reg_write = 1'b0;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                alu_ctrl  = 4'b0000;
                mem_write = 1'b1;
            end

            7'b1100011: begin // Branch
                branch = 1'b1;
            end

            7'b1101111: begin // jal
                reg_write = 1'b1;
                jal       = 1'b1;
                wb_sel    = WB_PC4;
            end

            7'b1100111: begin // jalr
                reg_write = 1'b1;
                jalr      = 1'b1;
                alu_src_a = 1'b0;
                alu_src_b = 1'b1;
                alu_ctrl  = 4'b0000;
                wb_sel    = WB_PC4;
            end

            7'b0110111: begin // lui
                reg_write = 1'b1;
                alu_src_b = 1'b1;
                alu_ctrl  = 4'b1010; // pass imm
                wb_sel    = WB_ALU;
            end

            7'b0010111: begin // auipc
                reg_write = 1'b1;
                alu_src_a = 1'b1;    // PC
                alu_src_b = 1'b1;    // imm
                alu_ctrl  = 4'b0000; // PC + imm
                wb_sel    = WB_ALU;
            end

            default: ;
        endcase
    end
endmodule

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] result
);
    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a & b;
            4'b0011: result = a | b;
            4'b0100: result = a ^ b;
            4'b0101: result = a << b[4:0];
            4'b0110: result = a >> b[4:0];
            4'b0111: result = $signed(a) >>> b[4:0];
            4'b1000: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            4'b1001: result = (a < b) ? 32'd1 : 32'd0;
            4'b1010: result = b;
            default: result = 32'b0;
        endcase
    end
endmodule

module branch_unit (
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  funct3,
    output reg         cond_met
);
    always @(*) begin
        case (funct3)
            3'b000: cond_met = (rs1_data == rs2_data);                     // beq
            3'b001: cond_met = (rs1_data != rs2_data);                     // bne
            3'b100: cond_met = ($signed(rs1_data) < $signed(rs2_data));     // blt
            3'b101: cond_met = ($signed(rs1_data) >= $signed(rs2_data));    // bge
            3'b110: cond_met = (rs1_data < rs2_data);                       // bltu
            3'b111: cond_met = (rs1_data >= rs2_data);                      // bgeu
            default: cond_met = 1'b0;
        endcase
    end
endmodule

module data_mem (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    reg [31:0] dmem [0:1023];

    assign rdata = dmem[addr[11:2]];

    always @(posedge clk) begin
        if (we)
            dmem[addr[11:2]] <= wdata;
    end
endmodule