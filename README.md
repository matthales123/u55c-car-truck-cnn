# U55C Car/Truck CNN Accelerator

U55C migration of the ECE5775 car/truck HLS project, with HLS kernel wrappers,
a pure-RTL pipeline prototype, tests and local web tooling. The build actively
uses `legacy_src/ece5775_final_proj/car_truck_accel/ecelinux`; those sources,
model weights and small test inputs are retained. Full datasets are downloaded
locally and are not part of this public repository.

## Build and run

```bash
./scripts/fetch_cifar10.sh
python3 scripts/prepare_car_truck_dataset.py --cifar-bin ./datasets/cifar10/cifar-10-batches-bin/test_batch.bin --out-data ./legacy_src/ece5775_final_proj/car_truck_accel/ecelinux/test_data2/test_data.dat --out-labels ./legacy_src/ece5775_final_proj/car_truck_accel/ecelinux/test_data2/test_labels.csv --samples 100
./scripts/check_setup.sh
./scripts/build_host.sh
make hls_xclbin
./scripts/run_webapp_car_truck.sh
```

For the standalone HLS test flow, run `./run_u55c_hls_2025.sh` from the
`ecelinux` directory above. The script stages HLS work into a path without spaces.
This migration includes experimental paths; no complete UVM/formal or new
hardware-validation claim is made by this source export.

Original course project: https://github.com/matthales123/ece5775-cnn-accelerator

## Requirements

For FPGA builds, install AMD Vitis/Vivado 2025.1, XRT, and the compatible
`xilinx_u55c_gen3x16_xdma_3_202210_1` platform. Source your installation's
`settings64.sh` and XRT setup script before building. Python 3, a C++ compiler,
CMake and Make are required for the host/tooling. Run commands from this repository.
Keep the checkout path free of spaces for Vitis HLS.

The source includes host programs, HDL/HLS, tests and local web tooling. Generated
builds, debugging sessions, reports and results are excluded from this public copy.
Web applications are local development interfaces with hardware controls; public
Internet demo access is a separate future deployment.
