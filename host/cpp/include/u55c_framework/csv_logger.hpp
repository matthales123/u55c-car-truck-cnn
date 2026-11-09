#pragma once

#include <string>
#include <vector>

#include "u55c_framework/types.hpp"

namespace u55c_framework {

void append_rows_csv(const std::string& path, const std::vector<BenchmarkRow>& rows);

}  // namespace u55c_framework
