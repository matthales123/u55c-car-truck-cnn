//===========================================================================
// mlp_u55c_tb.cpp
//===========================================================================

#include "mlp.h"
#include "typedefs.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

extern "C" void mlp_u55c(const float *images, bit32_t *predictions, int num_images);

static constexpr int kImageElems = 3072;
static constexpr int kTestImages = 4;

static bool load_images_from_path(const std::string &path, std::vector<float> &images, int image_count)
{
  std::ifstream in(path);
  if (!in.is_open())
  {
    std::cerr << "INFO: could not open image file candidate: " << path << "\\n";
    return false;
  }

  std::string line;
  int row = 0;
  while (row < image_count && std::getline(in, line))
  {
    std::stringstream ss(line);
    std::string token;
    int col = 0;
    while (col < kImageElems && std::getline(ss, token, ','))
    {
      images[row * kImageElems + col] = std::strtof(token.c_str(), nullptr);
      ++col;
    }
    if (col != kImageElems)
    {
      std::cerr << "ERROR: malformed row " << row << ", expected " << kImageElems
                << " elements, got " << col << "\\n";
      return false;
    }
    ++row;
  }

  if (row != image_count)
  {
    std::cerr << "ERROR: expected " << image_count << " rows, got " << row << "\\n";
    return false;
  }

  return true;
}

static bool load_images(std::vector<float> &images, int image_count)
{
  const char *candidates[] = {
      "test_data2/test_data.dat",
      "../../test_data2/test_data.dat",
      "../../../test_data2/test_data.dat",
      "../../../../test_data2/test_data.dat"};

  for (const char *candidate : candidates)
  {
    if (load_images_from_path(candidate, images, image_count))
    {
      std::cerr << "INFO: loaded test images from " << candidate << "\\n";
      return true;
    }
  }

  std::cerr << "ERROR: no readable test_data2/test_data.dat path found\\n";
  return false;
}

int main()
{
  std::vector<float> images(kTestImages * kImageElems, 0.0f);
  if (!load_images(images, kTestImages))
  {
    return 1;
  }

  std::vector<bit32_t> hw_out(kTestImages);
  std::vector<bit32_t> sw_ref(kTestImages);

  for (int img = 0; img < kTestImages; ++img)
  {
    float input[MAX_FMAP] = {0};
    for (int i = 0; i < kImageElems; ++i)
    {
      input[i] = images[img * kImageElems + i];
    }
    sw_ref[img] = mlp_xcel(input);
  }

  mlp_u55c(images.data(), hw_out.data(), kTestImages);

  int mismatches = 0;
  for (int i = 0; i < kTestImages; ++i)
  {
    if (sw_ref[i] != hw_out[i])
    {
      ++mismatches;
      std::cerr << "Mismatch image " << i << ": ref=" << sw_ref[i]
                << " hw=" << hw_out[i] << "\\n";
    }
  }

  if (mismatches)
  {
    std::cerr << "FAIL: " << mismatches << " mismatches\\n";
    return 1;
  }

  std::cout << "PASS: mlp_u55c matches mlp_xcel for " << kTestImages << " images\\n";
  return 0;
}
