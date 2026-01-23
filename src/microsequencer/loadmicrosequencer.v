
    always @(posedge clk) begin
        if (!rst) begin
            ifmap_idx <= 0;
            stride_cnt <= 0;
            first_phase <= 1'b1;
            flush_cnt <= 0;
            padding_cnt_head <= 0;
            padding_cnt_tail <= 0;
            zero_or_data <= 1'b0;
            ifmap_counter_en <= 1'b0;
            en_shift_reg_ifmap_input_bayangan <= 0;
        end
        if (current_state == S_INIT) begin
            ifmap_idx <= 0;
            stride_cnt <= 0;
            first_phase <= 1'b1;
            flush_cnt <= 0;
            padding_cnt_head <= 0;
            padding_cnt_tail <= 0;
            zero_or_data <= 1'b0;
            ifmap_counter_en <= 1'b0;
            en_shift_reg_ifmap_input_bayangan <= {{(Dimension-1){1'b0}}, 1'b1, 1'b1};
        end
        else if (current_state == S_LOAD_WINDOW) begin
            if (padding_cnt_head < padding) begin
                ifmap_counter_en <= 1'b0;
                zero_or_data <= 1'b1;
                padding_cnt_head <= padding_cnt_head + 1;
                en_shift_reg_ifmap_input_bayangan <= {{Dimension+1}{1'b1}};
            end
            else if(padding_cnt_head == padding) begin // Transition
                ifmap_counter_en <= 1'b0;
                zero_or_data <= 1'b0;
                en_shift_reg_ifmap_input_bayangan <= {{(Dimension-1){1'b0}}, 1'b1, 1'b1};
            end
        end
    end
