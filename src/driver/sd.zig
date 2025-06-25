const c = @cImport({
    @cInclude("pico.h");
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("hardware/gpio.h");
    @cInclude("hardware/spi.h");
});
// SD Card SPI commands
const SD_CMD0 = 0;
const SD_CMD1 = 1;
const SD_CMD8 = 8;
const SD_CMD9 = 9;
const SD_CMD10 = 10;
const SD_CMD12 = 12;
const SD_CMD16 = 16;
const SD_CMD17 = 17;
const SD_CMD18 = 18;
const SD_CMD24 = 24;
const SD_CMD25 = 25;
const SD_CMD32 = 32;
const SD_CMD33 = 33;
const SD_CMD38 = 38;
const SD_CMD55 = 55;
const SD_CMD58 = 58;
const SD_ACMD23 = 23;
const SD_ACMD41 = 41;

//SD Vard variants
const SD_TYPE_UNKNOWN = 0;
const SD_TYPE_V1 = 1;
const SD_TYPE_V2 = 2;
const SD_TYPE_SDHC = 3;

const SD_BLOCK_SIZE = 512;

// SD CART Response Types
const SD_R1_IDLE_STATE = 0x01;
const SD_R1_ERASE_RESET = 0x02;
const SD_R1_ILLEGAL_COMMAND = 0x04;
const SD_R1_COM_CRC_ERROR = 0x08;
const SD_R1_ERASE_SEQUENCE_ERROR = 0x10;
const SD_R1_ADDRESS_ERROR = 0x20;
const SD_R1_PARAMETER_ERROR = 0x40;

// SD Data Tokens
const SD_TOKEN_READ_START = 0xFE;
const SD_TOKEN_WRITE_START = 0xFE;
const SD_TOKEN_WRITE_MULTIPLE = 0xFC;
const SD_TOKEN_STOP_TRANSMISSION = 0xFD;

//errors
pub const SDError = error{
    InitializationFailed,
    CommandFailed,
    ReadFailed,
    WriteFailed,
    EraseFailed,
    InvalidResponse,
    Timeout,
    CardNotReady,
    UnsupportedCard,
};

pub const SD = struct {
    //pin def
    spi_inst: *c.spi_inst_t,
    cs_pin: u8,
    sck_pin: u8,
    mosi_pin: u8,
    miso_pin: u8,
    card_type: u8,
    block_count: u32,
    initalized: bool,

    const Self = @This();

    // Modify the init function to use slower speed initially:
    pub fn init(
        spi_inst: *c.spi_inst_t,
        cs_pin: u8,
        sck_pin: u8,
        mosi_pin: u8,
        miso_pin: u8,
        baudrate: u32,
    ) SDError!Self {
        var sd = Self{
            .spi_inst = spi_inst,
            .cs_pin = cs_pin,
            .sck_pin = sck_pin,
            .mosi_pin = mosi_pin,
            .miso_pin = miso_pin,
            .card_type = SD_TYPE_UNKNOWN,
            .block_count = 0,
            .initalized = false,
        };

        _ = c.spi_init(sd.spi_inst, 400000);

        // c.gpio_set_function(sd.cs_pin, c.GPIO_FUNC_SPI);
        c.gpio_set_function(sd.sck_pin, c.GPIO_FUNC_SPI);
        c.gpio_set_function(sd.mosi_pin, c.GPIO_FUNC_SPI);
        c.gpio_set_function(sd.miso_pin, c.GPIO_FUNC_SPI);

        c.gpio_init(sd.cs_pin);
        c.gpio_set_dir(sd.cs_pin, true);
        c.gpio_put(sd.cs_pin, true);
        // c.gpio_put(sd.mosi_pin, false);
        try sd.initializeCard();

        _ = c.spi_set_baudrate(sd.spi_inst, baudrate);

        sd.initalized = true;
        return sd;
    }
    pub fn deinit(self: *Self) void {
        if (self.initalized) {
            self.deselectSD();
            c.spi_deinit(self.spi_inst);
            self.initalized = false;
        }
    }
    //helpers for selecting and deselecting the SD card
    fn selectSD(self: *Self) void {
        c.gpio_put(self.cs_pin, false);
        c.sleep_ms(1);
    }
    fn deselectSD(self: *Self) void {
        c.gpio_put(self.cs_pin, true);
        c.sleep_ms(1);
    }
    //blocking transfer over SPI, also returns response
    fn spiTransfer(self: *Self, data: u8) SDError!u8 {
        var response: u8 = 0;
        _ = c.spi_write_read_blocking(self.spi_inst, &data, &response, 1);
        return response;
    }

    fn waitReady(self: *Self, timeout_ms: u32) SDError!void {
        const start_time = c.to_ms_since_boot(c.get_absolute_time());

        while (true) {
            if (try self.spiTransfer(0xFF) == 0xFF) {
                return;
            }

            const current_time = c.to_ms_since_boot(c.get_absolute_time());
            if (current_time - start_time > timeout_ms) {
                return SDError.Timeout;
            }
            c.sleep_ms(10);
        }
    }
    fn sendCommand(self: *Self, cmd: u8, arg: u32) SDError!u8 {

        //+------------+------------+------------+------------+------------+------------+
        //| 0x40+CMD   | ARG[31:24] | ARG[23:16] | ARG[15:8]  | ARG[7:0]   | CRC        |
        //+------------+------------+------------+------------+------------+------------+

        try self.waitReady(5000);
        _ = try self.spiTransfer(0x40 | cmd);
        _ = try self.spiTransfer(@intCast((arg >> 24) & 0xFF));
        _ = try self.spiTransfer(@intCast((arg >> 16) & 0xFF));
        _ = try self.spiTransfer(@intCast((arg >> 8) & 0xFF));
        _ = try self.spiTransfer(@intCast(arg & 0xFF));
        var crc: u8 = 0xFF;
        if (cmd == SD_CMD0) crc = 0x95;
        if (cmd == SD_CMD8) crc = 0x87;
        _ = try self.spiTransfer(crc);

        var response: u8 = 0xFF;
        for (0..10) |_| {
            response = try self.spiTransfer(0xFF);
            if ((response & 0x80) == 0) {
                break;
            }
        }
        return response;
    }
    fn sendAppCommand(self: *Self, cmd: u8, arg: u32) SDError!u8 {
        _ = try self.sendCommand(SD_CMD55, 0);
        return self.sendCommand(cmd, arg);
    }
    fn initializeCard(self: *Self) SDError!void {
        _ = c.printf("Starting SD card initialization\n");

        c.sleep_ms(100);
        self.deselectSD();

        _ = c.printf("Sending initial clock cycles\n");
        for (0..100) |_| {
            _ = try self.spiTransfer(0xFF);
        }

        self.selectSD();
        _ = c.printf("Sending CMD0\n");
        var response = try self.sendCommand(SD_CMD0, 0);
        _ = c.printf("CMD0 response: 0x%02X\n", response);

        if (response != SD_R1_IDLE_STATE) {
            self.deselectSD();
            return SDError.InitializationFailed;
        }

        // Send CMD8 to check if card is v2
        _ = c.printf("Sending CMD8\n");
        response = try self.sendCommand(SD_CMD8, 0x000001AA);
        _ = c.printf("CMD8 response: 0x%02X\n", response);

        //check if card is >=v2
        if (response == SD_R1_IDLE_STATE) {
            var ocr: [4]u8 = undefined;
            for (0..4) |i| {
                ocr[i] = try self.spiTransfer(0xFF);
            }
            _ = c.printf("CMD8 OCR: 0x%02X%02X%02X%02X\n", ocr[0], ocr[1], ocr[2], ocr[3]);

            if (ocr[2] == 0x01 and ocr[3] == 0xAA) {
                var timeout: u32 = 1000;
                while (timeout > 0) : (timeout -= 1) {
                    response = try self.sendAppCommand(SD_ACMD41, 0x40000000);
                    if (response == 0) break;
                    c.sleep_ms(1);
                }
                if (timeout == 0) {
                    self.deselectSD();
                    return SDError.InitializationFailed;
                }
                //check if SDHC
                response = try self.sendCommand(SD_CMD58, 0);
                if (response == 0) {
                    for (0..4) |i| {
                        ocr[i] = try self.spiTransfer(0xFF);
                    }

                    if ((ocr[0] & 0x40) != 0) {
                        self.card_type = SD_TYPE_SDHC;
                    } else {
                        self.card_type = SD_TYPE_V2;
                    }
                }
            } else {
                self.deselectSD();
                return SDError.InitializationFailed;
            }
        } else {
            //card is v1 or not responsind
            var timeout: u32 = 1000;
            while (timeout > 0) : (timeout -= 1) {
                response = try self.sendAppCommand(SD_ACMD41, 0);
                if (response == 0) break;
                c.sleep_ms(1);
            }

            if (timeout > 0) {
                self.card_type = SD_TYPE_V1;
            } else {
                self.deselectSD();
                return SDError.UnsupportedCard;
            }
        }

        if (self.card_type != SD_TYPE_SDHC) {
            response = try self.sendCommand(SD_CMD16, SD_BLOCK_SIZE);
            if (response != 0) {
                self.deselectSD();
                return SDError.InitializationFailed;
            }
        }

        self.deselectSD();
        _ = c.printf("SD card initialized successfully, type: %d\n", self.card_type);
    }
    pub fn readBlock(self: *Self, block_addr: u32, buffer: []u8) SDError!void {
        if (!self.initalized or buffer.len < SD_BLOCK_SIZE) {
            return SDError.ReadFailed;
        }
        self.selectSD();
        var addr = block_addr;
        if (self.card_type != SD_TYPE_SDHC) {
            addr *= SD_BLOCK_SIZE;
        }
        const response = try self.sendCommand(SD_CMD17, addr);
        if (response != 0) {
            self.deselectSD();
            return SDError.ReadFailed;
        }

        var token: u8 = 0xFF;
        var timeout: u32 = 200;
        while (timeout > 0) : (timeout -= 1) {
            token = try self.spiTransfer(0xFF);
            if (token != 0xFF) break;
            c.sleep_ms(1);
        }
        if (token != SD_TOKEN_READ_START) {
            self.deselectSD();
            return SDError.ReadFailed;
        }
        for (0..SD_BLOCK_SIZE) |i| {
            buffer[i] = try self.spiTransfer(0xFF);
        }

        _ = try self.spiTransfer(0xFF);
        _ = try self.spiTransfer(0xFF);
        self.deselectSD();
    }
    pub fn writeBlock(self: *Self, block_addr: u32, buffer: []u8) SDError!void {
        if (!self.initalized or buffer.len < SD_BLOCK_SIZE) {
            return SDError.WriteFailed;
        }
        self.selectSD();
        var addr = block_addr;
        if (self.card_type != SD_TYPE_SDHC) {
            addr *= SD_BLOCK_SIZE;
        }
        const response = try self.sendCommand(SD_CMD24, addr);
        if (response != 0) {
            self.deselectSD();
            return SDError.WriteFailed;
        }
        _ = try self.spiTransfer(SD_TOKEN_WRITE_START);

        for (0..SD_BLOCK_SIZE) |i| {
            _ = try self.spiTransfer(buffer[i]);
        }

        _ = try self.spiTransfer(0xFF);
        _ = try self.spiTransfer(0xFF);

        const data_response = try self.spiTransfer(0xFF);
        if ((data_response & 0x1F) != 0x05) {
            self.deselectSD();
            return SDError.WriteFailed;
        }

        try self.waitReady(500);

        self.deselectSD();
    }
    pub fn getCardInfo(self: *Self) struct { card_type: u8, blocks: u32 } {
        return .{
            .card_type = self.card_type,
            .blocks = self.block_count,
        };
    }
};
