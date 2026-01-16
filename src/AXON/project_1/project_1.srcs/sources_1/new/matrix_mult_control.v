module matrix_mult_control #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    /* -------- Shift Register Status -------- */
    input  wire done_ifmap,
    input  wire done_weight,

    /* -------- Systolic Array Status -------- */
    input  wire done_count,
    /* -------- Output Status -------- */
    input  wire output_val,
    input  wire out_new_val, // From counter, telling to shift. 

    /* -------- Shift Register Control -------- */
    output reg en_shift_reg_ifmap,
    output reg en_shift_reg_weight,

    /* -------- Systolic Array Control -------- */
    output reg en_cntr,
    output reg [Dimension*Dimension-1:0] en_in,
    output reg [Dimension*Dimension-1:0] en_out,
    output reg [Dimension*Dimension-1:0] en_psum,

    output reg [Dimension-1:0] ifmaps_sel,
    
    output reg output_val_count,
    output reg [Dimension-1:0] output_eject_ctrl
);

    /* ============================================================
     * State Encoding
     * ============================================================ */
    localparam IDLE    = 3'd0;
    localparam LOAD    = 3'd1;
    localparam COMPUTE = 3'd2;
    localparam EJECT  = 3'd3;
    localparam DONE    = 3'd4;

    reg [2:0] state, next_state;
    reg [4:0] counter_ejection = 0;
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
     * Next-State Logic
     * ============================================================ */
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = LOAD;
                    else next_state = IDLE;
            end
            LOAD: begin
                if (done_ifmap && done_weight)
                    next_state = COMPUTE;
                else
                    next_state = LOAD;
            end
            COMPUTE: begin
                if (done_count && output_val)
                    next_state = EJECT;
                else
                    next_state = COMPUTE;
            end
            EJECT: begin
                // If dimension of ejection is done, stop ejecting. 
                if (counter_ejection <= Dimension-1) begin
                    next_state = EJECT;
                end
                else next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    /* ============================================================
     * Output Logic (Moore FSM)
     * ============================================================ */
    // /* -------- Shift Register Control -------- */
    // output reg en_shift_reg_ifmap,
    // output reg en_shift_reg_weight,

    // /* -------- Systolic Array Control -------- */
    // output reg en_cntr,
    // output reg [Dimension*Dimension-1:0] en_in,
    // output reg [Dimension*Dimension-1:0] en_out,
    // output reg [Dimension*Dimension-1:0] en_psum,

    // output reg [Dimension-1:0] ifmaps_sel,
    
    // output wire output_val_count,
    // output reg [Dimension-1:0] output_eject_ctrl

    always @(*) begin
        /* ---------- defaults ---------- */
        en_shift_reg_ifmap     = 1'b0;
        en_shift_reg_weight    = 1'b0;
        en_cntr                = 1'b0;

        en_in                  = {Dimension*Dimension{1'b0}};
        en_psum                = {Dimension*Dimension{1'b0}};
        en_out                 = {Dimension*Dimension{1'b0}};

        ifmaps_sel             = {Dimension{1'b0}};
        output_val_count       = 1'b0;
        output_eject_ctrl      = {Dimension{1'b1}};
        case (state)
            /* ---------------- IDLE ---------------- */
            IDLE: begin
                // everything disabled
            end
            /* ---------------- LOAD ---------------- */
            LOAD: begin
                en_shift_reg_ifmap  = 1'b1;
                en_shift_reg_weight = 1'b1;
                en_cntr = 1'b1;
                // allow writing into PE input registers
                en_in    = {Dimension*Dimension{1'b1}};
                en_out   = {Dimension*Dimension{1'b1}};
                en_psum  = {Dimension*Dimension{1'b1}};
            end
            /* ---------------- COMPUTE ---------------- */
            COMPUTE: begin
                en_cntr = 1'b1;
                en_shift_reg_ifmap  = 1'b0;
                en_shift_reg_weight = 1'b0;
                en_in    = {Dimension*Dimension{1'b1}};
                en_psum  = {Dimension*Dimension{1'b1}};
                ifmaps_sel = {Dimension{1'b1}};

            end
            /* ---------------- EJECT ---------------- */
            EJECT: begin
                counter_ejection = counter_ejection + 1;
                output_val_count = 1'b1;
                en_in = {Dimension*Dimension{1'b0}};
                en_psum = {Dimension*Dimension{1'b0}};
                en_out = {Dimension*Dimension{1'b1}};
                en_cntr = 1'b0;
                output_val_count = 1'b1;
                output_eject_ctrl = output_eject_ctrl << 1;
            end
            /* ---------------- DONE ---------------- */
            DONE: begin
                // one clean cycle before returning to IDLE
            end
        endcase
    end

endmodule
