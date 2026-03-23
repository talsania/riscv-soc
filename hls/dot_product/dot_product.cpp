// Author: Krishang Talsania
// Email: talsania.k@outlook.com

// Result: 8 DSP, 8x mac_unit, each II=1 pipelined, latency 30ns per unit
//
// v1 (loop + UNROLL pragma)
//   ap_int<32> acc = 0;
//   for (int i = 0; i < 8; i++) {
//       #pragma HLS UNROLL
//       acc += vec_a[i] * vec_b[i];
//   }
//   Result: 4 DSP, 40ns - HLS merged mults into DSP cascade chain
//
// v2 (mac_unit function, INLINE off, PIPELINE II=1, BIND_OP inside mac_unit)
//   wrapped multiply in separate function with BIND_OP in same scope as product
//   #pragma HLS BIND_OP variable=product op=mul impl=dsp latency=3
//   Result: 8 DSP, 1 per unit, II=1, latency 30ns - correct
//
// Debug rule: BIND_OP must be in the same scope as the variable being bound.
//             INLINE off is required or HLS merges all instances into one unit.

#include "ap_int.h"

static void mac_unit(
    ap_int<8>  a,
    ap_int<8>  b,
    ap_int<32> &accum
) {
    #pragma HLS INLINE off
    #pragma HLS PIPELINE II=1

    ap_int<16> product;
    #pragma HLS BIND_OP variable=product op=mul impl=dsp latency=3

    product = (ap_int<16>)a * (ap_int<16>)b;
    accum = (ap_int<32>)product;
}

void dot_product(
    ap_int<8>  vec_a[8],
    ap_int<8>  vec_b[8],
    ap_int<32> *result,
    ap_uint<1> *busy
) {
    #pragma HLS INTERFACE s_axilite port=vec_a  bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=vec_b  bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=result bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=busy   bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=return bundle=CTRL

    #pragma HLS ARRAY_PARTITION variable=vec_a type=complete dim=1
    #pragma HLS ARRAY_PARTITION variable=vec_b type=complete dim=1

    ap_int<32> acc0, acc1, acc2, acc3;
    ap_int<32> acc4, acc5, acc6, acc7;

    mac_unit(vec_a[0], vec_b[0], acc0);
    mac_unit(vec_a[1], vec_b[1], acc1);
    mac_unit(vec_a[2], vec_b[2], acc2);
    mac_unit(vec_a[3], vec_b[3], acc3);
    mac_unit(vec_a[4], vec_b[4], acc4);
    mac_unit(vec_a[5], vec_b[5], acc5);
    mac_unit(vec_a[6], vec_b[6], acc6);
    mac_unit(vec_a[7], vec_b[7], acc7);

    ap_int<33> sum01 = acc0 + acc1;
    ap_int<33> sum23 = acc2 + acc3;
    ap_int<33> sum45 = acc4 + acc5;
    ap_int<33> sum67 = acc6 + acc7;

    ap_int<34> sum0123 = sum01 + sum23;
    ap_int<34> sum4567 = sum45 + sum67;

    *result = (ap_int<32>)(sum0123 + sum4567);
    *busy = 0;
}