#pragma once

#include <vector>

#include "u55c_framework/types.hpp"

namespace u55c_framework {

std::vector<BenchmarkRow> run_benchmark(const BenchmarkConfig& cfg);

}  // namespace u55c_framework
