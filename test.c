#define GPIO_BASE         0x40014000
#define SIO_BASE          0xd0000000
#define UART0_BASE        0x40034000
#define UART0_DR_OFFSET   0x00
#define UART0_FR_OFFSET   0x18
#define UART0_IBRD_OFFSET 0x24
#define UART0_FBRD_OFFSET 0x28
#define UART0_LCRH_OFFSET 0x2C
#define UART0_CR_OFFSET   0x30

#define GPIO_OE_OFFSET    0x20
#define GPIO_OUT_OFFSET   0x10

#define LED_PIN           25

static inline void delay(volatile unsigned int count) {
    while (count--) {
        __asm volatile ("nop");
    }
}

// void uart0_init(void) {
//     volatile unsigned int *uart_cr   = (unsigned int *)(UART0_BASE + UART0_CR_OFFSET);
//     volatile unsigned int *uart_ibrd = (unsigned int *)(UART0_BASE + UART0_IBRD_OFFSET);
//     volatile unsigned int *uart_fbrd = (unsigned int *)(UART0_BASE + UART0_FBRD_OFFSET);
//     volatile unsigned int *uart_lcrh = (unsigned int *)(UART0_BASE + UART0_LCRH_OFFSET);

//     *uart_cr = 0; // Disable UART0
//     *uart_ibrd = 26; // 115200 baud for 48MHz clk
//     *uart_fbrd = 3;
//     *uart_lcrh = (3 << 5); // 8N1
//     *uart_cr = (1 << 0) | (1 << 8) | (1 << 9); // Enable UART, TX, RX
// }

void uart0_putc(char c) {
    volatile unsigned int *uart_fr = (unsigned int *)(UART0_BASE + UART0_FR_OFFSET);
    volatile unsigned int *uart_dr = (unsigned int *)(UART0_BASE + UART0_DR_OFFSET);
    while (*uart_fr & (1 << 5)); // Wait until TXFF is clear
    *uart_dr = c;
}

void uart0_puts(const char *s) {
    while (*s) {
        uart0_putc(*s++);
    }
}

void _start(void *ctx) {
    volatile unsigned int *gpio_oe = (unsigned int *)(SIO_BASE + GPIO_OE_OFFSET);
    volatile unsigned int *gpio_out = (unsigned int *)(SIO_BASE + GPIO_OUT_OFFSET);

    *gpio_oe |= (1 << LED_PIN);



    while (1) {
        *gpio_out |= (1 << LED_PIN);

        uart0_putc('L');
        uart0_putc('E');
        uart0_putc('D');
        uart0_putc('\n');
        delay(10);

        *gpio_out &= ~(1 << LED_PIN);

        uart0_putc('O');
        delay(10);
    }

    // return 0;
}