// fifo with bypass if writting and readign at the same time

module fifo #(
    parameter int unsigned DEPTH      = 16,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  data_in_valid,
    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic [KEEP_WIDTH-1:0] keep_in,
    input  logic                  last_in,
    output logic                  data_in_ready,

    output logic                  data_out_valid,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic [KEEP_WIDTH-1:0] keep_out,
    output logic                  last_out,
    input  logic                  data_out_ready
);

    localparam int unsigned PTR_WIDTH = $clog2(DEPTH);

    // Extra MSB distinguishes full from empty after wraparound.
    logic [PTR_WIDTH:0] write_ptr;
    logic [PTR_WIDTH:0] read_ptr;

    logic [DATA_WIDTH-1:0] mem_data [0:DEPTH-1];
    logic [KEEP_WIDTH-1:0] mem_keep [0:DEPTH-1];
    logic                  mem_last [0:DEPTH-1];

    logic empty;
    logic full;

    assign empty = (write_ptr == read_ptr);

    assign full =
        (write_ptr[PTR_WIDTH] != read_ptr[PTR_WIDTH]) &&
        (write_ptr[PTR_WIDTH-1:0] ==
         read_ptr[PTR_WIDTH-1:0]);

    assign data_in_ready = !full || data_out_ready;

    assign data_out_valid = !empty || data_in_valid;

    assign data_out =
        empty
            ? data_in
            : mem_data[read_ptr[PTR_WIDTH-1:0]];

    assign keep_out =
        empty
            ? keep_in
            : mem_keep[read_ptr[PTR_WIDTH-1:0]];

    assign last_out =
        empty
            ? last_in
            : mem_last[read_ptr[PTR_WIDTH-1:0]];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr  <= '0;
        end else begin

  
            if (data_in_valid && data_in_ready &&!(empty && data_out_ready)) begin
                mem_data[write_ptr[PTR_WIDTH-1:0]] <= data_in;
                mem_keep[write_ptr[PTR_WIDTH-1:0]] <= keep_in;
                mem_last[write_ptr[PTR_WIDTH-1:0]] <= last_in;

                write_ptr <= write_ptr + 1'b1;
            end

            if (data_out_valid && data_out_ready && !empty) begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end

endmodule