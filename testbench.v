`timescale 1ns/1ps
//------------------------------------------------------------------------------
// tb_riscv.v - Self-checking testbench for riscv_top
//
// Program (byte address : instruction)
//   00: addi x1,  x0, 5          x1  = 5
//   04: addi x2,  x0, 10         x2  = 10
//   08: add  x3,  x1, x2         x3  = 15
//   0C: sub  x4,  x2, x1         x4  = 5
//   10: and  x5,  x1, x2         x5  = 0
//   14: or   x6,  x1, x2         x6  = 15
//   18: xor  x7,  x1, x2         x7  = 15
//   1C: slli x8,  x1, 3          x8  = 40
//   20: sw   x3,  0(x0)          mem[0] = 15
//   24: lw   x9,  0(x0)          x9  = 15
//   28: beq  x9,  x3, +8         taken -> skips 2C
//   2C: addi x10, x0, 1          (skipped, x10 stays 0)
//   30: addi x11, x0, 99         x11 = 99
//   34: jal  x12, +8             x12 = 0x38, skips 38
//   38: addi x13, x0, 1          (skipped, x13 stays 0)
//   3C: lui  x14, 0x12345        x14 = 0x12345000
//   40: auipc x15, 1             x15 = 0x40 + 0x1000 = 0x1040
//   44: addi x17, x0, 80         x17 = 0x50
//   48: jalr x16, 0(x17)         x16 = 0x4C, jumps to 0x50, skips 4C
//   4C: addi x19, x0, 1          (skipped, x19 stays 0)
//   50: jal  x0, 0               end-of-program loop
//------------------------------------------------------------------------------
module tb_riscv;

    reg         clk;
    reg         rst;
    wire [31:0] pc_out;
    wire [31:0] wb_data_out;
    integer     errors;

    riscv_top dut (
        .clk         (clk),
        .rst         (rst),
        .pc_out      (pc_out),
        .wb_data_out (wb_data_out)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Per-cycle trace
    always @(posedge clk) begin
        if (!rst)
            $display("t=%0t  pc=%h  instr=%h  wb=%h",
                     $time, pc_out, dut.instr, wb_data_out);
    end

    task check_reg;
        input [4:0]  idx;
        input [31:0] expected;
        begin
            if (dut.u_regfile.regs[idx] !== expected) begin
                $display("FAIL: x%0d = %h, expected %h",
                         idx, dut.u_regfile.regs[idx], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: x%0d = %h", idx, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_riscv.vcd");
        $dumpvars(0, tb_riscv);

        errors = 0;
        rst    = 1'b1;

        // Load program (after the memory's own initial block has run)
        #1;
        dut.u_imem.mem[0]  = 32'h00500093;  // addi x1,  x0, 5
        dut.u_imem.mem[1]  = 32'h00A00113;  // addi x2,  x0, 10
        dut.u_imem.mem[2]  = 32'h002081B3;  // add  x3,  x1, x2
        dut.u_imem.mem[3]  = 32'h40110233;  // sub  x4,  x2, x1
        dut.u_imem.mem[4]  = 32'h0020F2B3;  // and  x5,  x1, x2
        dut.u_imem.mem[5]  = 32'h0020E333;  // or   x6,  x1, x2
        dut.u_imem.mem[6]  = 32'h0020C3B3;  // xor  x7,  x1, x2
        dut.u_imem.mem[7]  = 32'h00309413;  // slli x8,  x1, 3
        dut.u_imem.mem[8]  = 32'h00302023;  // sw   x3,  0(x0)
        dut.u_imem.mem[9]  = 32'h00002483;  // lw   x9,  0(x0)
        dut.u_imem.mem[10] = 32'h00348463;  // beq  x9,  x3, +8
        dut.u_imem.mem[11] = 32'h00100513;  // addi x10, x0, 1   (skipped)
        dut.u_imem.mem[12] = 32'h06300593;  // addi x11, x0, 99
        dut.u_imem.mem[13] = 32'h0080066F;  // jal  x12, +8
        dut.u_imem.mem[14] = 32'h00100693;  // addi x13, x0, 1   (skipped)
        dut.u_imem.mem[15] = 32'h12345737;  // lui  x14, 0x12345
        dut.u_imem.mem[16] = 32'h00001797;  // auipc x15, 1
        dut.u_imem.mem[17] = 32'h05000893;  // addi x17, x0, 80
        dut.u_imem.mem[18] = 32'h00088867;  // jalr x16, 0(x17)
        dut.u_imem.mem[19] = 32'h00100993;  // addi x19, x0, 1   (skipped)
        dut.u_imem.mem[20] = 32'h0000006F;  // jal  x0, 0        (halt loop)

        // Reset pulse
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        // Run long enough for the program to reach the halt loop
        repeat (30) @(posedge clk);
        #1;

        $display("---- Register check ----");
        check_reg(5'd0,  32'h00000000);
        check_reg(5'd1,  32'h00000005);
        check_reg(5'd2,  32'h0000000A);
        check_reg(5'd3,  32'h0000000F);
        check_reg(5'd4,  32'h00000005);
        check_reg(5'd5,  32'h00000000);
        check_reg(5'd6,  32'h0000000F);
        check_reg(5'd7,  32'h0000000F);
        check_reg(5'd8,  32'h00000028);
        check_reg(5'd9,  32'h0000000F);
        check_reg(5'd10, 32'h00000000);
        check_reg(5'd11, 32'h00000063);
        check_reg(5'd12, 32'h00000038);
        check_reg(5'd13, 32'h00000000);
        check_reg(5'd14, 32'h12345000);
        check_reg(5'd15, 32'h00001040);
        check_reg(5'd16, 32'h0000004C);
        check_reg(5'd17, 32'h00000050);
        check_reg(5'd19, 32'h00000000);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule