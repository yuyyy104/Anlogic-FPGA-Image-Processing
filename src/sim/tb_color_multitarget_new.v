`timescale 1ns/1ps
// End-to-end detector test for the new palette and object classes.
// Object classes: 1 sphere, 2 cube. Palette: 1 red, 2 yellow, 3 green.
module tb_color_multitarget_new;
    localparam integer W = 512;
    localparam integer H = 256;

    reg clk = 0, rst_n = 0;
    reg [23:0] rgb = 0;
    reg [4:0] timing = 0;
    wire valid, overflow;
    wire [7:0] target_count;
    wire [11:0] colors, shapes;
    wire [79:0] areas;
    wire [191:0] boxes;
    reg [23:0] image [0:W*H-1];

    integer x, y, dx, dy, i, timeout;
    integer errors = 0, checks = 0;
    reg test_done = 0;

    color_multitarget #(.H_ACTIVE(W), .V_ACTIVE(H)) dut (
        .clk(clk), .rst_n(rst_n), .rgb(rgb), .timing(timing),
        .valid(valid), .overflow(overflow), .target_count(target_count),
        .colors(colors), .shapes(shapes), .areas(areas), .boxes(boxes)
    );

    always #5 clk = ~clk;

    task check;
        input [255:0] tag;
        input cond;
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s", tag);
            end
        end
    endtask

    function has_target;
        input [2:0] color;
        input [2:0] shape;
        integer j;
        begin
            has_target = 0;
            for (j = 0; j < 4; j = j + 1)
                if (areas[j*20+:20] != 0 &&
                    colors[j*3+:3] == color && shapes[j*3+:3] == shape)
                    has_target = 1;
        end
    endfunction

    initial begin
        for (y = 0; y < H; y = y + 1)
            for (x = 0; x < W; x = x + 1)
                image[y*W+x] = 24'h606060;

        // Red sphere.
        for (y = 30; y < 110; y = y + 1)
            for (x = 40; x < 120; x = x + 1) begin
                dx = x - 80; dy = y - 70;
                if (dx*dx + dy*dy <= 38*38) image[y*W+x] = 24'h1e1614;
            end

        // Yellow cube.
        for (y = 38; y < 102; y = y + 1)
            for (x = 182; x < 258; x = x + 1)
                image[y*W+x] = 24'hdcd223;

        // Green sphere.
        for (y = 30; y < 110; y = y + 1)
            for (x = 340; x < 420; x = x + 1) begin
                dx = x - 380; dy = y - 70;
                if (dx*dx + dy*dy <= 38*38) image[y*W+x] = 24'h23dc2d;
            end

        // Red cube. A second component of the same colour must remain distinct.
        for (y = 158; y < 222; y = y + 1)
            for (x = 182; x < 254; x = x + 1)
                image[y*W+x] = 24'h5a2018;

        // Sub-component colour noise must not become a fifth target.
        for (y = 232; y < 240; y = y + 1)
            for (x = 304; x < 312; x = x + 1)
                image[y*W+x] = 24'hdc2d23;

        repeat (5) @(negedge clk);
        rst_n = 1;
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                @(negedge clk);
                rgb = image[y*W+x];
                timing = {2'b00, 1'b1, (x == 0 && y == 0), (x == W-1)};
            end
            @(negedge clk);
            timing = 0;
            rgb = 0;
        end

        timeout = 0;
        while (!valid && timeout < 2000000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        repeat (2) @(negedge clk);

        check("detector completed", valid === 1'b1 && overflow === 1'b0);
        check("four targets", target_count === 8'd4);
        check("red sphere", has_target(3'd1, 3'd1));
        check("yellow cube", has_target(3'd2, 3'd2));
        check("green sphere", has_target(3'd3, 3'd1));
        check("red cube", has_target(3'd1, 3'd2));

        test_done = 1;
        if (errors == 0)
            $display("PASS color_multitarget_new red_sphere yellow_cube green_sphere red_cube small_noise_filtered checks=%0d", checks);
        else
            $display("FAIL color_multitarget_new checks=%0d errors=%0d", checks, errors);
        $finish;
    end
endmodule
