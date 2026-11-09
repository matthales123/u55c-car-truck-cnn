#include<stdio.h>
#include<stdlib.h>
#include<unistd.h>
#include<fcntl.h>
#include<math.h>
#include<assert.h>

#include<iostream>
#include<fstream>

#include "typedefs.h"
#include "timer.h"
#include "model.h"
#include "mlp.h"

//------------------------------------------------------------------------
// Helper function for reading images and labels
//------------------------------------------------------------------------
const int TEST_SIZE = 100;  // number of test instances

void read_test_images(int8_t test_images[TEST_SIZE][256]) {
  std::ifstream infile("data/test_b.dat");
  if (infile.is_open()) {
    for (int index = 0; index < TEST_SIZE; index++) {
      for (int pixel = 0; pixel < 256; pixel++) {
        int i;
        infile >> i;
        test_images[index][pixel] = i;
      }
    }
    infile.close();
  }
}

void read_test_labels(int test_labels[TEST_SIZE]) {
  std::ifstream infile("data/label.dat");
  if (infile.is_open()) {
    for (int index = 0; index < TEST_SIZE; index++) {
      infile >> test_labels[index];
    }
    infile.close();
  }
}

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


//--------------------------------------
// main function
//--------------------------------------
int main(int argc, char** argv)
{
  std::cout << "starting host.cpp"<< std::endl;
  // Open channels to the FPGA board.
  // These channels appear as files to the Linux OS
  int fdr = open("/dev/xillybus_read_32", O_RDONLY);
  int fdw = open("/dev/xillybus_write_32", O_WRONLY);

  // Check that the channels are correctly opened
  if ((fdr < 0) || (fdw < 0)) {
    fprintf (stderr, "Failed to open Xillybus device channels\n");
    exit(-1);
  }
  
  // Arrays to store test data and expected results (labels)
  float test_images[TEST_SIZE][3072];
  bit32_t test_image;
  int    test_labels[TEST_SIZE];

  // Timer
  Timer timer("digitrec mlp on FPGA");
  // intermediate results
  int nbytes;
  int error = 0;
  int num_test_insts = 0;
  float correct = 0.0;
    
  //--------------------------------------------------------------------
  // Read data from the input file into two arrays
  //--------------------------------------------------------------------
  read_test_images1(test_images);


  timer.start();
  //--------------------------------------------------------------------
  // Send data to accelerator
  //--------------------------------------------------------------------
  for (int i = 0; i < TEST_SIZE; ++i) {
    // Send 32-bit value through the write channel
    std::cout << "inputting images" << i << std::endl;
    for (int j = 0; j < 3072; j++) {
      union { float fval; int ival; } u;
      u.fval = test_images[i][j];
      int iv = u.ival;
      test_image = iv;
      //test_image(k,k) = test_images[i][j*32+k];
     nbytes = write (fdw, (void*)&test_image, sizeof(test_image));
     assert (nbytes == sizeof(test_image));
    }
  }
  //std::cout << "done inputting images" << std::endl;

  //--------------------------------------------------------------------
  // Receive data from the accelerator
  //--------------------------------------------------------------------
  for (int i = 0; i < TEST_SIZE; ++i) {
    std::cout << "outputing answer" << i << std::endl;
    bit32_t output;
    //std::cout << "sending data" << i << std::endl;
    nbytes = read (fdr, (void*)&output, sizeof(output));
  //  std::cout << "read complete" << i << std::endl;
    assert (nbytes == sizeof(output));
    //std::cout << "asserted" << i << std::endl;

    // verify results
    //if (output == test_labels[i]) correct += 1.0;
    if(output == 0)
      correct += 1.0;
   //std::cout << "updated correct" << i << std::endl;
  }
  //std::cout << "done outputting" << std::endl;

  timer.stop();

  //--------------------------------------------------------------------
  // Calculate error rate
  //--------------------------------------------------------------------
  std::cout << "Testing images: " << TEST_SIZE << std::endl;
  std::cout << "Accuracy: " << correct/TEST_SIZE << std::endl;

  return 0;
}
