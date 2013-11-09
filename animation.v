`define VGA_WIDTH 160
`define VGA_HEIGHT 120
`define IMG_WIDTH 16
`define IMG_HEIGHT 16

//top-level module
module animation(
    input CLOCK_50,                     //  On Board 50 MHz
    input[3:0] KEY,                     //  Push Button[3:0]
    input[17:0] SW,                     //  DPDT Switch[17:0]
    output VGA_CLK,                     //  VGA Clock
    output VGA_HS,                          //  VGA H_SYNC
    output VGA_VS,                          //  VGA V_SYNC
    output VGA_BLANK,                       //  VGA BLANK
    output VGA_SYNC,                        //  VGA SYNC
    output[9:0] VGA_R,                  //  VGA Red[9:0]
    output[9:0] VGA_G,                  //  VGA Green[9:0]
    output[9:0] VGA_B,                  //  VGA Blue[9:0]
    output[7:0] LEDG,
    output[17:0] LEDR);
    
    wire Clock, Reset, Blank, Plot, X_en, Y_en, Erase, VGA_en;
    reg Draw_start, Draw_done, Animate_done;
    wire[7:0] X, X_out;
    wire[6:0] Y, Y_out;
    wire[2:0] C_out;
    
    assign Clock = CLOCK_50;
    assign Reset = ~KEY[0];
    assign Blank = ~KEY[1];
    assign Plot = ~KEY[2];
    assign Animate = ~KEY[3];
    assign X = SW[7:0];
    assign Y = SW[14:8];
    
    Datapath(Clock, Reset, X, X_en, Y, Y_en, Erase, X_out, Y_out, C_out);
    FSM(Blank, Plot, Animate, Reset, X_en, Y_en, Erase, VGA_en, LEDG[1:0]);
    
    vga_adapter VGA(
            .resetn(1'b1),
            .clock(CLOCK_50),
            .colour(C_out),
            .x(X_out),
            .y(Y_out),
            .plot(VGA_en),
            /* Signals for the DAC to drive the monitor. */
            .VGA_R(VGA_R),
            .VGA_G(VGA_G),
            .VGA_B(VGA_B),
            .VGA_HS(VGA_HS),
            .VGA_VS(VGA_VS),
            .VGA_BLANK(VGA_BLANK),
            .VGA_SYNC(VGA_SYNC),
            .VGA_CLK(VGA_CLK));
        defparam VGA.RESOLUTION = "160x120";
        defparam VGA.MONOCHROME = "FALSE";
        defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
        //defparam VGA.BACKGROUND_IMAGE = "display.mif";
endmodule

module Datapath(input Clock, Reset, input[7:0] X, X_en, input[6:0] Y, Y_en, Erase, 
                    output reg[7:0] X_out = -1, output reg[6:0] Y_out = 0, output reg[2:0] C_out = 0);
    reg[7:0] address = 0;
    wire Clock_60Hz;
    wire[7:0] X_anm;
    reg[7:0] X_off;
    wire[6:0] Y_anm;
    reg[6:0] Y_off;
    wire[2:0] color;
    
    rom(address, Clock, color);
    _60HzClock(Clock, Clock_60Hz);
    Animator(Clock_60Hz, Reset, ~Erase, X_anm, Y_anm);
    
    always @ (posedge Clock or posedge Reset) begin
        if (Reset) begin        
            X_off = 0;
            Y_off = 0;
            address = 0;
            X_out = 0;
            Y_out = 0;
            C_out = 0;
        end else begin
            if (X_en) X_off = X;
            else X_off = X_anm;
            if (Y_en) Y_off = Y;
            else Y_off = Y_anm;
            
            X_out = X_out + 1;
            if (X_out == `VGA_WIDTH) begin
                X_out = 0;
                Y_out = Y_out + 1;
                if (Y_out == `VGA_HEIGHT) begin
                    Y_out = 0;
                end
            end
            
            if (X_out == X_off + (address % `IMG_WIDTH) & 
            Y_out == Y_off + (address / `IMG_HEIGHT) & ~Erase) begin
            
                C_out = color;
                if (address < 255) address = address + 1;
                else address = 0;
            end else begin
                C_out = 3'b000;
            end
        end
    end
endmodule

module FSM(input Blank, Plot, Animate, Reset, output reg X_en, Y_en, Erase = 0, VGA_en, output reg[2:0] y);
    //FSM states
    parameter BLANK = 0, DRAW = 1, ANIMATE = 2, IDLE = 3;
    reg Draw_start = 0, Draw_done = 0, Animate_start = 0;
    //Current FSM state
    reg[2:0] Y;
    
    always @ (*) begin
        Draw_start = Plot & ~Draw_start;
        Animate_start = Animate & ~Animate_start;
        
        if (Blank) Y = BLANK;
        else if (Animate_start) Y = ANIMATE;
        else if (Draw_start) Y = DRAW;
        else if (Draw_done) Y = IDLE;
        y = Y;
        
        Erase = (y == BLANK);
        VGA_en = (y != IDLE);
        
        if (y == DRAW) begin
            X_en = 1;
            Y_en = 1;
        end else begin
            X_en = 0;
            Y_en = 0;
        end
        
        //Reset all indicator signals
        Draw_start = 0;
        Draw_done = 0;
        Animate_start = 0;
    end
endmodule

module _60HzClock(input Clock, output reg EN = 0);
    //20 bits required to store largest cnt value (833333)
    reg[19:0] cnt = 0;
    always @ (posedge Clock) begin
        cnt = cnt + 1;
        //83333 clock cycles is 60 Hz
        if (cnt == 833333) begin
            cnt = 0;
            EN = ~EN;
        end
    end
endmodule

module Animator(input Clock, Reset, EN, output reg[7:0] X_anm = 0, output reg[6:0] Y_anm = 0);
    //Indicates direction of animation
    reg X_fwd = 1, Y_fwd = 1; 
    //Clock for this module should be 60Hz
    always @ (posedge Clock or posedge Reset) begin
        if (Reset == 1) begin
            X_anm = 0; 
            Y_anm = 0;
            X_fwd = 1;
            Y_fwd = 1;
        end else begin
            if (EN) begin
                if (X_fwd) X_anm = X_anm + 1;
                else X_anm = X_anm - 1;
                if (Y_fwd) Y_anm = Y_anm + 1;
                else Y_anm = Y_anm - 1;
                
                if (X_anm == (`VGA_WIDTH - `IMG_WIDTH)) X_fwd = 0;
                else if (X_anm == 0) X_fwd = 1;
                if (Y_anm == (`VGA_HEIGHT - `IMG_HEIGHT)) Y_fwd = 0;
                else if (Y_anm == 0) Y_fwd = 1;
            end
        end //end if (EN)
    end //end always
endmodule

