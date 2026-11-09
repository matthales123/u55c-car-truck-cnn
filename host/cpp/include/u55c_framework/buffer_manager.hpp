#pragma once

#include <cstddef>
#include <cstdint>

#if defined(U55C_ENABLE_XRT)
#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>
#endif

namespace u55c_framework {

#if defined(U55C_ENABLE_XRT)
class BufferManager {
 public:
  BufferManager(const xrt::device& device, const xrt::kernel& kernel, std::size_t bytes);

  std::uint32_t* input_a();
  std::uint32_t* input_b();
  std::uint32_t* output();

  void sync_inputs_to_device();
  void sync_output_from_device();

  xrt::bo& input_a_bo();
  xrt::bo& input_b_bo();
  xrt::bo& output_bo();

 private:
  xrt::bo input_a_bo_;
  xrt::bo input_b_bo_;
  xrt::bo output_bo_;
  std::uint32_t* input_a_ptr_ = nullptr;
  std::uint32_t* input_b_ptr_ = nullptr;
  std::uint32_t* output_ptr_ = nullptr;
};
#endif

}  // namespace u55c_framework
