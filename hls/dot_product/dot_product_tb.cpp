#include "ap_int.h"
#include <iostream>

// Declaration of the function under test
void dot_product(
    ap_int<8>  vec_a[8],
    ap_int<8>  vec_b[8],
    ap_int<32> *result,
    ap_uint<1> *busy
);

int main() {
    ap_int<8>  a[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    ap_int<8>  b[8] = {8, 7, 6, 5, 4, 3, 2, 1};
    ap_int<32> result = 0;
    ap_uint<1> busy   = 0;

    // Expected: 1*8 + 2*7 + 3*6 + 4*5 + 5*4 + 6*3 + 7*2 + 8*1
    //         = 8 + 14 + 18 + 20 + 20 + 18 + 14 + 8 = 120

    dot_product(a, b, &result, &busy);

    std::cout << "Result: " << result << std::endl;
    std::cout << "Expected: 120" << std::endl;

    if (result == 120) {
        std::cout << "PASS" << std::endl;
        return 0;
    } else {
        std::cout << "FAIL" << std::endl;
        return 1;
    }
}