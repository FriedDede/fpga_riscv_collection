`ifndef AXI_ASSIGN_SVH_HBM
`define AXI_ASSIGN_SVH_HBM

//////////////////////////////////////////////////////////////
// assign an axi req resp pair to an hbm channel, using new pulp axi
// pat = "S00" or "S01" etc
`define AXI_ASSIGN_MASTER_TO_HBM(pat, req, rsp) \
  assign ``pat``_AXI_0_awvalid  = req.aw_valid;  \
  assign ``pat``_AXI_0_awid     = req.aw.id;     \
  assign ``pat``_AXI_0_awaddr   = req.aw.addr[30:0];   \
  assign ``pat``_AXI_0_awlen    = req.aw.len;    \
  assign ``pat``_AXI_0_awsize   = req.aw.size;   \
  assign ``pat``_AXI_0_awburst  = req.aw.burst;  \
  assign ``pat``_AXI_0_awlock   = req.aw.lock;   \
  assign ``pat``_AXI_0_awcache  = req.aw.cache;  \
  assign ``pat``_AXI_0_awprot   = req.aw.prot;   \
  assign ``pat``_AXI_0_awqos    = req.aw.qos;    \
  assign ``pat``_AXI_0_awregion = req.aw.region; \
  assign ``pat``_AXI_0_awuser   = req.aw.user;   \
                                           \
  assign ``pat``_AXI_0_wvalid   = req.w_valid;   \
  assign ``pat``_AXI_0_wdata    = req.w.data;    \
  assign ``pat``_AXI_0_wstrb    = req.w.strb;    \
  assign ``pat``_AXI_0_wlast    = req.w.last;    \
  assign ``pat``_AXI_0_wuser    = req.w.user;    \
                                          \
  assign ``pat``_AXI_0_bready   = req.b_ready;   \
                                          \
  assign ``pat``_AXI_0_arvalid  = req.ar_valid;  \
  assign ``pat``_AXI_0_arid     = req.ar.id;     \
  assign ``pat``_AXI_0_araddr   = req.ar.addr[30:0];   \
  assign ``pat``_AXI_0_arlen    = req.ar.len;    \
  assign ``pat``_AXI_0_arsize   = req.ar.size;   \
  assign ``pat``_AXI_0_arburst  = req.ar.burst;  \
  assign ``pat``_AXI_0_arlock   = req.ar.lock;   \
  assign ``pat``_AXI_0_arcache  = req.ar.cache;  \
  assign ``pat``_AXI_0_arprot   = req.ar.prot;   \
  assign ``pat``_AXI_0_arqos    = req.ar.qos;    \
  assign ``pat``_AXI_0_arregion = req.ar.region; \
  assign ``pat``_AXI_0_aruser   = req.ar.user;   \
                                            \
  assign ``pat``_AXI_0_rready   = req.r_ready;   \
                                                 \
  assign rsp.aw_ready = ``pat``_AXI_0_awready;   \
  assign rsp.ar_ready = ``pat``_AXI_0_arready;   \
  assign rsp.w_ready  = ``pat``_AXI_0_wready;    \
                                           \
  assign rsp.b_valid  = ``pat``_AXI_0_bvalid;    \
  assign rsp.b.id     = ``pat``_AXI_0_bid;       \
  assign rsp.b.resp   = ``pat``_AXI_0_bresp;     \
  assign rsp.b.user   = ``pat``_AXI_0_buser;     \
                                           \
  assign rsp.r_valid  = ``pat``_AXI_0_rvalid;    \
  assign rsp.r.id     = ``pat``_AXI_0_rid;       \
  assign rsp.r.data   = ``pat``_AXI_0_rdata;     \
  assign rsp.r.resp   = ``pat``_AXI_0_rresp;     \
  assign rsp.r.last   = ``pat``_AXI_0_rlast;     \
  assign rsp.r.user   = ``pat``_AXI_0_ruser;     

// adapter between snitch new axi interface and ariane old one
`define AXI_ASSIGN_MASTER_TO_ARIANE_AXI_INT(slave, req, rsp) \
  assign slave.aw_valid  = req.aw_valid;  \
  assign slave.aw_id     = req.aw.id;     \
  assign slave.aw_addr   = req.aw.addr[30:0];   \
  assign slave.aw_len    = req.aw.len;    \
  assign slave.aw_size   = req.aw.size;   \
  assign slave.aw_burst  = req.aw.burst;  \
  assign slave.aw_lock   = req.aw.lock;   \
  assign slave.aw_cache  = req.aw.cache;  \
  assign slave.aw_prot   = req.aw.prot;   \
  assign slave.aw_qos    = req.aw.qos;    \
  assign slave.aw_region = req.aw.region; \
  assign slave.aw_user   = req.aw.user;   \
                                    \
  assign slave.w_valid   = req.w_valid;   \
  assign slave.w_data    = req.w.data;    \
  assign slave.w_strb    = req.w.strb;    \
  assign slave.w_last    = req.w.last;    \
  assign slave.w_user    = req.w.user;    \
                                   \
  assign slave.b_ready   = req.b_ready;   \
                                   \
  assign slave.ar_valid  = req.ar_valid;  \
  assign slave.ar_id     = req.ar.id;     \
  assign slave.ar_addr   = req.ar.addr[30:0];   \
  assign slave.ar_len    = req.ar.len;    \
  assign slave.ar_size   = req.ar.size;   \
  assign slave.ar_burst  = req.ar.burst;  \
  assign slave.ar_lock   = req.ar.lock;   \
  assign slave.ar_cache  = req.ar.cache;  \
  assign slave.ar_prot   = req.ar.prot;   \
  assign slave.ar_qos    = req.ar.qos;    \
  assign slave.ar_region = req.ar.region; \
  assign slave.ar_user   = req.ar.user;   \
                                            \
  assign slave.r_ready   = req.r_ready;   \
                                                 \
  assign rsp.aw_ready = slave.aw_ready;   \
  assign rsp.ar_ready = slave.ar_ready;   \
  assign rsp.w_ready  = slave.w_ready;    \
                                    \
  assign rsp.b_valid  = slave.b_valid;    \
  assign rsp.b.id     = slave.b_id;       \
  assign rsp.b.resp   = slave.b_resp;     \
  assign rsp.b.user   = slave.b_user;     \
                                    \
  assign rsp.r_valid  = slave.r_valid;    \
  assign rsp.r.id     = slave.r_id;       \
  assign rsp.r.data   = slave.r_data;     \
  assign rsp.r.resp   = slave.r_resp;     \
  assign rsp.r.last   = slave.r_last;     \
  assign rsp.r.user   = slave.r_user;     

//////////////////////////////////////////////////////////////
// assign an axi req resp pair to an hbm channel, using old ariane axi
// pat = "S00" or "S01" etc
`define AXI_ASSIGN_MASTER_TO_HBM_ARIANE(pat, bus) \
  assign pat``_AXI_0_awvalid  = bus.aw_valid;  \
  assign pat``_AXI_0_awid     = bus.aw_id;     \
  assign pat``_AXI_0_awaddr   = bus.aw_addr[30:0]; \
  assign pat``_AXI_0_awlen    = bus.aw_len;    \
  assign pat``_AXI_0_awsize   = bus.aw_size;   \
  assign pat``_AXI_0_awburst  = bus.aw_burst;  \
  assign pat``_AXI_0_awlock   = bus.aw_lock;   \
  assign pat``_AXI_0_awcache  = bus.aw_cache;  \
  assign pat``_AXI_0_awprot   = bus.aw_prot;   \
  assign pat``_AXI_0_awqos    = bus.aw_qos;    \
  assign pat``_AXI_0_awregion = bus.aw_region; \
  assign pat``_AXI_0_awuser   = bus.aw_user;   \
                                        \
  assign pat``_AXI_0_wvalid   = bus.w_valid;   \
  assign pat``_AXI_0_wdata    = bus.w_data;    \
  assign pat``_AXI_0_wstrb    = bus.w_strb;    \
  assign pat``_AXI_0_wlast    = bus.w_last;    \
  assign pat``_AXI_0_wuser    = bus.w_user;    \
                                        \
  assign pat``_AXI_0_bready   = bus.b_ready;   \
                                        \
  assign pat``_AXI_0_arvalid  = bus.ar_valid;  \
  assign pat``_AXI_0_arid     = bus.ar_id;     \
  assign pat``_AXI_0_araddr   = bus.ar_addr[30:0];\
  assign pat``_AXI_0_arlen    = bus.ar_len;    \
  assign pat``_AXI_0_arsize   = bus.ar_size;   \
  assign pat``_AXI_0_arburst  = bus.ar_burst;  \
  assign pat``_AXI_0_arlock   = bus.ar_lock;   \
  assign pat``_AXI_0_arcache  = bus.ar_cache;  \
  assign pat``_AXI_0_arprot   = bus.ar_prot;   \
  assign pat``_AXI_0_arqos    = bus.ar_qos;    \
  assign pat``_AXI_0_arregion = bus.ar_region; \
  assign pat``_AXI_0_aruser   = bus.ar_user;   \
                                          \
  assign pat``_AXI_0_rready   = req.r_ready;   \
                                                 \
  assign bus.aw_ready = pat``_AXI_0_awready;   \
  assign bus.ar_ready = pat``_AXI_0_arready;   \
  assign bus.w_ready  = pat``_AXI_0_wready;    \
                                         \
  assign bus.b_valid  = pat``_AXI_0_bvalid;    \
  assign bus.b_id     = pat``_AXI_0_bid;       \
  assign bus.b_resp   = pat``_AXI_0_bresp;     \
  assign bus.b_user   = pat``_AXI_0_buser;     \
                                         \
  assign bus.r_valid  = pat``_AXI_0_rvalid;    \
  assign bus.r_id     = pat``_AXI_0_rid;       \
  assign bus.r_data   = pat``_AXI_0_rdata;     \
  assign bus.r_resp   = pat``_AXI_0_rresp;     \
  assign bus.r_last   = pat``_AXI_0_rlast;     \
  assign bus.r_user   = pat``_AXI_0_ruser;

//////////////////////////////////////////////////////////////
// port connections of one hbm_interface (qdma_interface.tcl) channel, to be used in the
// hbm_interface port list, e.g.
//   hbm_interface i_hbm_interface (
//       `HBM_ASSIGN_CHANNEL(S00, axi_dram[0], 0, clk_cluster),
//       `HBM_TIE_OFF_CHANNEL(S01, clk_cluster),
//       ...
// prefix         = S00 ... S11
// bus            = AXI_BUS (pulp interface) master, the lower 30 address bits are used
// address_offset = HBM address bits [33:30], i.e. which 1GB of the 16GB HBM the channel sees
// clk            = clock of the bus (crossbar of the cluster), axi_clk_cluster_<prefix> port
// bus.b_user / bus.r_user are not driven by the HBM, assign them outside the instance
`define HBM_ASSIGN_CHANNEL(prefix, bus, address_offset, clk)               \
  .axi_clk_cluster_``prefix (clk),                                          \
  .prefix``_AXI_0_araddr   ({4'(address_offset), bus.ar_addr[29:0]}),       \
  .prefix``_AXI_0_arburst  (bus.ar_burst),                                  \
  .prefix``_AXI_0_arcache  (bus.ar_cache),                                  \
  .prefix``_AXI_0_arid     (bus.ar_id),                                     \
  .prefix``_AXI_0_arlen    (bus.ar_len),                                    \
  .prefix``_AXI_0_arlock   (bus.ar_lock),                                   \
  .prefix``_AXI_0_arprot   (bus.ar_prot),                                   \
  .prefix``_AXI_0_arqos    (bus.ar_qos),                                    \
  .prefix``_AXI_0_arready  (bus.ar_ready),                                  \
  .prefix``_AXI_0_arsize   (bus.ar_size),                                   \
  .prefix``_AXI_0_arvalid  (bus.ar_valid),                                  \
  .prefix``_AXI_0_awaddr   ({4'(address_offset), bus.aw_addr[29:0]}),       \
  .prefix``_AXI_0_awburst  (bus.aw_burst),                                  \
  .prefix``_AXI_0_awcache  (bus.aw_cache),                                  \
  .prefix``_AXI_0_awid     (bus.aw_id),                                     \
  .prefix``_AXI_0_awlen    (bus.aw_len),                                    \
  .prefix``_AXI_0_awlock   (bus.aw_lock),                                   \
  .prefix``_AXI_0_awprot   (bus.aw_prot),                                   \
  .prefix``_AXI_0_awqos    (bus.aw_qos),                                    \
  .prefix``_AXI_0_awready  (bus.aw_ready),                                  \
  .prefix``_AXI_0_awsize   (bus.aw_size),                                   \
  .prefix``_AXI_0_awvalid  (bus.aw_valid),                                  \
  .prefix``_AXI_0_bid      (bus.b_id),                                      \
  .prefix``_AXI_0_bready   (bus.b_ready),                                   \
  .prefix``_AXI_0_bresp    (bus.b_resp),                                    \
  .prefix``_AXI_0_bvalid   (bus.b_valid),                                   \
  .prefix``_AXI_0_rdata    (bus.r_data),                                    \
  .prefix``_AXI_0_rid      (bus.r_id),                                      \
  .prefix``_AXI_0_rlast    (bus.r_last),                                    \
  .prefix``_AXI_0_rready   (bus.r_ready),                                   \
  .prefix``_AXI_0_rresp    (bus.r_resp),                                    \
  .prefix``_AXI_0_rvalid   (bus.r_valid),                                   \
  .prefix``_AXI_0_wdata    (bus.w_data),                                    \
  .prefix``_AXI_0_wlast    (bus.w_last),                                    \
  .prefix``_AXI_0_wready   (bus.w_ready),                                   \
  .prefix``_AXI_0_wstrb    (bus.w_strb),                                    \
  .prefix``_AXI_0_wvalid   (bus.w_valid)

// unused hbm_interface channel: no requests, responses always accepted.
// clk must be a running clock (e.g. the one of a used channel): the smartconnect of the
// block design synchronizes its reset in each clock domain
`define HBM_TIE_OFF_CHANNEL(prefix, clk)   \
  .axi_clk_cluster_``prefix (clk),          \
  .prefix``_AXI_0_araddr   ('0),            \
  .prefix``_AXI_0_arburst  ('0),            \
  .prefix``_AXI_0_arcache  ('0),            \
  .prefix``_AXI_0_arid     ('0),            \
  .prefix``_AXI_0_arlen    ('0),            \
  .prefix``_AXI_0_arlock   ('0),            \
  .prefix``_AXI_0_arprot   ('0),            \
  .prefix``_AXI_0_arqos    ('0),            \
  .prefix``_AXI_0_arready  (),              \
  .prefix``_AXI_0_arsize   ('0),            \
  .prefix``_AXI_0_arvalid  (1'b0),          \
  .prefix``_AXI_0_awaddr   ('0),            \
  .prefix``_AXI_0_awburst  ('0),            \
  .prefix``_AXI_0_awcache  ('0),            \
  .prefix``_AXI_0_awid     ('0),            \
  .prefix``_AXI_0_awlen    ('0),            \
  .prefix``_AXI_0_awlock   ('0),            \
  .prefix``_AXI_0_awprot   ('0),            \
  .prefix``_AXI_0_awqos    ('0),            \
  .prefix``_AXI_0_awready  (),              \
  .prefix``_AXI_0_awsize   ('0),            \
  .prefix``_AXI_0_awvalid  (1'b0),          \
  .prefix``_AXI_0_bid      (),              \
  .prefix``_AXI_0_bready   (1'b1),          \
  .prefix``_AXI_0_bresp    (),              \
  .prefix``_AXI_0_bvalid   (),              \
  .prefix``_AXI_0_rdata    (),              \
  .prefix``_AXI_0_rid      (),              \
  .prefix``_AXI_0_rlast    (),              \
  .prefix``_AXI_0_rready   (1'b1),          \
  .prefix``_AXI_0_rresp    (),              \
  .prefix``_AXI_0_rvalid   (),              \
  .prefix``_AXI_0_wdata    ('0),            \
  .prefix``_AXI_0_wlast    (1'b0),          \
  .prefix``_AXI_0_wready   (),              \
  .prefix``_AXI_0_wstrb    ('0),            \
  .prefix``_AXI_0_wvalid   (1'b0)

`endif
//////////////////////////////////////////////////////////////
// HBM axi channel port macro
//`define AXI_HBM_CHANNEL(tag)  \
//  .tag``_AXI_0_araddr   ,   \  
//  .tag``_AXI_0_arburst  ,   \
//  .tag``_AXI_0_arcache  ,   \
//  .tag``_AXI_0_arid     ,   \
//  .tag``_AXI_0_arlen    ,   \
//  .tag``_AXI_0_arlock   ,   \
//  .tag``_AXI_0_arprot   ,   \
//  .tag``_AXI_0_arqos    ,   \
//  .tag``_AXI_0_arready  ,   \
//  .tag``_AXI_0_arsize   ,   \
//  .tag``_AXI_0_arvalid  ,   \
//  .tag``_AXI_0_awaddr   ,   \  
//  .tag``_AXI_0_awburst  ,   \
//  .tag``_AXI_0_awcache  ,   \
//  .tag``_AXI_0_awid     ,   \
//  .tag``_AXI_0_awlen    ,   \
//  .tag``_AXI_0_awlock   ,   \
//  .tag``_AXI_0_awprot   ,   \
//  .tag``_AXI_0_awqos    ,   \
//  .tag``_AXI_0_awready  ,   \
//  .tag``_AXI_0_awsize   ,   \
//  .tag``_AXI_0_awvalid  ,   \
//  .tag``_AXI_0_bid      ,   \
//  .tag``_AXI_0_bready   ,   \
//  .tag``_AXI_0_bresp    ,   \
//  .tag``_AXI_0_bvalid   ,   \
//  .tag``_AXI_0_rdata    ,   \
//  .tag``_AXI_0_rid      ,   \
//  .tag``_AXI_0_rlast    ,   \
//  .tag``_AXI_0_rready   ,   \
//  .tag``_AXI_0_rresp    ,   \
//  .tag``_AXI_0_rvalid   ,   \
//  .tag``_AXI_0_wdata    ,   \
//  .tag``_AXI_0_wlast    ,   \
//  .tag``_AXI_0_wready   ,   \
//  .tag``_AXI_0_wstrb    ,   \
//  .tag``_AXI_0_wvalid      
//`endif