//=========================================================================
// mlp_test.cpp
//=========================================================================
// @brief: testbench for Binarized Neural Betwork(mlp) digit recongnition application

#include <iostream>
#include <fstream>
#include "mlp.h"
#include "timer.h"
#include <string>
#include <sstream>
#include "model.h"
#include <vector>
#include <string>

using namespace std;

// Number of test instances
 const int TEST_SIZE = 2000;
 const int TEST_SIZE_HALF = 1000;
//const int TEST_SIZE = 0;
//const int TEST_SIZE_HALF = 0;

//------------------------------------------------------------------------
// Helper function for reading images and labels
//------------------------------------------------------------------------

// void read_test_images(float test_images[100][3072])
// {
//   // std::ifstream infile("test_data2/test_data.dat");
//   // if (infile.is_open())
//   // {
//   //   for (int index = 0; index < 100; index++)
//   //   {
//   //     for (int pixel = 0; pixel < 3072; pixel++)
//   //     {
//   //       float i;
//   //       infile >> i;
//   //       test_images[index][pixel] = i;
//   //       if (index == 0)
//   //       {
//   //         cout << i << endl;
//   //       }
//   //     }
//   //   }
//   //   infile.close();
//   // }
//   string line, word;
//   string fname = "test_data2/test_data.dat";
//   fstream file(fname, ios::in);
//   if (file.is_open())
//   {
//     int i = 0;
//     while (getline(file, line))
//     {
//       stringstream str(line);
//       int j = 0;
//       // cout << endl;
//       while (getline(str, word, ','))
//       {
//         test_images[i][j] = stof(word);
//         // cout << word << ",";
//         j++;
//       }
//       // cout << "last j:" << j << endl;
//       // cout << endl;
//       i++;
//     }
//     // cout << "last i:" << i << endl;
//   }
//   else
//     cout << "Could not open the file\n";

//   // cout << "test_images[0][0]:" << endl;
//   // printf("%.6f \n", test_images[0][0]);
//   // cout << "test_images[99][3071]:" << endl;
//   // printf("%.6f \n", test_images[99][3071]);
//   // exit(0);
// }

void read_test_images1(float test_images[100][3072])
{
  char fname[25] = "test_data2/test_data.dat";
  FILE *file = fopen(fname, "r");
  if (!file)
  {
    printf("Could not open the file\n");
    exit(0);
  }

  char content[3072 * 30];
  int i = 0;
  while (fgets(content, 3072 * 30, file))
  {
    const char *v = strtok(content, ",");
    int j = 0;
    while (v)
    {
      // printf("%s ", v);
      test_images[i][j] = atof(v);
      j++;
      v = strtok(NULL, ",");
    }
    // printf("\n");
    i++;
  }
  fclose(file);

  // cout << "test_images[0][0]:" << endl;
  // printf("%.6f \n", test_images[0][0]);
  // cout << "test_images[99][3071]:" << endl;
  // printf("%.6f \n", test_images[99][3071]);
  // exit(0);
}


void read_any(float test_images[TEST_SIZE_HALF][3072], string item)
{
  for (int k = 0; k < TEST_SIZE_HALF; k++)
  {
    string e = "data/testing_data/normalized_";
    string f = "_32/";
    string b = ".jpg.dat";
    stringstream ss;
    ss << k;
    string str = ss.str();
    string file = string(e) + item + f + str + b;
    std::ifstream infile(file.c_str());
    if (infile.is_open())
    {
      for (int pixel = 0; pixel < 3072; pixel++)
      {
        float i;
        infile >> i;
        test_images[k][pixel] = i;
        if (pixel == 3071 && k == 1)
        {
          // std::cout << file <<" \n";
          // std::cout << pixel  << " " << test_images[k][pixel] <<" \n";
        }
      }
      infile.close();
    }
  }
}

void read_test_labels(int test_labels[TEST_SIZE])
{
  std::ifstream infile("data/label.dat");
  if (infile.is_open())
  {
    for (int index = 0; index < TEST_SIZE; index++)
    {
      infile >> test_labels[index];
    }
    infile.close();
  }
}

//------------------------------------------------------------------------
// Digitrec testbench
//------------------------------------------------------------------------

int main()
{
  // HLS streams for communicating with the cordic block
  hls::stream<bit32_t> digitrec_in;
  hls::stream<bit32_t> digitrec_out;

  float test_images[100][3072];
  read_test_images1(test_images);
  // float trucks[TEST_SIZE_HALF][3072];
  // float test_images[TEST_SIZE][3072];
  // int test_labels[TEST_SIZE];
  // for (int i = 0; i < TEST_SIZE; i++)
  // {
  //   if (i < TEST_SIZE_HALF)
  //   {
  //     test_labels[i] = 0;
  //   }
  //   else
  //   {
  //     test_labels[i] = 1;
  //   }
  // }

  // // read test images and labels
  // read_any(cars, "cars");
  // read_any(trucks, "trucks");
  // for (int j = 0; j < 3072; j++)
  // {
  //   for (int i = 0; i < TEST_SIZE; i++)
  //   {
  //     if (i < TEST_SIZE_HALF)
  //     {
  //       test_images[i][j] = cars[i][j];
  //     }
  //     else
  //     {
  //       test_images[i][j] = trucks[i - TEST_SIZE_HALF][j];
  //     }
  //   }
  // }
  // read_test_labels(test_labels);

  float test_image;
  float correct = 0.0;

  // Timer
  Timer timer("digirec mlp");
  timer.start();

  // pack images to 32-bit and transmit to dut function
  for (int test = 0; test < 100; test++)
  {
    std::cout << test << " \n";
    // for (int i = 0; i < I_WIDTH1 * I_WIDTH1 / BUS_WIDTH; i++) {
    // std::cout << "test number: " <<test <<" \n";
    for (int i = 0; i < 3072; i++)
    {
      // std::cout << "A" << "\n";

      // for (int j = 0; j < BUS_WIDTH; j++) {

      union { float fval; int ival; } u;
        u.fval = test_images[test][i];
        int iv = u.ival;
        test_image = iv;
        digitrec_in.write(test_image);
    }
    // perform prediction
    // std::cout << test<< "\n";
    dut(digitrec_in, digitrec_out);

    // check results
    if (digitrec_out.read() == 0)
      correct += 1.0;
  }

  // // if (TEST_SIZE == 0)
  // // {
  // //   for (int i = 0; i < 3072; i++)
  // //   {
  // //     test_image = first_img[i];
  // //     if (i < 100)
  // //     {
  // //       cout << test_image << ",";
  // //     }

  // //     digitrec_in.write(test_image);
  // //   }
  // //   cout << endl;
  // //   cout << "print from mlp_test" << endl;
  // //   dut(digitrec_in, digitrec_out);
  // // }
  // // if (digitrec_out.read() == 1)
  // //   correct += 1.0;
  // // std::cout << "Accuracy: " << correct << std::endl;

  timer.stop();

  // Calculate accuracy
  std::cout << "Accuracy: " << correct / 100 << std::endl;

  return 0;
}
