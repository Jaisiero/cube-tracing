
#pragma once 
#include "defines.h"

#include <fstream>
#include <filesystem>

#include <gvox/gvox.h>

struct GvoxRayTracingModelData {
    uint32_t instance_count = 0;
    uint32_t primitive_count = 0;
    uint32_t material_count = 0;
    uint32_t light_count = 0;
};

struct GvoxRayTracingSerializeAdapterConfig {
    GvoxRayTracingModelData *model_data;

    const uint32_t max_instance_count;
    INSTANCE* const instances;

    const uint32_t max_primitive_count;
    PRIMITIVE* const primitives;
    AABB* const aabbs;

    const uint32_t max_material_count;
    MATERIAL* const materials;

    const uint32_t max_light_count;
    LIGHT* const lights;
};

struct MapLoader {
public:
    void create_gvox_context();
    auto load_gvox_data(std::filesystem::path gvox_model_path, GvoxRayTracingSerializeAdapterConfig gvox_adapter_config) -> GvoxRayTracingModelData;
    void destroy_gvox_context();
private:
    // Gvox context
    GvoxContext *gvox_ctx;
};