// main.c  PicoRV32 SoC firmware
// Peripheral map:
//   0x20000000  UART TX data
//   0x20000004  UART TX status (bit 0 = tx_busy)
//   0x30000000  GPIO output
//   0x40000000  dot_product accelerator (HLS, AXI-Lite)
//
// Accelerator register map (from HLS synthesis report):
//   0x40000000  CTRL       bit0=ap_start  bit1=ap_done  bit2=ap_idle
//   0x40000010  vec_a[0]   bits[7:0]
//   0x40000018  vec_a[1]
//   0x40000020  vec_a[2]
//   0x40000028  vec_a[3]
//   0x40000030  vec_a[4]
//   0x40000038  vec_a[5]
//   0x40000040  vec_a[6]
//   0x40000048  vec_a[7]
//   0x40000050  vec_b[0]   bits[7:0]
//   0x40000058  vec_b[1]
//   0x40000060  vec_b[2]
//   0x40000068  vec_b[3]
//   0x40000070  vec_b[4]
//   0x40000078  vec_b[5]
//   0x40000080  vec_b[6]
//   0x40000088  vec_b[7]
//   0x40000090  result     bits[31:0] read-only
//   0x400000a0  busy       bit0 read-only

#define UART_DATA    ((volatile unsigned char *)0x20000000)
#define UART_STATUS  ((volatile unsigned int  *)0x20000004)
#define GPIO_BASE    ((volatile unsigned int  *)0x30000000)

#define ACCEL_CTRL   ((volatile unsigned int *)0x40000000)
#define ACCEL_A(i)   ((volatile unsigned int *)(0x40000010 + (i) * 0x8))
#define ACCEL_B(i)   ((volatile unsigned int *)(0x40000050 + (i) * 0x8))
#define ACCEL_RESULT ((volatile unsigned int *)0x40000090)

void uart_putchar(char c)
{
    while (*UART_STATUS & 0x1);
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

// dot_product accelerator driver
// loads two INT8 vectors, starts accelerator, polls ap_done, returns result
unsigned int accel_dot_product(signed char *a, signed char *b)
{
    int i;

    // load vec_a and vec_b, one element per register
    // each register is 32-bit but only bits[7:0] are used
    for (i = 0; i < 8; i++) {
        *ACCEL_A(i) = (unsigned int)(unsigned char)a[i];
        *ACCEL_B(i) = (unsigned int)(unsigned char)b[i];
    }

    // write ap_start (bit 0) to kick off computation
    *ACCEL_CTRL = 0x1;

    // poll ap_done (bit 1) — clears on read per HLS ap_ctrl_hs protocol
    while (!(*ACCEL_CTRL & 0x2));

    return *ACCEL_RESULT;
}

int main(void)
{
    unsigned int result;

    gpio_write(0x1);

    uart_print("\r\n");
    uart_print("================================\r\n");
    uart_print("  PicoRV32 SoC  C Runtime OK   \r\n");
    uart_print("================================\r\n");
    uart_print("\r\n");

    // Test 1: known result
    // a = {1,2,3,4,5,6,7,8}  b = {8,7,6,5,4,3,2,1}
    // expected: 1*8+2*7+3*6+4*5+5*4+6*3+7*2+8*1 = 120
    signed char a[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    signed char b[8] = {8, 7, 6, 5, 4, 3, 2, 1};

    uart_print("Running dot product accelerator...\r\n");
    result = accel_dot_product(a, b);

    uart_print("Result = ");
    uart_print_uint(result);
    uart_print("  (expected 120)\r\n");

    if (result == 120) {
        uart_print("PASS\r\n");
        gpio_write(0x00000001);
    } else {
        uart_print("FAIL\r\n");
        gpio_write(0xDEADBEEF);
    }

    // Test 2: all ones
    // a = {1,1,1,1,1,1,1,1}  b = {1,1,1,1,1,1,1,1}  expected: 8
    signed char a2[8] = {1, 1, 1, 1, 1, 1, 1, 1};
    signed char b2[8] = {1, 1, 1, 1, 1, 1, 1, 1};

    result = accel_dot_product(a2, b2);
    uart_print("Result = ");
    uart_print_uint(result);
    uart_print("  (expected 8)\r\n");

    uart_print("\r\nDone. Halting.\r\n");
    gpio_write(0xDEADBEEF);

    while (1);
    return 0;
}
