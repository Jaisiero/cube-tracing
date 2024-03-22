
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
    
    bool create(uint32_t max_instance_count, uint32_t max_primitive_count);
    bool destroy();

    daxa::TlasId get_tlas(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::TlasId();
        return tlas[frame_index]; 
    }

    daxa::BufferId get_instance_buffer(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::BufferId();
        return instance_buffer[frame_index]; 
    }

    daxa::BufferId get_aabb_buffer(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::BufferId();
        return aabb_buffer[frame_index]; 
    }

    daxa::BufferId get_aabb_host_buffer() const { return aabb_host_buffer; }

    INSTANCE* get_instances() const { return instances.get(); }

    PRIMITIVE* get_primitives() const { return primitives.get(); }

    daxa::BufferId get_primitive_buffer(uint32_t frame_index) const { 
        if(frame_index >= DOUBLE_BUFFERING) return daxa::BufferId();
        return primitive_buffer[frame_index]; 
    }

    bool add_instance_count(uint32_t frame_index, uint32_t count) {
        if(frame_index >= DOUBLE_BUFFERING) return false;
        if(current_instance_count[frame_index] + count > MAX_INSTANCES) return false;
        current_instance_count[frame_index] += count;
        return true;
    }

    bool load_primitives(uint32_t frame_index, bool synchronize);
    void upload_aabb_primitives(daxa::BufferId aabb_staging_buffer, daxa::BufferId aabb_buffer, size_t aabb_buffer_offset, size_t aabb_copy_size);
    bool upload_aabb_device_buffer(uint32_t current_aabb_host_count);
    bool build_new_blas(uint32_t frame_index, bool synchronize);
    bool build_tlas(uint32_t frame_index, bool synchronize);

private:
    daxa::Device& device;

    size_t proc_blas_scratch_buffer_size = 0; // TODO: is this a good estimation?
    size_t proc_blas_buffer_size = 0; // TODO: is this a good estimation?
    size_t max_instance_buffer_size = 0;
    size_t max_aabb_buffer_size = 0;
    size_t max_aabb_host_buffer_size = 0;
    size_t max_primitive_buffer_size = 0;

    // Acceleration structures
    daxa::TlasId tlas[DOUBLE_BUFFERING] = {};
    std::vector<daxa::BlasId> proc_blas = {};
    daxa::BufferId proc_blas_scratch_buffer = {};
    uint64_t proc_blas_scratch_buffer_offset = 0;
    uint32_t acceleration_structure_scratch_offset_alignment = 0;
    daxa::BufferId proc_blas_buffer = {};
    uint64_t proc_blas_buffer_offset = 0;
    const uint32_t ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT = 256;

    std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
    std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};
    
    daxa::BufferId instance_buffer[DOUBLE_BUFFERING] = {};
    
    uint32_t current_instance_count[DOUBLE_BUFFERING] = {};
    std::unique_ptr<INSTANCE[]> instances = {};
    
    daxa::BufferId aabb_buffer[DOUBLE_BUFFERING] = {};
    daxa::BufferId aabb_host_buffer = {};
    uint32_t current_aabb_host_count = 0;

    uint32_t current_primitive_count[DOUBLE_BUFFERING] = {};
    uint32_t max_current_primitive_count = 0;
    std::unique_ptr<PRIMITIVE[]> primitives = {};

    daxa::BufferId primitive_buffer[DOUBLE_BUFFERING] = {};

    bool initialized = false;
};