module CPU(
	input clk, reset, hlt,
	input [63:0] control_bus,
	inout [7:0] data_bus, 
	inout [15:0] address_bus
);
	//wire [7:0] data_bus; 
	//wire [15:0] address_bus;

	//========================= CONTROL UNIT OUTPUTS =====================================
	//Control outputs for Data bus
	wire WE_A, WE_B, WE_R0, WE_R1, WE_IR0, WE_IR1, WE_AR0, WE_AR1, WE_PC0, WE_PC1, WE_SP0, WE_SP1, WE_M;
	wire OE_A, OE_B, OE_R0, OE_R1, OE_IR0, OE_IR1, OE_AR0, OE_AR1, OE_PC0, OE_PC1, OE_SP0, OE_SP1, OE_M;
	wire OE_SR, OE_ALU, PC_INR;
	//Control outputs for address bus
	wire OE_AR, OE_PC, OE_SP, OE_R0R1;
	wire [4:0] alu_opcode, MID, SID; //data bus master/slave ID
	wire [1:0] AMID; //address master ID
	wire sign, zero, parity, carry;

	//Timing outputs
	wire[3:0] T;

	//========================= random wires in CPU =====================================
	wire[7:0] alu_in0, alu_in1, alu_out;
	wire[3:0] alu_status;
	wire[15:0] instr_data;

	//control bus
//	assign {
//	  sign, zero, parity, carry,
//		MID, SID, AMID,
//		alu_opcode, 
//		OE_AR, OE_PC, OE_SP, OE_R0R1,
//		OE_SR, OE_ALU, PC_INR,
//		OE_A, OE_B, OE_R0, OE_R1, OE_IR0, OE_IR1, OE_AR0, OE_AR1, OE_PC0, OE_PC1, OE_SP0, OE_SP1, OE_M,
//		WE_A, WE_B, WE_R0, WE_R1, WE_IR0, WE_IR1, WE_AR0, WE_AR1, WE_PC0, WE_PC1, WE_SP0, WE_SP1, WE_M
//	} = control_bus;
	
	//========================= CPU Registers =====================================

	//Accumulator
	ac_register #(.DATA_WIDTH(8)) AC (
		.clk(clk), .reset(reset),
		.data(data_bus), .data_out(alu_in0),
		.CS(1'b1),.WE(WE_A),.OE(OE_A)
	);
		
	//B register
	ac_register #(.DATA_WIDTH(8)) B_reg (
		.clk(clk), .reset(reset),
		.data(data_bus), .data_out(alu_in1),
		.CS(1'b1),.WE(WE_B),.OE(OE_B)
	);

	//16 bit R0 R1 pair.
	//Can be used to address memory directly
	ar_register #(.ADDR_WIDTH(16)) R1R0_pair(
		.clk(clk), .reset(reset),
		.data(data_bus), .address(address_bus),
		.CS(1'b1),.OE_A(OE_R0R1),
		.WE_H(WE_R1),.OE_H(OE_R1),
		.WE_L(WE_R0),.OE_L(OE_R1)
	);

	//status register
	st_register #(.DATA_WIDTH(4)) status_reg(
		.clk(clk), .reset(reset),
		.data_out(data_bus[3:0]), .data_in(alu_status),
		.CS(1'b1), .WE(~OE_SR), .OE(OE_SR)
	);

	//Instruction register (Connects to instruction decoder)
	ar_register #(.ADDR_WIDTH(16)) instr_reg(
		.clk(clk), .reset(reset),
		.data(data_bus), .address(instr_data),
		.CS(1'b1),.OE_A(1'b1),
		.WE_H(WE_IR1),.OE_H(OE_IR1),
		.WE_L(WE_IR0),.OE_L(OE_IR0)
	);

	//========================= ALU =====================================
	ALU alu(
		.A(alu_in0), .B(alu_in1),
		.opcode(alu_opcode), 
		.C(alu_out), .status(alu_status)
	);
	tri_state_buffer #(.DATA_WIDTH(8)) alu_tsb(
		.data_in(alu_out), .data_out(data_bus),
		.OE(OE_ALU)
	);
	assign {sign, zero, parity, carry} = alu_status;

	//========================= Address Registers =====================================
	//Address register AR
	ar_register #(.ADDR_WIDTH(16)) AR(
		.clk(clk), .reset(reset),
		.data(data_bus), .address(address_bus),
		.CS(1'b1),.OE_A(OE_AR),
		.WE_H(WE_AR1),.OE_H(OE_AR1),
		.WE_L(WE_AR0),.OE_L(OE_AR0)
	);
	//Programme Counter PC
	pc_register #(.ADDR_WIDTH(16)) PC(
		.clk(clk), .reset(reset),
		.data(data_bus), .address(address_bus),
		.CS(1'b1),.OE_A(OE_PC), .CNT_EN(PC_INR),
		.WE_H(WE_PC1),.OE_H(OE_PC1),
		.WE_L(WE_PC0),.OE_L(OE_PC0)
	);
	//Stack pointer SP
	ar_register #(.ADDR_WIDTH(16)) SP(
		.clk(clk), .reset(reset),
		.data(data_bus), .address(address_bus),
		.CS(1'b1),.OE_A(OE_SP),
		.WE_H(WE_SP1),.OE_H(OE_SP1),
		.WE_L(WE_SP0),.OE_L(OE_SP0)
	);
	//========================= PORTS =====================================

	//========================= Memory =====================================
	memory #(.DEPTH(256)) RAM(.clk(clk), .reset(reset), .address(address_bus[14:0]), .data(data_bus), .OE(OE_M), .WE(WE_M), .CS(~address_bus[15]));

	//========================= Control Unit =====================================
	//operates on clk_n
	wire clk_n; //inverted clock
	wire[7:0] control_address; 
	wire[63:0] control_outputs;
	wire CAR_INR = 1'b1;

	assign clk_n = ~clk;

	assign {
		MID, SID, AMID,
		alu_opcode, 
		OE_AR, OE_PC, OE_SP, OE_R0R1,
		OE_SR, OE_ALU, PC_INR,
		OE_A, OE_B, OE_R0, OE_R1, OE_IR0, OE_IR1, OE_AR0, OE_AR1, OE_PC0, OE_PC1, OE_SP0, OE_SP1, OE_M,
		WE_A, WE_B, WE_R0, WE_R1, WE_IR0, WE_IR1, WE_AR0, WE_AR1, WE_PC0, WE_PC1, WE_SP0, WE_SP1, WE_M
	} = control_outputs;

	//Control Address register CAR
	pc_register #(.ADDR_WIDTH(8)) CAR(
		.clk(clk_n), .reset(reset),
		.data(), .address(control_address),
		.CS(1'b1),.OE_A(1'b1), .CNT_EN(CAR_INR),
		.WE_H(1'b0),.OE_H(1'b0),
		.WE_L(1'b0),.OE_L(1'b0)
	);	

	//Control Memory
	memory #(.DEPTH(32), .DATA_WIDTH(64), .ID(1))	control_ROM(
		.clk(clk_n), .reset(1'b1), 
		.address(control_address), 
		.data(control_outputs), .OE(1'b1), .WE(1'b0), .CS(1'b1)
	);
	//========================= Instruction Decoder =====================================


endmodule
