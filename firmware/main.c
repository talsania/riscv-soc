/* =============================================================================
 * main.c  —  PicoRV32 SoC  (polls UART tx_busy before each write)
 *
 * Peripheral map:
 *   0x20000000  UART TX data   — write byte to transmit
 *   0x20000004  UART TX status — bit 0 = tx_busy (1=busy, 0=ready)
 *   0x30000000  GPIO           — 32-bit output
 *
 * uart_tx.v accepts a byte and sets tx_busy=1 for ~434 clocks (115200 baud).
 * We poll the status register so we never drop a byte.
 * No division/modulo used anywhere — rv32i has no hardware divider.
 * =============================================================================
 */

#define UART_DATA   ((volatile unsigned char *)0x20000000)
#define UART_STATUS ((volatile unsigned int  *)0x20000004)
#define GPIO_BASE   ((volatile unsigned int  *)0x30000000)

/* -------------------------------------------------------------------------- */
/* Drivers                                                                     */
/* -------------------------------------------------------------------------- */

void uart_putchar(char c)
{
    while (*UART_STATUS & 0x1);   /* spin while tx_busy == 1 */
    *UART_DATA = (unsigned char)c;
}

void uart_print(const char *s)
{
    while (*s) uart_putchar(*s++);
}

void gpio_write(unsigned int val)
{
    *GPIO_BASE = val;
}

/* -------------------------------------------------------------------------- */
/* Integer printers — no % or / (rv32i has no hardware divide)                */
/* -------------------------------------------------------------------------- */

static const char hex_chars[] = "0123456789ABCDEF";

void uart_print_hex(unsigned int val)
{
    int i;
    uart_print("0x");
    for (i = 28; i >= 0; i -= 4)
        uart_putchar(hex_chars[(val >> i) & 0xF]);
}

void uart_print_uint(unsigned int val)
{
    static const unsigned int powers[] = {
        1000000000u, 100000000u, 10000000u, 1000000u,
        100000u, 10000u, 1000u, 100u, 10u, 1u
    };
    int i, printed = 0;
    if (val == 0) { uart_putchar('0'); return; }
    for (i = 0; i < 10; i++) {
        char digit = '0';
        while (val >= powers[i]) { val -= powers[i]; digit++; }
        if (digit != '0' || printed) { uart_putchar(digit); printed = 1; }
    }
}

/* -------------------------------------------------------------------------- */
/* main                                                                        */
/* -------------------------------------------------------------------------- */
int main(void)
{
    unsigned int counter = 0;

    gpio_write(0x1);

    uart_print("\r\n");
    uart_print("================================\r\n");
    uart_print("  PicoRV32 SoC  C Runtime OK   \r\n");
    uart_print("================================\r\n");
    uart_print("UART poll: tx_busy @ 0x20000004\r\n");
    uart_print("\r\n");

    uart_print("Counting:\r\n");
    while (1) {
        gpio_write(counter & 1);
        uart_print("  count = ");
        uart_print_uint(counter);
        uart_print("  hex = ");
        uart_print_hex(counter);
        uart_print("\r\n");
        counter++;
        if (counter >= 2) {
            uart_print("\r\nDone. Halting.\r\n");
            gpio_write(0xDEADBEEF);
            break;
        }
    }

    while (1);
    return 0;
}