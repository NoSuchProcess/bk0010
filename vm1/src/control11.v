// =======================================================
// 1801VM1 SOFT CPU
// Copyright(C)2005 Alex Freed, 2008 Viacheslav Slavinsky
// Based on original POP-11 design (C)2004 Yoshihiro Iida
//
// Distributed under the terms of Modified BSD License
// ========================================================
// LSI-11 Control Chip
// --------------------------------------------------------

`default_nettype none
`include "instr.h"
`include "opc.h"

module 	control11(clk, 
				ce, 
				reset_n, 
				dpcmd, 
				ierror, 
				ready, 
				dati,
				dato,
				mbyte, 
			    dp_opcode,
				dp_taken,
				dp_alucc,
				psw,	
				ifetch,			
				irq_in,
				iako,
				idcop,
				idc_cco, 
				idc_bra, 
				idc_nof, 
				idc_rsd, 
				idc_dop, 
				idc_sop, 
				idc_unused,
				initq, 
				test);
				
input 				clk;
input				ce;
input				reset_n;
output	reg	[127:0]	dpcmd;
input				ierror, ready;
input				dp_taken;
input 		[15:0]	dp_opcode;
input		 [3:0]	dp_alucc;
input		[15:0]	psw;
output	reg			ifetch;
input				irq_in;
output	reg			iako;
input[`IDC_NOPS:0] 	idcop;
output	reg			dati, dato;
output  reg 		mbyte;
input 				idc_cco, idc_bra, idc_nof, idc_rsd, idc_dop, idc_sop, idc_unused;
output	reg			initq;

output		[7:0]	test = state;

parameter [5:0]	BOOT_0 = 0,
				FS_IF0 = 1,
				FS_IF1 = 2,
				FS_ID0 = 3,
				FS_ID1 = 4,
				FS_OF0 = 5,
				FS_OF1 = 6,
				FS_OF2 = 7,
				FS_OF3 = 8,
				FS_OF4 = 9,
				FS_BR0 = 10,
				FS_CC0 = 11,
		
				EX_0 = 16,
				EX_1 = 17,
				EX_2 = 18,
				EX_3 = 19,
				EX_4 = 20,
				EX_5 = 21,
				EX_6 = 22,
				EX_7 = 23,
				EX_8 = 24,
				
				WB_0 = 32,

				TRAP_1 = 49,
				TRAP_2 = 50,
				TRAP_3 = 51,
				TRAP_4 = 52,
				TRAP_IRQ = 55,
				TRAP_SVC = 56;

reg [5:0] state;

parameter SRC_OP = 1'b0,
		  DST_OP = 1'b1;
reg opsrcdst;

wire [1:0] 	MODE = dp_opcode[5:4];
wire 		INDR = dp_opcode[3];
wire		SPPC = dp_opcode[2] & dp_opcode[1];
wire	AUTO_INC = dp_opcode[4];
wire	AUTO_DEC = dp_opcode[5];
wire	    BYTE = dp_opcode[15];
wire		TRACE= psw[4]; 

`define dp(x) dpcmd[x] <= 1'b1

reg		rsub;


// fetch task
always @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		state <= BOOT_0;
		opsrcdst <= SRC_OP;
		{dati,dato,iako,initq,ifetch} <= 0;
	end
	else if (ce) begin
		{dati,dato} <= 0;
		dpcmd <= 128'b0;
		//dpcmd[`DBAPC] <= 1'bx;
		initq <= 1'b0;
		iako <= 1'b0;
		ifetch <= 1'b0;
		
		case (state)
		BOOT_0: begin
					`dp(`SETPCROM);
					state <= FS_IF0;
				end
		FS_IF0:	begin 
					// fixme: should be _before_ if0
					
					if (~TRACE & irq_in) 
						state <= TRAP_IRQ;
					else if (TRACE) begin 
						`dp(`BPT);	state <= TRAP_SVC; 
					end 
					else begin
						mbyte <= 0;
						ifetch <= 1'b1;
						`dp(`DBAPC);
						dati <= 1;

						if (ierror) begin
							dati <= 1'b0;
							state <= TRAP_SVC;
							`dp(`BUSERR);
						end else if (ready) begin
							state <= FS_ID0;
							
							dati <= 1'b0;
							`dp(`PCALU1);
							`dp(`INC2);
							`dp(`ALUPC);
							`dp(`SETOPC);
						end 
					end
				end
				
				// Instruction Decode #0
		FS_ID0:	begin
					if (idc_unused) begin
						`dp(`ERR);
						state <= TRAP_SVC;
					end else if (idc_rsd) begin
						`dp(`CHANGE_OPR);
						opsrcdst <= DST_OP;
						state <= FS_OF0;
					end else if (idc_nof) begin
						state <= EX_0;
					end else if (idc_cco) begin
						state <= FS_CC0;
					end else if (idc_bra) begin
						`dp(`CCTAKEN); // latch condition 
						state <= FS_BR0;
					end else if (idc_sop) begin
						`dp(`CHANGE_OPR);
						opsrcdst <= SRC_OP;
						state <= FS_OF1;
					end else if (idc_dop) begin
						opsrcdst <= DST_OP;
						state <= FS_OF1;
					end
					
					if (idcop[`dadd]) begin
						rsub <= 1'b0;
					end 
					else if (idcop[`dsub]) begin
						rsub <= 1'b1; `dp(`RESET_BYTE);
					end
				end
				
				// direct register read
		FS_OF0:	begin
					`dp(`REGSEL);
					`dp(`SELSRC);
					`dp(`CHANGE_OPR);
					
					state <= FS_OF1;
				end
				
				// Operand Fetch #1
		FS_OF1: begin
					case (MODE) 
					2'b 00: begin
							`dp(opsrcdst == SRC_OP ? `SELSRC : `SELDST);
							`dp(`REGSEL);
							
							if (INDR) state <= FS_OF4;
							else if (opsrcdst == DST_OP) begin 
								state <= EX_0;
							end 
							else if (opsrcdst == SRC_OP) begin
								opsrcdst <= DST_OP;
								`dp(`CHANGE_OPR);
								state <= FS_OF1; // fetch other operand
							end
							end
							
					2'b 01:	begin
							`dp(`REGSEL); `dp(`SELALU1);
							`dp(`ALUREG); `dp(`SETREG);
							if (BYTE & ~(INDR|SPPC)) `dp(`INC);
							if (~BYTE | (INDR|SPPC)) `dp(`INC2);
							`dp(opsrcdst == SRC_OP ? `SELSRC : `SELDST);
							state <= FS_OF3;
							end
							
					2'b 10: begin
							`dp(`REGSEL); `dp(`SELALU1);
							`dp(`ALUREG); `dp(`SETREG);
							if (BYTE & ~(INDR|SPPC)) `dp(`DEC);
							if (~BYTE | (INDR|SPPC)) `dp(`DEC2);
							`dp(opsrcdst == SRC_OP ? `ALUSRC : `ALUDST);
							state <= FS_OF3;
							end
							
					2'b 11: begin
							`dp(`DBAPC);
							dati <= 1;
							mbyte <= 0;

							if (ierror) begin
								state <= TRAP_SVC;		
								`dp(`BUSERR);
							end else if (ready) begin
								dati <= 0;
								`dp(`PCALU1);	`dp(`INC2); `dp(`ALUPC);
								`dp(opsrcdst == SRC_OP ? `DBISRC : `DBIDST);
								state <= FS_OF2;
							end 
							
							end
					endcase
				end
				
				// Computes effective address in index mode
		FS_OF2: begin
				`dp(`REGSEL); `dp(`SELALU1); `dp(`ADD);
				if (opsrcdst == SRC_OP) begin 
					`dp(`SRCALU2); `dp(`ALUSRC);
				end
				if (opsrcdst == DST_OP) begin
					`dp(`DSTALU2); `dp(`ALUDST);
				end
				
				state <= FS_OF3;
				end
				
				// First step memory read. Used by Auto-inc,dec,index mode.
		FS_OF3: begin
				mbyte <= INDR ? 1'b0 : BYTE;
				//mbyte <= !INDR;
				//mbyte <= BYTE;
				
				dati <= 1'b1;
				`dp(opsrcdst == SRC_OP ? `DBASRC : `DBADST);

				if (ierror) begin
					state <= TRAP_SVC;
					`dp(`BUSERR);
				end else if (ready) begin
					dati <= 0;
					
					if (opsrcdst == DST_OP) begin
						`dp(`DBIDST); `dp(`DSTADR);
					end else begin
						`dp(`DBISRC); `dp(`SRCADR);
					end
					
					if (INDR) 
						state <= FS_OF4;
					else if (opsrcdst == DST_OP) begin
						state <= EX_0;
					end else begin
						`dp(`CHANGE_OPR);
						opsrcdst <= DST_OP;
						state <= FS_OF1;
					end
				end 
				
				end
				
				// Deferred instruction
		FS_OF4:	begin
				
				if (opsrcdst == DST_OP) begin
					mbyte <= BYTE;
					dati <= 1'b1;
					`dp(`DBADST); 
					if (ierror) begin
						dati <= 1'b0;
						`dp(`BUSERR);
						state <= TRAP_SVC;
					end 
					else if (ready) begin
						dati <= 1'b0;
						`dp(`DSTADR); `dp(`DBIDST);
						state <= EX_0;
					end
				end else begin		// SRC
					mbyte <= BYTE;
					`dp(`DBASRC);
					dati <= 1'b1;
					
					if (ierror) begin
						dati <= 1'b0;
						`dp(`BUSERR);
						state <= TRAP_SVC;
					end
					else if (ready) begin
						dati <= 1'b0;
						`dp(`SRCADR); `dp(`DBISRC);
						`dp(`CHANGE_OPR);
						opsrcdst <= DST_OP;
						state <= FS_OF1;
					end
				end
				
				end
		
		FS_CC0:	begin
					`dp(`CCSET);
					
					state <= FS_IF0;
					if (~TRACE & irq_in) state <= TRAP_IRQ;
					if (TRACE) begin `dp(`BPT);	state <= TRAP_SVC; end
				end
				
		FS_BR0:	begin
					//`dp(`CCTAKEN); // latch condition -- see ID0
					if (dp_taken) begin
						`dp(`PCALU1); `dp(`OFS8ALU2); 
						`dp(`ADD); `dp(`ALUPC);
					end
					
					state <= FS_IF0;
					if (~TRACE & irq_in) state <= TRAP_IRQ;
					if (TRACE) begin `dp(`BPT);	state <= TRAP_SVC; end
				end
		// ifetch states end here
		
		// execution states
				
		EX_0,EX_1,EX_2,EX_3,EX_4,EX_5,EX_6,EX_7,EX_8: 	
				begin
					// set datapath to execute decoded instruction
					case (1'b 1) // synopsys parallel_case
					idcop[`dclr]: begin `dp(`DSTALU1); `dp(`CLR); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dcom]: begin	`dp(`DSTALU1); `dp(`COM); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dinc]: begin `dp(`DSTALU1); `dp(`INC); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`ddec]: begin `dp(`DSTALU1); `dp(`DEC); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dneg]: begin `dp(`DSTALU1); `dp(`NEG); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dadc]: begin `dp(`DSTALU1); `dp(`ADC); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dsbc]: begin `dp(`DSTALU1); `dp(`SBC); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dtst]: begin `dp(`DSTALU1); `dp(`TST); `dp(`ALUCC); state <= FS_IF0; end
					idcop[`dror]: begin `dp(`DSTALU1); `dp(`ROR); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`drol]: begin `dp(`DSTALU1); `dp(`ROL); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dasr]: begin `dp(`DSTALU1); `dp(`ASR); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dasl]: begin `dp(`DSTALU1); `dp(`ASL); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dsxt]: begin `dp(`DSTALU1); `dp(`SXT); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					
					idcop[`dmov]: begin `dp(`SRCALU1); `dp(`MOV);     `dp(`ALUDST); `dp(`ALUCC); state <= WB_0; end
					
					idcop[`dcmp]: begin `dp(`SRCALU1); `dp(`DSTALU2); `dp(`CMP);    `dp(`ALUCC); state <= FS_IF0; end
					idcop[`dbit]: begin `dp(`SRCALU1); `dp(`DSTALU2); `dp(`BIT);    `dp(`ALUCC); state <= FS_IF0; end
					idcop[`dbic]: begin `dp(`SRCALU1); `dp(`DSTALU2); `dp(`BIC);    `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dbis]: begin `dp(`SRCALU1); `dp(`DSTALU2); `dp(`BIS);    `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dadd]: 
								if (!rsub) begin
									`dp(`SRCALU1); `dp(`DSTALU2); `dp(`ADD); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; 
								end else begin
									`dp(`SRCALU2); `dp(`DSTALU1); `dp(`SUB); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; 
								end
					idcop[`dexor]:begin `dp(`SRCALU1); `dp(`DSTALU2); `dp(`EXOR); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end
					idcop[`dswab]: begin `dp(`SRCALU1); `dp(`SWAB); `dp(`ALUDSTB); `dp(`ALUCC); state <= WB_0; end

					idcop[`dnop]: begin state <= FS_IF0; end
					idcop[`djmp]: begin `dp(`ADRPC); state <= FS_IF0; end

					idcop[`dbpt]: begin `dp(`BPT); state <= TRAP_SVC; end
					idcop[`diot]: begin `dp(`IOT); state <= TRAP_SVC; end
					idcop[`demt]: begin `dp(`EMT); state <= TRAP_SVC; end
					idcop[`dtrap]:begin `dp(`SVC); state <= TRAP_SVC; end

					idcop[`dspl]: begin `dp(`SPL); state <= FS_IF0; end
					
					idcop[`dreset]: begin initq <= 1'b1; state <= FS_IF0; end

					idcop[`dhalt]: begin `dp(`BUSERR); state <= TRAP_SVC; end // should be `dp(`HALT)?

					idcop[`diwait]: if (irq_in) state <= FS_IF0; // ? not TRAP_IRQ?
								
					
					idcop[`dsob]: begin
									case (state) // synopsys parallel_case
									EX_0: begin
											`dp(`REGSEL2); `dp(`SELALU1); `dp(`DEC); `dp(`ALUREG); `dp(`SETREG2);
											`dp(`CCGET);
											state <= EX_1;
										  end
									EX_1: begin
											if (~dp_alucc[2]) begin
												`dp(`PCALU1); `dp(`OFS6ALU2); `dp(`SUB); `dp(`ALUPC);
											end
											state <= FS_IF0;
										  end
									endcase
								  end
								
					// gruuu...
					idcop[`djsr]: begin
									case (state)
									EX_0: begin
											`dp(`SPALU1); `dp(`DEC2); `dp(`ALUSP);
											state <= EX_1;
										  end
									EX_1: begin
											mbyte <= 1'b0;
											dato <= 1'b1;
											`dp(`REGSEL2); `dp(`DBOSEL); `dp(`DBASP);
											if (ierror) begin
												dato <= 1'b0;
												`dp(`BUSERR);
												state <= TRAP_SVC;
											end 
											else if (ready) begin
												dato <= 1'b0;
												`dp(`PCREG); `dp(`SETREG2);
												state <= EX_2;
											end
										  end
									EX_2: begin
											`dp(`ADRPC); 
											state <= FS_IF0;
										  end
									endcase
								  end
								
					idcop[`drts]: begin
									case (state)
									EX_0: begin
											`dp(`REGSEL); `dp(`SELPC);
											state <= EX_1;
										  end
									
									EX_1: begin
											mbyte <= 1'b0;
											dati <= 1'b1;
											`dp(`DBASP);
											if (ierror) begin
												dati <= 1'b0;
												`dp(`BUSERR);
												state <= TRAP_SVC;
											end 
											else if (ready) begin
												dati <= 1'b0;
												`dp(`DBIREG); `dp(`SETREG);
												`dp(`SPALU1); `dp(`INC2); `dp(`ALUSP);
												state <= FS_IF0;
											end
										  end
									endcase
								  end
								
					idcop[`drtt],			
					idcop[`drti]: begin
									case (state)
									EX_0: begin
											mbyte <= 1'b0;
											dati <= 1'b1;
											`dp(`DBASP);
											if (ierror) begin
												dati <= 1'b0;
												`dp(`BUSERR);
												state <= TRAP_SVC;
											end
											else if (ready) begin
												dati <= 1'b0;
												`dp(`DBIPC);
												`dp(`SPALU1); `dp(`INC2); `dp(`ALUSP);
												state <= EX_1;
											end
										  end
									EX_1: begin
											mbyte <= 1'b0;
											dati <= 1'b1;
											`dp(`DBASP);
											if (ierror) begin
												dati <= 1'b0;
												`dp(`BUSERR);
												state <= TRAP_SVC;
											end
											else if (ready) begin
												dati <= 1'b0;
												`dp(`DBIPS);
												`dp(`SPALU1); `dp(`INC2); `dp(`ALUSP);
												state <= FS_IF0;
											end
										  end
									endcase
								  end
								
					idcop[`dmark]:begin
									// gruuu..
									case (state)
									EX_0: begin
											`dp(`SPALU1); `dp(`OFS6ALU2); 
											`dp(`ADD); `dp(`ALUSP);
											`dp(`FPPC);
											state <= EX_1;
										  end
									EX_1: begin
											mbyte <= 1'b0;
											dati <= 1'b1;
											`dp(`DBASP);
											if (ierror) begin
												dati <= 1'b0;
												`dp(`BUSERR);
												state <= TRAP_SVC;
											end 
											else if (ready) begin
												dati <= 1'b0;
												`dp(`DBIFP);
												`dp(`SPALU1); `dp(`INC2); `dp(`ALUSP);
												state <= FS_IF0;
											end
										  end
									endcase
								  end
                    idcop[`dmtps]:begin // PSW <- ss
                                  `dp(`DSTPSW);
                                  state <= FS_IF0;
                                  end
                    idcop[`dmfps]:begin // dd <- PSW, set flags
                                  `dp(`PSWALU1);
                                  `dp(`ALUDST); 
                                  `dp(`MOV); 
                                  `dp(`ALUCC);
                                  state <= WB_0;
                                  end
                    //default:      begin
                    //              `dp(`ERR);
                    //              state <= TRAP_SVC;
                    //              end
					endcase // idcop
				end // EX_*
				
		WB_0: 	begin
					//state <= FS_IF0;
					
					if (dp_opcode[5:3] != 0) begin
						dato <= 1'b1;
						mbyte <= BYTE;
						`dp(`DBODST); `dp(`DBAADR);
						
						if (ierror|ready) dato <= 1'b0;
						
						if (ierror) begin
							`dp(`BUSERR);
							state <= TRAP_SVC;
						end
						else 
							if (ready) begin
								if (TRACE) begin
									`dp(`BPT); state <= TRAP_SVC;
								end 
								else if (irq_in) 
									state <= TRAP_IRQ;
								else
									state <= FS_IF0;
							end
					end 
					else begin
						`dp(`DSTREG); `dp(`SETREG);
						if (TRACE) begin
							`dp(`BPT); state <= TRAP_SVC;
						end 
						else if (irq_in) 
							state <= TRAP_IRQ;
						else
							state <= FS_IF0;						
					end
					
				end
		
			// it's a trap!
		TRAP_IRQ: begin
					iako <= 1'b1; // ?
					`dp(`DBISRC);
					`dp(`RESET_BYTE);
					`dp(`SAVE_STAT);
					state <= TRAP_1;
				  end
		
		TRAP_SVC: begin
					`dp(`RESET_BYTE);
					`dp(`SAVE_STAT);
					state <= TRAP_1;
				  end
				
		TRAP_1:	begin
					mbyte <= 1'b0;
					dati <= 1'b1;
					`dp(`DBASRC);	// trap vector
					if (ierror) begin
						dati <= 1'b0;
						`dp(`BUSERR);
						state <= TRAP_SVC;
						// becoming an hero.
						// here LSI-11 is supposed to:
						// - if this is IRQ or any trap but bus error => trap to 4
						// - if this is trap 4 => die to console mode
						// not sure what VM1 is supposed to do here
					end else if (ready) begin
						dati <= 1'b0;
						`dp(`DBIPC);
						`dp(`SRCALU1); `dp(`INC2); `dp(`ALUSRC);
						state <= TRAP_2;
					end
				end
				
		TRAP_2: begin
					mbyte <= 1'b0;
					dati <= 1'b1;
					if (ierror|ready) dati <= 1'b0;
					`dp(`DBASRC); 	// vector+2/priority
					if (ierror) begin
						`dp(`BUSERR);
						state <= TRAP_SVC;
					end else if (ready) begin
						`dp(`VECTORPS);
						`dp(`SPALU1); `dp(`DEC2); `dp(`ALUSP);
						state <= TRAP_3;
					end
				end
				
		TRAP_3:	begin
					`dp(`DBODST); `dp(`DBASP);
					mbyte <= 1'b0;// Mr.Iida has BYTE here
					dato <= 1'b1;
					if (ierror|ready) dato <= 1'b0;
					if (ierror) begin
						`dp(`BUSERR);
						state <= TRAP_SVC;
					end else if (ready) begin
						`dp(`SPALU1); `dp(`DEC2); `dp(`ALUSP);
						state <= TRAP_4;
					end
				end
		TRAP_4: begin
					`dp(`DBOADR); `dp(`DBASP);
					dato <= 1'b1;
					if (ierror|ready) dato <= 1'b0;
					if (ierror) begin
						`dp(`BUSERR);
						state <= TRAP_SVC;
					end else if (ready) begin
						state <= FS_IF0;
					end
				end
		endcase // state
	end
end


endmodule

