#include "vector_add.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

int main() {
  constexpr unsigned int n = 1024;
  std::vector<ap_uint<32>> a(n);
  std::vector<ap_uint<32>> b(n);
  std::vector<ap_uint<32>> c(n);

  for (unsigned int i = 0; i < n; ++i) {
    a[i] = i;
    b[i] = i * 3;
  }

  vector_add(a.data(), b.data(), c.data(), n);

  for (unsigned int i = 0; i < n; ++i) {
    const ap_uint<32> expected = a[i] + b[i];
    if (c[i] != expected) {
      std::cerr << "Mismatch at i=" << i << ": got " << c[i] << " expected " << expected << '\n';
      return EXIT_FAILURE;
    }
  }

  std::cout << "vector_add_tb PASS\n";
  return EXIT_SUCCESS;
}
