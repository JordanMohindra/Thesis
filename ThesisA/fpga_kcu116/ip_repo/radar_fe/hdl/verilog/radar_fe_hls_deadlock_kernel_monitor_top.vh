
wire kernel_monitor_reset;
wire kernel_monitor_clock;
wire kernel_monitor_report;
assign kernel_monitor_reset = ~ap_rst_n;
assign kernel_monitor_clock = ap_clk;
assign kernel_monitor_report = 1'b0;
wire [1:0] axis_block_sigs;
wire [13:0] inst_idle_sigs;
wire [9:0] inst_block_sigs;
wire kernel_block;

assign axis_block_sigs[0] = ~fe_window_U0.in_stream_TDATA_blk_n;
assign axis_block_sigs[1] = ~fe_out_U0.grp_fe_out_Pipeline_EMIT_fu_162.out_stream_TDATA_blk_n;

assign inst_idle_sigs[0] = fe_window_U0.ap_idle;
assign inst_block_sigs[0] = (fe_window_U0.ap_done & ~fe_window_U0.ap_continue) | ~fe_window_U0.s0_blk_n | ~fe_window_U0.ms_blk_n | ~fe_window_U0.nRamps_c8_blk_n;
assign inst_idle_sigs[1] = fe_stage_0_U0.ap_idle;
assign inst_block_sigs[1] = (fe_stage_0_U0.ap_done & ~fe_stage_0_U0.ap_continue) | ~fe_stage_0_U0.grp_fe_stage_0_Pipeline_STORE_fu_104.s0_blk_n | ~fe_stage_0_U0.grp_fe_stage_0_Pipeline_BUTTERFLY_fu_118.s1_blk_n | ~fe_stage_0_U0.nRamps_blk_n | ~fe_stage_0_U0.nRamps_c7_blk_n;
assign inst_idle_sigs[2] = fe_stage_1_U0.ap_idle;
assign inst_block_sigs[2] = (fe_stage_1_U0.ap_done & ~fe_stage_1_U0.ap_continue) | ~fe_stage_1_U0.grp_fe_stage_1_Pipeline_STORE_fu_104.s1_blk_n | ~fe_stage_1_U0.grp_fe_stage_1_Pipeline_BUTTERFLY_fu_118.s2_blk_n | ~fe_stage_1_U0.nRamps_blk_n | ~fe_stage_1_U0.nRamps_c6_blk_n;
assign inst_idle_sigs[3] = fe_stage_2_U0.ap_idle;
assign inst_block_sigs[3] = (fe_stage_2_U0.ap_done & ~fe_stage_2_U0.ap_continue) | ~fe_stage_2_U0.grp_fe_stage_2_Pipeline_STORE_fu_104.s2_blk_n | ~fe_stage_2_U0.grp_fe_stage_2_Pipeline_BUTTERFLY_fu_118.s3_blk_n | ~fe_stage_2_U0.nRamps_blk_n | ~fe_stage_2_U0.nRamps_c5_blk_n;
assign inst_idle_sigs[4] = fe_stage_3_U0.ap_idle;
assign inst_block_sigs[4] = (fe_stage_3_U0.ap_done & ~fe_stage_3_U0.ap_continue) | ~fe_stage_3_U0.grp_fe_stage_3_Pipeline_STORE_fu_104.s3_blk_n | ~fe_stage_3_U0.grp_fe_stage_3_Pipeline_BUTTERFLY_fu_118.s4_blk_n | ~fe_stage_3_U0.nRamps_blk_n | ~fe_stage_3_U0.nRamps_c4_blk_n;
assign inst_idle_sigs[5] = fe_stage_4_U0.ap_idle;
assign inst_block_sigs[5] = (fe_stage_4_U0.ap_done & ~fe_stage_4_U0.ap_continue) | ~fe_stage_4_U0.grp_fe_stage_4_Pipeline_STORE_fu_104.s4_blk_n | ~fe_stage_4_U0.grp_fe_stage_4_Pipeline_BUTTERFLY_fu_118.s5_blk_n | ~fe_stage_4_U0.nRamps_blk_n | ~fe_stage_4_U0.nRamps_c3_blk_n;
assign inst_idle_sigs[6] = fe_stage_5_U0.ap_idle;
assign inst_block_sigs[6] = (fe_stage_5_U0.ap_done & ~fe_stage_5_U0.ap_continue) | ~fe_stage_5_U0.grp_fe_stage_5_Pipeline_STORE_fu_104.s5_blk_n | ~fe_stage_5_U0.grp_fe_stage_5_Pipeline_BUTTERFLY_fu_118.s6_blk_n | ~fe_stage_5_U0.nRamps_blk_n | ~fe_stage_5_U0.nRamps_c2_blk_n;
assign inst_idle_sigs[7] = fe_stage_6_U0.ap_idle;
assign inst_block_sigs[7] = (fe_stage_6_U0.ap_done & ~fe_stage_6_U0.ap_continue) | ~fe_stage_6_U0.grp_fe_stage_6_Pipeline_STORE_fu_104.s6_blk_n | ~fe_stage_6_U0.grp_fe_stage_6_Pipeline_BUTTERFLY_fu_118.s7_blk_n | ~fe_stage_6_U0.nRamps_blk_n | ~fe_stage_6_U0.nRamps_c1_blk_n;
assign inst_idle_sigs[8] = fe_stage_7_U0.ap_idle;
assign inst_block_sigs[8] = (fe_stage_7_U0.ap_done & ~fe_stage_7_U0.ap_continue) | ~fe_stage_7_U0.grp_fe_stage_7_Pipeline_STORE_fu_100.s7_blk_n | ~fe_stage_7_U0.grp_fe_stage_7_Pipeline_BUTTERFLY_fu_114.s8_blk_n | ~fe_stage_7_U0.nRamps_blk_n | ~fe_stage_7_U0.nRamps_c_blk_n;
assign inst_idle_sigs[9] = fe_out_U0.ap_idle;
assign inst_block_sigs[9] = (fe_out_U0.ap_done & ~fe_out_U0.ap_continue) | ~fe_out_U0.grp_fe_out_Pipeline_REORDER_fu_148.s8_blk_n | ~fe_out_U0.ms_blk_n | ~fe_out_U0.nRamps_blk_n;

assign inst_idle_sigs[10] = 1'b0;
assign inst_idle_sigs[11] = fe_window_U0.ap_idle;
assign inst_idle_sigs[12] = fe_out_U0.ap_idle;
assign inst_idle_sigs[13] = fe_out_U0.grp_fe_out_Pipeline_EMIT_fu_162.ap_idle;

radar_fe_hls_deadlock_idx0_monitor radar_fe_hls_deadlock_idx0_monitor_U (
    .clock(kernel_monitor_clock),
    .reset(kernel_monitor_reset),
    .axis_block_sigs(axis_block_sigs),
    .inst_idle_sigs(inst_idle_sigs),
    .inst_block_sigs(inst_block_sigs),
    .block(kernel_block)
);


always @ (kernel_block or kernel_monitor_reset) begin
    if (kernel_block == 1'b1 && kernel_monitor_reset == 1'b0) begin
        find_kernel_block = 1'b1;
    end
    else begin
        find_kernel_block = 1'b0;
    end
end
