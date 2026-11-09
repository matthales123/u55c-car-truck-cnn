#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace u55c_framework {

enum class RunMode {
  DryRun,
  CpuRef,
  Hardware,
};

struct BenchmarkConfig {
  RunMode mode = RunMode::DryRun;
  std::string xclbin_path;
  std::string kernel_name = "vector_add";
  std::string input_f32_bin;
  std::string output_u32_bin;
  std::uint32_t device_index = 0;
  std::size_t elements = 1 << 20;
  std::size_t iterations = 10;
  bool verify = true;
  std::uint32_t seed = 1;
};

struct BenchmarkRow {
  std::string timestamp_utc;
  std::string mode;
  std::string kernel;
  std::uint32_t device_index = 0;
  std::size_t elements = 0;
  std::size_t iteration = 0;
  bool verify_ok = false;
  double h2d_ms = 0.0;
  double kernel_ms = 0.0;
  double d2h_ms = 0.0;
  double total_ms = 0.0;
  double throughput_gbps = 0.0;
};

const char* run_mode_string(RunMode mode);

}  // namespace u55c_framework
