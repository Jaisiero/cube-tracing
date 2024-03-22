
#pragma once
#include "defines.h"

struct ACCEL_STRUCT_MNGR
{
public:
    ACCEL_STRUCT_MNGR(daxa::Device& device) : device(device) {
        if(device.is_valid()) {
            acceleration_structure_scratch_offset_alignment = device.properties().acceleration_structure_properties.value().min_acceleration_structure_scratch_offset_alignment;
        }
    }
    ~ACCEL_STRUCT_MNGR() {
        if(initialized) {
            destroy();
        }
    }
    
    bool create();
    bool destroy();

    daxa::TlasId get_tlas(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::TlasId();
        return tlas[frame_index]; 
    }

    daxa::BufferId get_instance_buffer(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::BufferId();
        return instance_buffer[frame_index]; 
    }
    
    bool add_instance_count(uint32_t frame_index, uint32_t count) {
        if(frame_index >= DOUBLE_BUFFERING) return false;
        if(current_instance_count[frame_index] + count > MAX_INSTANCES) return false;
        current_instance_count[frame_index] += count;
        return true;
    }

    bool build_new_blas(uint32_t frame_index, daxa::BufferId aabb_buffer[DOUBLE_BUFFERING],  INSTANCE instances[], bool synchronize);
    bool build_tlas(uint32_t frame_index, INSTANCE instances[], bool synchronize);

private:
    daxa::Device& device;

    // Acceleration structures
    daxa::TlasId tlas[DOUBLE_BUFFERING] = {};
    std::vector<daxa::BlasId> proc_blas = {};
    daxa::BufferId proc_blas_scratch_buffer = {};
    daxa_u64 proc_blas_scratch_buffer_size = MAX_INSTANCES * 1024ULL * 2ULL; // TODO: is this a good estimation?
    daxa_u64 proc_blas_scratch_buffer_offset = 0;
    uint32_t acceleration_structure_scratch_offset_alignment = 0;
    daxa::BufferId proc_blas_buffer = {};
    daxa_u64 proc_blas_buffer_size = MAX_INSTANCES * 1024ULL * 2ULL; // TODO: is this a good estimation?
    daxa_u64 proc_blas_buffer_offset = 0;
    const uint32_t ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT = 256;

    std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
    std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};
    
    daxa::BufferId instance_buffer[DOUBLE_BUFFERING] = {};
    size_t max_instance_buffer_size = sizeof(INSTANCE) * MAX_INSTANCES;
    
    uint32_t current_instance_count[DOUBLE_BUFFERING] = {};
    // std::unique_ptr<INSTANCE[]> instances = {};

    bool initialized = false;
};