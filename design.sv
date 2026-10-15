module counter (
  input  logic       clk,
  input  logic       rst,
  input  logic       enable,
  output logic [3:0] count
);
  always_ff @(posedge clk) begin
    if (rst)
      count <= 4'd0;
    else if (enable)
      count <= count + 4'd1;
  end
endmodule

interface counter_if (input logic clk);
  logic       rst;
  logic       enable;
  logic [3:0] count;
endinterface
