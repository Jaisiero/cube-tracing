
#pragma once 
#include "defines.h"

#include <fstream>
#include <filesystem>

#include <gvox/gvox.h>
#include <gvox/adapters/input/byte_buffer.h>
#include <gvox/adapters/output/byte_buffer.h>
#include <gvox/adapters/parse/voxlap.h>

struct MapLoader {
public:
    void create_gvox_context();
    auto load_gvox_data(std::filesystem::path gvox_model_path) -> GvoxModelData;
    void destroy_gvox_context();
private:
    // Gvox context
    GvoxContext *gvox_ctx;
};