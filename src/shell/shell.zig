const std = @import("std");
const c = @cImport({
    @cInclude("pico/stdlib.h");
    @cInclude("pico/stdio.h");
    @cInclude("stdio.h");
    @cInclude("hardware/uart.h");
});

//TODO: clean up, by moving helper functions to diff place
//yes this is alil messy, but i clean it up later
const MAX_COMMAND_LENGTH = 256;
const MAX_ARGS = 16;

const Command = struct {
    name: []const u8,
    args: [MAX_ARGS][]const u8,
    arg_count: usize,
};

const Shell = struct {
    buffer: [MAX_COMMAND_LENGTH]u8,
    buffer_pos: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .buffer = [_]u8{0} ** MAX_COMMAND_LENGTH,
            .buffer_pos = 0,
        };
    }

    pub fn run(self: *Self) void {
        self.printPrompt();

        while (true) {
            // hopefully stdio works rather than diret uart
            const ch_result = c.getchar_timeout_us(1000);
            if (ch_result != c.PICO_ERROR_TIMEOUT) {
                const ch: u8 = @intCast(ch_result);
                self.handleChar(ch);
            }
        }
    }

    fn printPrompt(self: *Self) void {
        _ = self;
        _ = c.printf("> ");
    }

    fn handleChar(self: *Self, ch: u8) void {
        switch (ch) {
            '\r', '\n' => { //handle returns and such
                _ = c.printf("\r\n");
                self.processCommand();
                self.clearBuffer();
                self.printPrompt();
            }, //FINALLY BACKSPACE IN UART OMG
            '\x08', 0x7F => {
                if (self.buffer_pos > 0) {
                    self.buffer_pos -= 1;
                    _ = c.printf("\x08 \x08");
                }
            },
            0x20...0x7E => {
                if (self.buffer_pos < MAX_COMMAND_LENGTH - 1) {
                    self.buffer[self.buffer_pos] = ch;
                    self.buffer_pos += 1;
                    _ = c.printf("%c", ch);
                }
            },
            else => {},
        }
    }

    fn clearBuffer(self: *Self) void {
        self.buffer_pos = 0;
        @memset(&self.buffer, 0);
    }

    fn processCommand(self: *Self) void {
        if (self.buffer_pos == 0) return;

        const command = self.parseCommand();
        self.executeCommand(command);
    }

    fn parseCommand(self: *Self) Command {
        var cmd = Command{
            .name = "",
            .args = [_][]const u8{""} ** MAX_ARGS,
            .arg_count = 0,
        };

        var start: usize = 0;
        var i: usize = 0;
        var in_word = false;

        while (i < self.buffer_pos) {
            const ch = self.buffer[i];

            if (ch == ' ' or ch == '\t') {
                if (in_word) {
                    const word = self.buffer[start..i];
                    if (cmd.name.len == 0) {
                        cmd.name = word;
                    } else if (cmd.arg_count < MAX_ARGS) {
                        cmd.args[cmd.arg_count] = word;
                        cmd.arg_count += 1;
                    }
                    in_word = false;
                }
            } else {
                if (!in_word) {
                    start = i;
                    in_word = true;
                }
            }
            i += 1;
        }

        if (in_word) {
            const word = self.buffer[start..i];
            if (cmd.name.len == 0) {
                cmd.name = word;
            } else if (cmd.arg_count < MAX_ARGS) {
                cmd.args[cmd.arg_count] = word;
                cmd.arg_count += 1;
            }
        }

        return cmd;
    }

    fn executeCommand(self: *Self, cmd: Command) void {
        if (std.mem.eql(u8, cmd.name, "echo")) {
            self.cmdEcho(cmd);
        } else if (std.mem.eql(u8, cmd.name, "cd")) {
            self.cmdCd(cmd);
        } else if (std.mem.eql(u8, cmd.name, "help")) {
            self.cmdHelp(cmd);
        } else if (std.mem.eql(u8, cmd.name, "exit")) {
            self.cmdExit(cmd);
        } else if (cmd.name.len > 0) {
            _ = c.printf("Command not found: %.*s\r\n", @as(c_int, @intCast(cmd.name.len)), cmd.name.ptr);
        }
    }

    fn cmdEcho(self: *Self, cmd: Command) void {
        _ = self;

        for (0..cmd.arg_count) |i| {
            if (i > 0) _ = c.printf(" ");
            _ = c.printf("%.*s", @as(c_int, @intCast(cmd.args[i].len)), cmd.args[i].ptr);
        }
        _ = c.printf("\r\n");
    }

    fn cmdCd(self: *Self, cmd: Command) void {
        _ = self;

        if (cmd.arg_count == 0) {
            _ = c.printf("cd: missing argument\r\n");
        } else {
            _ = c.printf("cd: changing dir ok (dummy)\r\n", @as(c_int, @intCast(cmd.args[0].len)), cmd.args[0].ptr);
        }
    }

    fn cmdHelp(self: *Self, cmd: Command) void {
        _ = self;
        _ = cmd;

        _ = c.printf("Available commands:\r\n");
        _ = c.printf("NOTE: most of these are dummies and yet to be implemented fully\r\n");
        _ = c.printf("  echo <args>  - echo arguments\r\n");
        _ = c.printf("  cd <dir>    - change directory\r\n");
        _ = c.printf("  help        - help\r\n");
        _ = c.printf("  exit       - exit\r\n");
    }

    fn cmdExit(self: *Self, cmd: Command) void {
        _ = self;
        _ = cmd;

        _ = c.printf("Exitting~\r\n");
    }
};

pub fn initShell() void {
    _ = c.stdio_init_all();

    var shell = Shell.init();
    shell.run();
}
