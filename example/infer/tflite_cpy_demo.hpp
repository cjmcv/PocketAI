
#include <stdio.h>
#include "engine/infer/tools/tflite_cpy/tflite_cpy.hpp"

inline int TestTfliteCpy() {
    pai::infer::TfliteCpy tflite_cpy;
    std::string work_space = "/home/shared_dir/PocketAI/engine/infer/tools/tflite_cpy/";
    std::string model_path = "/home/shared_dir/PocketAI/example/infer/models/tf_micro_conv_test_model.int8.tflite";
    tflite_cpy.Init(work_space, model_path);

    int8_t *input_data;
    uint32_t input_size;
    tflite_cpy.GetInputPtr("serving_default_conv2d_input:0", (void **)&input_data, &input_size);

    for (uint32_t i=0; i<input_size/sizeof(uint8_t); i++)
        input_data[i] = i % 255;

    tflite_cpy.Infer();

    tflite_cpy.Print("StatefulPartitionedCall:0");

    return 0;
}