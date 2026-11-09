#include "u55c_framework/buffer_manager.hpp"

namespace u55c_framework {

#if defined(U55C_ENABLE_XRT)
BufferManager::BufferManager(const xrt::device& device,
                             const xrt::kernel& kernel,
                             const std::size_t bytes)
    : input_a_bo_(device, bytes, kernel.group_id(0)),
      input_b_bo_(device, bytes, kernel.group_id(1)),
      output_bo_(device, bytes, kernel.group_id(2)),
      input_a_ptr_(input_a_bo_.map<std::uint32_t*>()),
      input_b_ptr_(input_b_bo_.map<std::uint32_t*>()),
      output_ptr_(output_bo_.map<std::uint32_t*>()) {}

std::uint32_t* BufferManager::input_a() {
  return input_a_ptr_;
}

std::uint32_t* BufferManager::input_b() {
  return input_b_ptr_;
}

std::uint32_t* BufferManager::output() {
  return output_ptr_;
}

void BufferManager::sync_inputs_to_device() {
  input_a_bo_.sync(XCL_BO_SYNC_BO_TO_DEVICE);
  input_b_bo_.sync(XCL_BO_SYNC_BO_TO_DEVICE);
}

void BufferManager::sync_output_from_device() {
  output_bo_.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
}

xrt::bo& BufferManager::input_a_bo() {
  return input_a_bo_;
}

xrt::bo& BufferManager::input_b_bo() {
  return input_b_bo_;
}

xrt::bo& BufferManager::output_bo() {
  return output_bo_;
}
#endif

}  // namespace u55c_framework
