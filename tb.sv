class transaction;
  rand bit rst;
  rand bit enable;
  bit [3:0] count;

  constraint rst_c    { rst    dist {1'b0 := 9, 1'b1 := 1}; }
  constraint enable_c { enable dist {1'b0 := 3, 1'b1 := 7}; }

  function transaction copy();
    copy = new();
    copy.rst    = this.rst;
    copy.enable = this.enable;
    copy.count  = this.count;
  endfunction

  function void display(string tag);
    $display("[%0s] rst=%0b enable=%0b count=%0d time=%0t", tag, rst, enable, count, $time);
  endfunction
endclass


class generator;
  mailbox #(transaction) mbx;
  event drv_done;
  event done;
  int   num_transactions;

  function new(mailbox #(transaction) mbx, event drv_done);
    this.mbx      = mbx;
    this.drv_done = drv_done;
  endfunction

  task run();
    transaction tr;
    repeat (num_transactions) begin
      tr = new();
      if (!tr.randomize()) $error("[GEN] randomization failed");
      mbx.put(tr);
      tr.display("GEN");
      @(drv_done);
    end
    ->done;
  endtask
endclass


class driver;
  mailbox #(transaction) mbx;
  virtual counter_if vif;
  event drv_done;

  function new(mailbox #(transaction) mbx, virtual counter_if vif, event drv_done);
    this.mbx      = mbx;
    this.vif      = vif;
    this.drv_done = drv_done;
  endfunction

  task reset();
    transaction dummy;
    vif.rst    <= 1'b1;
    vif.enable <= 1'b0;
    repeat (5) @(posedge vif.clk);
    vif.rst    <= 1'b0;
    @(posedge vif.clk);
    $display("[DRV] reset done at %0t", $time);
  endtask

  task run();
    transaction tr;
    forever begin
      mbx.get(tr);
      @(posedge vif.clk);
      vif.rst    <= tr.rst;
      vif.enable <= tr.enable;
      tr.display("DRV");
      @(posedge vif.clk);
      vif.rst    <= 1'b0;
      vif.enable <= 1'b0;
      ->drv_done;
    end
  endtask
endclass


class monitor;
  mailbox #(transaction) mbx;
  virtual counter_if vif;

  function new(mailbox #(transaction) mbx, virtual counter_if vif);
    this.mbx = mbx;
    this.vif = vif;
  endfunction

  task run();
    transaction tr;
    forever begin
      @(posedge vif.clk);
      tr         = new();
      tr.rst     = vif.rst;
      tr.enable  = vif.enable;
      tr.count   = vif.count;
      mbx.put(tr);
    end
  endtask
endclass


class scoreboard;
  mailbox #(transaction) mbx;
  bit [3:0] exp_count;
  int pass_cnt;
  int fail_cnt;

  function new(mailbox #(transaction) mbx);
    this.mbx  = mbx;
    exp_count = 4'd0;
    pass_cnt  = 0;
    fail_cnt  = 0;
  endfunction

  task run();
    transaction tr;
    forever begin
      mbx.get(tr);

      if (tr.count === exp_count) begin
        pass_cnt++;
      end
      else begin
        fail_cnt++;
        $error("[SCO] MISMATCH expected=%0d got=%0d time=%0t", exp_count, tr.count, $time);
      end

      if (tr.rst)         exp_count = 4'd0;
      else if (tr.enable) exp_count = exp_count + 4'd1;
    end
  endtask

  function void report();
    $display("--------------------------------------");
    $display("[SCO] PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("[SCO] TEST PASSED");
    else               $display("[SCO] TEST FAILED");
    $display("--------------------------------------");
  endfunction
endclass


class environment;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard sco;

  event drv_done;

  mailbox #(transaction) gdmbx;
  mailbox #(transaction) msmbx;
  virtual counter_if vif;

  function new(virtual counter_if vif);
    this.vif = vif;
    gdmbx = new();
    msmbx = new();
    gen = new(gdmbx, drv_done);
    drv = new(gdmbx, vif, drv_done);
    mon = new(msmbx, vif);
    sco = new(msmbx);
  endfunction

  task pre_test();
    drv.reset();
  endtask

  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_none
  endtask

  task post_test();
    @(gen.done);
    repeat (5) @(posedge vif.clk);
    sco.report();
    $finish;
  endtask

  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass


module tb;
  logic clk = 0;
  always #5 clk = ~clk;

  counter_if vif (clk);

  counter dut (
    .clk   (vif.clk),
    .rst   (vif.rst),
    .enable(vif.enable),
    .count (vif.count)
  );

  environment env;

  initial begin
    vif.rst    = 1'b0;
    vif.enable = 1'b0;
    env = new(vif);
    env.gen.num_transactions = 50;
    env.run();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
  end
endmodule
