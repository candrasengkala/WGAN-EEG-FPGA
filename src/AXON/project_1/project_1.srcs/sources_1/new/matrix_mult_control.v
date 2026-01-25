module matrix_mult_control #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire done_ifmap,
    input  wire done_weight,
    input  wire done_count,

    input  wire output_val,
    input  wire out_new_val,

    output reg  en_ifmap_counter,
    output reg  en_weight_counter,

    output reg [Dimension-1:0] en_shift_reg_ifmap,
    output reg [Dimension-1:0] en_shift_reg_weight,

    output reg  en_cntr,
    output reg [Dimension*Dimension-1:0] en_in,
    output reg [Dimension*Dimension-1:0] en_out,
    output reg [Dimension*Dimension-1:0] en_psum,

    output reg [Dimension-1:0] ifmaps_sel,

    output reg done_all,

    output reg output_val_count,
    output reg [Dimension-1:0] output_eject_ctrl
);

    /* ============================================================
     * State Encoding
     * ============================================================ */
    localparam IDLE        = 3'd0;
    localparam RAISE_EN    = 3'd1;
    localparam LOAD        = 3'd2;
    localparam COMPUTE     = 3'd3;
    localparam EJECT_WAIT  = 3'd4;
    localparam EJECT_SHIFT = 3'd5;
    localparam EJECT_IDLE  = 3'd6;
    localparam DONE        = 3'd7;

    reg [2:0] state, next_state;
    reg [$clog2(Dimension+1)-1:0] counter_ejection;

    /* ============================================================
     * State Register
     * ============================================================ */
    always @(posedge clk) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    /* ============================================================
     * Sequential Registers (SHIFT + COUNTER)
     * ============================================================ */
    always @(posedge clk) begin
        if (!rst) begin
            output_eject_ctrl <= {Dimension{1'b0}};
            counter_ejection  <= 0;
        end else begin
            case (state)
                EJECT_WAIT: begin
                    output_eject_ctrl <= {Dimension{1'b1}};
                    counter_ejection  <= 0;
                end

                EJECT_SHIFT: begin
                    output_eject_ctrl <= output_eject_ctrl << 1; // SHIFT ONCE
                    counter_ejection  <= counter_ejection + 1;
                end

                default: begin
                    output_eject_ctrl <= output_eject_ctrl;
                    counter_ejection  <= counter_ejection;
                end
            endcase
        end
    end

    /* ============================================================
     * Next-State Logic
     * ============================================================ */
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (start) next_state = RAISE_EN;

            RAISE_EN:
                next_state = LOAD;

            LOAD:
                if (done_ifmap && done_weight)
                    next_state = COMPUTE;

            COMPUTE:
                if (done_count)
                    next_state = EJECT_WAIT;

            EJECT_WAIT:
                if (output_val)
                    next_state = EJECT_SHIFT;

            EJECT_SHIFT:
                if (counter_ejection < Dimension)
                    next_state = EJECT_IDLE;
                else
                    next_state = DONE;

            EJECT_IDLE:
                if (out_new_val)
                    next_state = EJECT_SHIFT;

            DONE:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    /* ============================================================
     * Output Logic (COMBINATIONAL)
     * ============================================================ */
    always @(*) begin
        /* defaults */
        en_ifmap_counter   = 1'b0;
        en_weight_counter  = 1'b0;
        en_shift_reg_ifmap = {Dimension{1'b0}};
        en_shift_reg_weight= {Dimension{1'b0}};
        en_cntr            = 1'b0;

        en_in   = {Dimension*Dimension{1'b0}};
        en_psum = {Dimension*Dimension{1'b0}};
        en_out  = {Dimension*Dimension{1'b0}};

        ifmaps_sel       = {Dimension{1'b1}};
        output_val_count = 1'b0;
        done_all         = 1'b0;

        case (state)
            RAISE_EN: begin
                en_in   = {Dimension*Dimension{1'b1}};
                en_out  = {Dimension*Dimension{1'b1}};
                en_psum = {Dimension*Dimension{1'b1}};
            end

            LOAD: begin
                en_ifmap_counter   = 1'b1;
                en_weight_counter  = 1'b1;
                en_shift_reg_ifmap = {Dimension{1'b1}};
                en_shift_reg_weight= {Dimension{1'b1}};
                en_cntr            = 1'b1;
                en_in   = {Dimension*Dimension{1'b1}};
                en_psum = {Dimension*Dimension{1'b1}};
                en_out  = {Dimension*Dimension{1'b1}};
            end

            COMPUTE: begin
                en_cntr = 1'b1;
                en_in   = {Dimension*Dimension{1'b1}};
                en_psum = {Dimension*Dimension{1'b1}};
                en_out  = {Dimension*Dimension{1'b1}};
            end

            EJECT_WAIT: begin
                en_out = {Dimension*Dimension{1'b1}};
            end

            EJECT_SHIFT: begin
                output_val_count = 1'b1;
                en_out = {Dimension*Dimension{1'b1}};
            end

            EJECT_IDLE: begin
                output_val_count = 1'b1;
                en_out = {Dimension*Dimension{1'b1}};
            end

            DONE: begin
                done_all = 1'b1;
            end
        endcase
    end

endmodule
