#pragma once

#include <chrono>

namespace u55c_framework {

using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;

inline double elapsed_ms(const TimePoint& start, const TimePoint& end) {
  return std::chrono::duration<double, std::milli>(end - start).count();
}

}  // namespace u55c_framework
