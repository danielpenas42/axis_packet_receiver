`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Daniel Penas Varela
// 
// Create Date: 07/29/2026 01:21:11 PM
// Design Name: 
// Module Name: axis_packet_receiver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Axis buffer with forwarding
module axis_packet_receiver#(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = DATA_WIDTH/8,
    parameter int ADDR_WIDTH = 4
)(
    input logic                  aclk,
    input logic                  arst_n,

    // AXI-4 Stream Interface slave
    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic [KEEP_WIDTH-1:0] s_axis_tkeep,
    input logic                  s_axis_tvalid,
    input logic                  s_axis_tlast,
    output logic                 s_axis_tready,

    // AXI-4 Stream Interface master
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic [KEEP_WIDTH-1:0] m_axis_tkeep,
    output logic                  m_axis_tvalid,
    output logic                  m_axis_tlast,
    input  logic                  m_axis_tready,

    // axi lite interface write
    input  logic [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,
    
    input  logic [DATA_WIDTH-1:0] s_axil_wdata,
    input  logic [KEEP_WIDTH-1:0] s_axil_wstrb, // wstrb is intentionally ignored here
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    output logic [1:0] s_axil_bresp,
    output logic       s_axil_bvalid,
    input  logic       s_axil_bready,

    // axi lite read interface 
    input logic [ADDR_WIDTH-1:0] s_axil_araddr,
    input logic                  s_axil_arvalid,
    output  logic                  s_axil_arready,

    output logic [DATA_WIDTH-1:0] s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready

    );

    fifo #(
        .DEPTH      (1024),
        .DATA_WIDTH (DATA_WIDTH),
        .KEEP_WIDTH (KEEP_WIDTH)
    ) fifo_inst (
        .clk            (aclk),
        .rst_n          (arst_n),

        .data_in_valid  (s_axis_tvalid),
        .data_in        (s_axis_tdata),
        .keep_in        (s_axis_tkeep),
        .last_in        (s_axis_tlast),
        .data_in_ready  (s_axis_tready),

        .data_out_valid (m_axis_tvalid),
        .data_out       (m_axis_tdata),
        .keep_out       (m_axis_tkeep),
        .last_out       (m_axis_tlast),
        .data_out_ready (m_axis_tready)
    );


    logic [31:0]          bursts_count;
    logic [31:0]          current_burst_beats;
    logic [31:0]          last_burst_beats;
    logic [31:0]          control_reg;

    assign s_axil_arready = !s_axil_rvalid;
    
    // read logic of the axi lite
    always_ff @(posedge aclk or negedge arst_n) begin

        if (!arst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= '0;
            s_axil_rresp  <= 2'b00;
        end
        else begin
            if (s_axil_arvalid && s_axil_arready) begin
                logic [DATA_WIDTH-1:0] value_out;
                s_axil_rresp  <= 2'b00;
                case (s_axil_araddr)
                    4'h0: 
                        value_out = control_reg;
                    4'h4: value_out = bursts_count;
                    4'h8: value_out = current_burst_beats;
                    4'hC: value_out = last_burst_beats;
                    default: begin
                        value_out = '0;
                        s_axil_rresp <= 2'b10;
                    end
                endcase
                s_axil_rdata <= value_out;
                s_axil_rvalid <= 1'b1;
            end
            else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end
    
    logic [ADDR_WIDTH-1:0] waddress;
    logic                  waddress_stored;

    logic [DATA_WIDTH-1:0] wdata;
    logic                  wdata_stored;
    logic new_aw;
    logic new_w;

    logic clear_counters;

    assign new_aw = s_axil_awvalid && s_axil_awready;
    assign new_w  = s_axil_wvalid  && s_axil_wready;

    assign s_axil_awready = !s_axil_bvalid && !waddress_stored;
    assign s_axil_wready = !s_axil_bvalid && !wdata_stored;

    // wrire logic of the axi lite
    always_ff @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            waddress_stored <= 1'b0;
            wdata_stored    <= 1'b0;
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
            control_reg   <= '0;
            clear_counters <= '0;
        end
        else begin
            clear_counters <= '0;

            if (new_aw) begin
                waddress        <= s_axil_awaddr;
                waddress_stored <= 1'b1;
            end

            if (new_w) begin
                wdata        <= s_axil_wdata;
                wdata_stored <= 1'b1;
            end

            if ((waddress_stored || new_aw) && (wdata_stored || new_w)) begin
               
                case (new_aw ? s_axil_awaddr : waddress) 
                    4'h0: begin
                        control_reg[0] <= (new_w ? s_axil_wdata[0] : wdata[0]);
                        clear_counters <=(new_w ? s_axil_wdata[1] : wdata[1]);
                        s_axil_bresp  <= 2'b00;
                    end
                    default:
                        s_axil_bresp <= 2'b10; // SLVERR;
                endcase

                waddress_stored <= 1'b0;
                wdata_stored    <= 1'b0;

                s_axil_bvalid <= 1'b1;
                
            end

            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;

        end
    end

    always_ff @(posedge aclk or negedge arst_n) begin
        if(!arst_n || clear_counters) begin
            bursts_count <= '0;
            current_burst_beats <= '0;
            last_burst_beats <= '0;
        end
        else begin
            if (s_axis_tvalid && s_axis_tready && control_reg[0]) begin
                if (s_axis_tlast) begin
                    last_burst_beats <= current_burst_beats + 1'b1;
                    current_burst_beats <= '0;
                    bursts_count <= bursts_count + 1'b1;
                end
                else begin
                    current_burst_beats <= current_burst_beats + 1'b1;
                end
            end
        end
    end


endmodule
