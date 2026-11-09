#include "u55c_framework/csv_logger.hpp"
#include "u55c_framework/runner.hpp"
#include "u55c_framework/types.hpp"

#include <algorithm>
#include <exception>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct CliOptions {
  u55c_framework::BenchmarkConfig cfg;
  std::string csv_path;
};

void print_usage(const char* argv0) {
  std::cout
      << "Usage: " << argv0 << " [options]\n"
      << "\nOptions:\n"
      << "  --mode <dry-run|cpu-ref|hw> Run mode (default: dry-run)\n"
      << "  --xclbin <path>            xclbin path (required in hw mode)\n"
      << "  --kernel <name>            Kernel name (default: vector_add)\n"
      << "  --device <index>           Device index (default: 0)\n"
      << "  --elements <count>         Elements per iteration\n"
      << "  --iterations <count>       Iteration count\n"
      << "  --seed <value>             Seed for deterministic data pattern\n"
      << "  --input-f32-bin <path>     Optional float32 input payload file (MLP mode)\n"
      << "  --output-u32-bin <path>    Optional uint32 prediction dump file (MLP mode)\n"
      << "  --csv <path>               Append results to CSV\n"
      << "  --no-verify                Disable correctness checks\n"
      << "  -h, --help                 Show this help\n";
}

u55c_framework::RunMode parse_mode(const std::string& value) {
  if (value == "dry-run") {
    return u55c_framework::RunMode::DryRun;
  }
  if (value == "cpu-ref") {
    return u55c_framework::RunMode::CpuRef;
  }
  if (value == "hw") {
    return u55c_framework::RunMode::Hardware;
  }
  throw std::runtime_error("invalid mode: " + value);
}

std::size_t parse_size_t(const std::string& value, const std::string& arg_name) {
  try {
    return static_cast<std::size_t>(std::stoull(value));
  } catch (const std::exception&) {
    throw std::runtime_error("invalid numeric value for " + arg_name + ": " + value);
  }
}

std::uint32_t parse_u32(const std::string& value, const std::string& arg_name) {
  try {
    return static_cast<std::uint32_t>(std::stoul(value));
  } catch (const std::exception&) {
    throw std::runtime_error("invalid numeric value for " + arg_name + ": " + value);
  }
}

CliOptions parse_args(int argc, char** argv) {
  CliOptions opts;

  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];

    auto require_next = [&](const char* name) -> std::string {
      if (i + 1 >= argc) {
        throw std::runtime_error(std::string("missing value for ") + name);
      }
      ++i;
      return argv[i];
    };

    if (arg == "--mode") {
      opts.cfg.mode = parse_mode(require_next("--mode"));
    } else if (arg == "--xclbin") {
      opts.cfg.xclbin_path = require_next("--xclbin");
    } else if (arg == "--kernel") {
      opts.cfg.kernel_name = require_next("--kernel");
    } else if (arg == "--device") {
      opts.cfg.device_index = parse_u32(require_next("--device"), "--device");
    } else if (arg == "--elements") {
      opts.cfg.elements = parse_size_t(require_next("--elements"), "--elements");
    } else if (arg == "--iterations") {
      opts.cfg.iterations = parse_size_t(require_next("--iterations"), "--iterations");
    } else if (arg == "--seed") {
      opts.cfg.seed = parse_u32(require_next("--seed"), "--seed");
    } else if (arg == "--input-f32-bin") {
      opts.cfg.input_f32_bin = require_next("--input-f32-bin");
    } else if (arg == "--output-u32-bin") {
      opts.cfg.output_u32_bin = require_next("--output-u32-bin");
    } else if (arg == "--csv") {
      opts.csv_path = require_next("--csv");
    } else if (arg == "--no-verify") {
      opts.cfg.verify = false;
    } else if (arg == "--help" || arg == "-h") {
      print_usage(argv[0]);
      std::exit(0);
    } else {
      throw std::runtime_error("unknown argument: " + arg);
    }
  }

  if (opts.cfg.mode == u55c_framework::RunMode::Hardware && opts.cfg.xclbin_path.empty()) {
    throw std::runtime_error("--xclbin is required in hw mode");
  }

  return opts;
}

double average_ms(const std::vector<u55c_framework::BenchmarkRow>& rows,
                  double u55c_framework::BenchmarkRow::*field) {
  if (rows.empty()) {
    return 0.0;
  }
  const double total = std::accumulate(
      rows.begin(),
      rows.end(),
      0.0,
      [&](double acc, const u55c_framework::BenchmarkRow& row) { return acc + row.*field; });
  return total / static_cast<double>(rows.size());
}

}  // namespace

int main(int argc, char** argv) {
  try {
    const auto opts = parse_args(argc, argv);

    const auto rows = u55c_framework::run_benchmark(opts.cfg);
    if (!opts.csv_path.empty()) {
      u55c_framework::append_rows_csv(opts.csv_path, rows);
    }

    const bool all_verified = std::all_of(
        rows.begin(), rows.end(), [](const u55c_framework::BenchmarkRow& row) { return row.verify_ok; });

    const auto avg_h2d = average_ms(rows, &u55c_framework::BenchmarkRow::h2d_ms);
    const auto avg_kernel = average_ms(rows, &u55c_framework::BenchmarkRow::kernel_ms);
    const auto avg_d2h = average_ms(rows, &u55c_framework::BenchmarkRow::d2h_ms);
    const auto avg_total = average_ms(rows, &u55c_framework::BenchmarkRow::total_ms);
    const auto avg_tput = average_ms(rows, &u55c_framework::BenchmarkRow::throughput_gbps);

    std::cout << std::fixed << std::setprecision(3)
              << "mode=" << u55c_framework::run_mode_string(opts.cfg.mode)
              << " kernel=" << opts.cfg.kernel_name
              << " elements=" << opts.cfg.elements
              << " iterations=" << opts.cfg.iterations
              << " avg_h2d_ms=" << avg_h2d
              << " avg_kernel_ms=" << avg_kernel
              << " avg_d2h_ms=" << avg_d2h
              << " avg_total_ms=" << avg_total
              << " avg_throughput_gbps=" << avg_tput
              << " verify=" << (all_verified ? "PASS" : "FAIL")
              << '\n';

    return all_verified ? 0 : 2;
  } catch (const std::exception& ex) {
    std::cerr << "ERROR: " << ex.what() << '\n';
    print_usage(argv[0]);
    return 1;
  }
}
