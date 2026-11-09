#include "u55c_framework/runner.hpp"

#include "u55c_framework/buffer_manager.hpp"
#include "u55c_framework/profiler.hpp"

#include <algorithm>
#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

#if defined(U55C_ENABLE_CPU_REF)
#include "mlp.h"
#endif

#if defined(U55C_ENABLE_XRT)
#include <xrt/experimental/xrt_xclbin.h>
#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>
#endif

namespace u55c_framework {
namespace {

constexpr std::size_t kMlpImageElems = 3072;

std::string utc_now_iso8601() {
  const std::time_t now = std::time(nullptr);
  std::tm tm_utc{};
#if defined(_WIN32)
  gmtime_s(&tm_utc, &now);
#else
  gmtime_r(&now, &tm_utc);
#endif

  std::ostringstream oss;
  oss << std::put_time(&tm_utc, "%Y-%m-%dT%H:%M:%SZ");
  return oss.str();
}

double throughput_gbps(const std::size_t elements, const double total_ms) {
  if (total_ms <= 0.0) {
    return 0.0;
  }

  const double bytes_moved = static_cast<double>(elements) * sizeof(std::uint32_t) * 3.0;
  const double bits_moved = bytes_moved * 8.0;
  return bits_moved / (total_ms * 1.0e6);
}

double throughput_gbps_bytes(const std::size_t bytes_moved, const double total_ms) {
  if (total_ms <= 0.0) {
    return 0.0;
  }
  return (static_cast<double>(bytes_moved) * 8.0) / (total_ms * 1.0e6);
}

bool is_mlp_kernel(const std::string& kernel_name) {
  return kernel_name.find("mlp_u55c") != std::string::npos;
}

std::vector<float> read_f32_bin_exact(const std::string& path, const std::size_t count) {
  std::ifstream in(path, std::ios::binary | std::ios::ate);
  if (!in) {
    throw std::runtime_error("failed to open input file: " + path);
  }
  const auto size = static_cast<std::size_t>(in.tellg());
  const std::size_t expected = count * sizeof(float);
  if (size != expected) {
    std::ostringstream oss;
    oss << "input file size mismatch for " << path << " (got " << size
        << " bytes, expected " << expected << ")";
    throw std::runtime_error(oss.str());
  }

  std::vector<float> data(count);
  in.seekg(0, std::ios::beg);
  in.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(expected));
  if (!in) {
    throw std::runtime_error("failed to read input payload from: " + path);
  }
  return data;
}

void write_u32_bin(const std::string& path, const std::uint32_t* data, const std::size_t count) {
  if (path.empty()) {
    return;
  }
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    throw std::runtime_error("failed to open output file: " + path);
  }
  out.write(
      reinterpret_cast<const char*>(data),
      static_cast<std::streamsize>(count * sizeof(std::uint32_t)));
  if (!out) {
    throw std::runtime_error("failed to write output payload to: " + path);
  }
}

void fill_inputs(std::uint32_t* a,
                 std::uint32_t* b,
                 std::vector<std::uint32_t>& expected,
                 const std::size_t elements,
                 const std::uint32_t seed,
                 const std::size_t iteration) {
  std::mt19937 rng(seed + static_cast<std::uint32_t>(iteration));
  std::uniform_int_distribution<std::uint32_t> dist(0u, 0x00FFFFFFu);

  for (std::size_t i = 0; i < elements; ++i) {
    const auto va = dist(rng);
    const auto vb = dist(rng);
    a[i] = va;
    b[i] = vb;
    expected[i] = va + vb;
  }
}

bool verify_outputs(const std::vector<std::uint32_t>& expected,
                    const std::uint32_t* out,
                    const std::size_t elements) {
  for (std::size_t i = 0; i < elements; ++i) {
    if (out[i] != expected[i]) {
      return false;
    }
  }
  return true;
}

BenchmarkRow base_row(const BenchmarkConfig& cfg, const std::size_t iteration) {
  BenchmarkRow row;
  row.timestamp_utc = utc_now_iso8601();
  row.mode = run_mode_string(cfg.mode);
  row.kernel = cfg.kernel_name;
  row.device_index = cfg.device_index;
  row.elements = cfg.elements;
  row.iteration = iteration;
  row.verify_ok = false;
  return row;
}

std::vector<BenchmarkRow> run_dry_run(const BenchmarkConfig& cfg) {
  if (is_mlp_kernel(cfg.kernel_name)) {
    std::vector<BenchmarkRow> rows;
    rows.reserve(cfg.iterations);

    const std::size_t num_images = cfg.elements;
    const std::size_t input_elems = num_images * kMlpImageElems;
    const std::size_t in_bytes = input_elems * sizeof(float);
    const std::size_t out_bytes = num_images * sizeof(std::uint32_t);
    const std::size_t moved_bytes = in_bytes + out_bytes;

    std::vector<float> host_images(input_elems);
    std::vector<float> dev_images(input_elems);
    std::vector<std::uint32_t> dev_out(num_images);
    std::vector<std::uint32_t> host_out(num_images);
    std::vector<float> fixed_input;
    if (!cfg.input_f32_bin.empty()) {
      fixed_input = read_f32_bin_exact(cfg.input_f32_bin, input_elems);
    }

    for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
      auto row = base_row(cfg, iteration);
      if (!fixed_input.empty()) {
        std::copy(fixed_input.begin(), fixed_input.end(), host_images.begin());
      } else {
        std::mt19937 rng(cfg.seed + static_cast<std::uint32_t>(iteration));
        std::uniform_real_distribution<float> dist(0.0f, 1.0f);
        for (std::size_t i = 0; i < input_elems; ++i) {
          host_images[i] = dist(rng);
        }
      }

      const auto t_total_start = Clock::now();

      const auto t_h2d_start = Clock::now();
      std::copy(host_images.begin(), host_images.end(), dev_images.begin());
      const auto t_h2d_end = Clock::now();

      const auto t_kernel_start = Clock::now();
      for (std::size_t img = 0; img < num_images; ++img) {
        float score = 0.0f;
        const std::size_t base = img * kMlpImageElems;
        for (std::size_t j = 0; j < kMlpImageElems; ++j) {
          score += dev_images[base + j];
        }
        dev_out[img] = (score > (static_cast<float>(kMlpImageElems) * 0.5f)) ? 1u : 0u;
      }
      const auto t_kernel_end = Clock::now();

      const auto t_d2h_start = Clock::now();
      std::copy(dev_out.begin(), dev_out.end(), host_out.begin());
      const auto t_d2h_end = Clock::now();

      bool verify_ok = true;
      if (cfg.verify) {
        verify_ok = std::all_of(
            host_out.begin(), host_out.end(), [](const std::uint32_t v) { return v <= 1u; });
      }
      const auto t_total_end = Clock::now();

      row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
      row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
      row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
      row.total_ms = elapsed_ms(t_total_start, t_total_end);
      row.verify_ok = verify_ok;
      row.throughput_gbps = throughput_gbps_bytes(moved_bytes, row.total_ms);
      write_u32_bin(cfg.output_u32_bin, host_out.data(), num_images);
      rows.push_back(row);
    }

    return rows;
  }

  std::vector<BenchmarkRow> rows;
  rows.reserve(cfg.iterations);

  std::vector<std::uint32_t> host_a(cfg.elements);
  std::vector<std::uint32_t> host_b(cfg.elements);
  std::vector<std::uint32_t> expected(cfg.elements);
  std::vector<std::uint32_t> dev_a(cfg.elements);
  std::vector<std::uint32_t> dev_b(cfg.elements);
  std::vector<std::uint32_t> dev_out(cfg.elements);
  std::vector<std::uint32_t> host_out(cfg.elements);

  for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
    auto row = base_row(cfg, iteration);
    fill_inputs(host_a.data(), host_b.data(), expected, cfg.elements, cfg.seed, iteration);

    const auto t_total_start = Clock::now();

    const auto t_h2d_start = Clock::now();
    std::copy(host_a.begin(), host_a.end(), dev_a.begin());
    std::copy(host_b.begin(), host_b.end(), dev_b.begin());
    const auto t_h2d_end = Clock::now();

    const auto t_kernel_start = Clock::now();
    for (std::size_t i = 0; i < cfg.elements; ++i) {
      dev_out[i] = dev_a[i] + dev_b[i];
    }
    const auto t_kernel_end = Clock::now();

    const auto t_d2h_start = Clock::now();
    std::copy(dev_out.begin(), dev_out.end(), host_out.begin());
    const auto t_d2h_end = Clock::now();

    const bool verify_ok = !cfg.verify || verify_outputs(expected, host_out.data(), cfg.elements);
    const auto t_total_end = Clock::now();

    row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
    row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
    row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
    row.total_ms = elapsed_ms(t_total_start, t_total_end);
    row.verify_ok = verify_ok;
    row.throughput_gbps = throughput_gbps(cfg.elements, row.total_ms);
    rows.push_back(row);
  }

  return rows;
}

#if defined(U55C_ENABLE_CPU_REF)
std::vector<BenchmarkRow> run_cpu_ref(const BenchmarkConfig& cfg) {
  if (is_mlp_kernel(cfg.kernel_name)) {
    std::vector<BenchmarkRow> rows;
    rows.reserve(cfg.iterations);

    const std::size_t num_images = cfg.elements;
    const std::size_t input_elems = num_images * kMlpImageElems;
    const std::size_t in_bytes = input_elems * sizeof(float);
    const std::size_t out_bytes = num_images * sizeof(std::uint32_t);
    const std::size_t moved_bytes = in_bytes + out_bytes;

    std::vector<float> images(input_elems);
    std::vector<std::uint32_t> predictions(num_images);
    std::vector<float> fixed_input;
    if (!cfg.input_f32_bin.empty()) {
      fixed_input = read_f32_bin_exact(cfg.input_f32_bin, input_elems);
    }

    for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
      auto row = base_row(cfg, iteration);
      if (!fixed_input.empty()) {
        std::copy(fixed_input.begin(), fixed_input.end(), images.begin());
      } else {
        std::mt19937 rng(cfg.seed + static_cast<std::uint32_t>(iteration));
        std::uniform_real_distribution<float> dist(0.0f, 1.0f);
        for (std::size_t i = 0; i < input_elems; ++i) {
          images[i] = dist(rng);
        }
      }

      const auto t_total_start = Clock::now();
      const auto t_h2d_start = Clock::now();
      const auto t_h2d_end = Clock::now();

      const auto t_kernel_start = Clock::now();
      for (std::size_t img = 0; img < num_images; ++img) {
        const bit32_t pred = mlp_xcel(&images[img * kMlpImageElems]);
        predictions[img] = static_cast<std::uint32_t>(pred);
      }
      const auto t_kernel_end = Clock::now();

      const auto t_d2h_start = Clock::now();
      const auto t_d2h_end = Clock::now();

      bool verify_ok = true;
      if (cfg.verify) {
        verify_ok = std::all_of(
            predictions.begin(), predictions.end(), [](const std::uint32_t v) { return v <= 1u; });
      }
      const auto t_total_end = Clock::now();

      row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
      row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
      row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
      row.total_ms = elapsed_ms(t_total_start, t_total_end);
      row.verify_ok = verify_ok;
      row.throughput_gbps = throughput_gbps_bytes(moved_bytes, row.total_ms);
      write_u32_bin(cfg.output_u32_bin, predictions.data(), num_images);
      rows.push_back(row);
    }

    return rows;
  }

  // Vector-add reference for non-MLP kernels.
  return run_dry_run(cfg);
}
#endif

#if defined(U55C_ENABLE_XRT)
std::vector<BenchmarkRow> run_hardware(const BenchmarkConfig& cfg) {
  if (cfg.xclbin_path.empty()) {
    throw std::runtime_error("hardware mode requires --xclbin <path>");
  }

  if (cfg.elements > static_cast<std::size_t>(std::numeric_limits<std::uint32_t>::max())) {
    throw std::runtime_error("elements exceeds kernel arg width (uint32)");
  }

  xrt::device device(cfg.device_index);
  auto uuid = device.load_xclbin(cfg.xclbin_path);
  xrt::kernel kernel(device, uuid, cfg.kernel_name);

  if (is_mlp_kernel(cfg.kernel_name)) {
    std::vector<BenchmarkRow> rows;
    rows.reserve(cfg.iterations);

    const std::size_t num_images = cfg.elements;
    const std::size_t input_elems = num_images * kMlpImageElems;
    const std::size_t in_bytes = input_elems * sizeof(float);
    const std::size_t out_bytes = num_images * sizeof(std::uint32_t);
    const std::size_t moved_bytes = in_bytes + out_bytes;

    xrt::bo images_bo(device, in_bytes, kernel.group_id(0));
    xrt::bo predictions_bo(device, out_bytes, kernel.group_id(1));
    auto* images = images_bo.map<float*>();
    auto* predictions = predictions_bo.map<std::uint32_t*>();
    std::vector<float> fixed_input;
    if (!cfg.input_f32_bin.empty()) {
      fixed_input = read_f32_bin_exact(cfg.input_f32_bin, input_elems);
    }

    for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
      auto row = base_row(cfg, iteration);
      if (!fixed_input.empty()) {
        std::copy(fixed_input.begin(), fixed_input.end(), images);
      } else {
        std::mt19937 rng(cfg.seed + static_cast<std::uint32_t>(iteration));
        std::uniform_real_distribution<float> dist(0.0f, 1.0f);
        for (std::size_t i = 0; i < input_elems; ++i) {
          images[i] = dist(rng);
        }
      }

      const auto t_total_start = Clock::now();

      const auto t_h2d_start = Clock::now();
      images_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      const auto t_h2d_end = Clock::now();

      const auto t_kernel_start = Clock::now();
      auto run = kernel(images_bo, predictions_bo, static_cast<std::uint32_t>(num_images));
      run.wait();
      const auto t_kernel_end = Clock::now();

      const auto t_d2h_start = Clock::now();
      predictions_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
      const auto t_d2h_end = Clock::now();

      bool verify_ok = true;
      if (cfg.verify) {
        verify_ok = std::all_of(
            predictions, predictions + num_images, [](const std::uint32_t v) { return v <= 1u; });
      }
      const auto t_total_end = Clock::now();

      row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
      row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
      row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
      row.total_ms = elapsed_ms(t_total_start, t_total_end);
      row.verify_ok = verify_ok;
      row.throughput_gbps = throughput_gbps_bytes(moved_bytes, row.total_ms);
      write_u32_bin(cfg.output_u32_bin, predictions, num_images);
      rows.push_back(row);
    }

    return rows;
  }

  std::vector<BenchmarkRow> rows;
  rows.reserve(cfg.iterations);

  const std::size_t bytes = cfg.elements * sizeof(std::uint32_t);
  BufferManager buffers(device, kernel, bytes);
  std::vector<std::uint32_t> expected(cfg.elements);

  for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
    auto row = base_row(cfg, iteration);

    fill_inputs(buffers.input_a(), buffers.input_b(), expected, cfg.elements, cfg.seed, iteration);

    const auto t_total_start = Clock::now();

    const auto t_h2d_start = Clock::now();
    buffers.sync_inputs_to_device();
    const auto t_h2d_end = Clock::now();

    const auto t_kernel_start = Clock::now();
    auto run = kernel(
        buffers.input_a_bo(),
        buffers.input_b_bo(),
        buffers.output_bo(),
        static_cast<std::uint32_t>(cfg.elements));
    run.wait();
    const auto t_kernel_end = Clock::now();

    const auto t_d2h_start = Clock::now();
    buffers.sync_output_from_device();
    const auto t_d2h_end = Clock::now();

    const bool verify_ok = !cfg.verify || verify_outputs(expected, buffers.output(), cfg.elements);
    const auto t_total_end = Clock::now();

    row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
    row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
    row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
    row.total_ms = elapsed_ms(t_total_start, t_total_end);
    row.verify_ok = verify_ok;
    row.throughput_gbps = throughput_gbps(cfg.elements, row.total_ms);
    rows.push_back(row);
  }

  return rows;
}
#endif

}  // namespace

const char* run_mode_string(const RunMode mode) {
  switch (mode) {
    case RunMode::DryRun:
      return "dry-run";
    case RunMode::CpuRef:
      return "cpu-ref";
    case RunMode::Hardware:
      return "hw";
    default:
      return "unknown";
  }
}

std::vector<BenchmarkRow> run_benchmark(const BenchmarkConfig& cfg) {
  if (cfg.elements == 0) {
    throw std::runtime_error("elements must be > 0");
  }
  if (cfg.iterations == 0) {
    throw std::runtime_error("iterations must be > 0");
  }

  switch (cfg.mode) {
    case RunMode::DryRun:
      return run_dry_run(cfg);
    case RunMode::CpuRef:
#if defined(U55C_ENABLE_CPU_REF)
      return run_cpu_ref(cfg);
#else
      throw std::runtime_error(
          "cpu-ref mode requested, but this binary was built without CPU reference support");
#endif
    case RunMode::Hardware:
#if defined(U55C_ENABLE_XRT)
      return run_hardware(cfg);
#else
      throw std::runtime_error(
          "hardware mode requested, but this binary was built without XRT support");
#endif
    default:
      throw std::runtime_error("unsupported run mode");
  }
}

}  // namespace u55c_framework
