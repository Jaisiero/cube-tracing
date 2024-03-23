
#pragma once
#include "defines.h"
#include <queue>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <thread>

struct ACCEL_STRUCT_MNGR
{
public:
    struct TASK
    {
        enum class TYPE
        {
            BUILD_BLAS_FROM_CPU,
            REBUILD_BLAS,
            UPDATE_BLAS,
        };

        struct BLAS_UPDATE
        {
            uint32_t instance_index;
        };

        struct BLAS_REBUILD
        {
            uint32_t instance_index;
            uint32_t del_primitive_index;
        };

        struct BLAS_BUILD_FROM_CPU
        {
            uint32_t instance_count;
            uint32_t primitive_count;
        };

        TYPE type;
        union
        {
            BLAS_BUILD_FROM_CPU blas_build_from_cpu;
            BLAS_REBUILD blas_rebuild;
            BLAS_UPDATE blas_update;
        };
    };

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


    bool is_updating() const { return updating; }
    bool is_switching() const { return switching; }
    bool is_initialized() const { return initialized; }
    bool is_synchronizing() const { return synchronizing; }
    void set_synchronizing(bool value) { synchronizing = value; }
    void set_updating(bool value) { updating = value; }


    daxa::TlasId get_current_tlas() const { 
        return tlas[current_index]; 
    }

    daxa::TlasId get_previous_tlas() const { 
        return switching ? tlas[current_index-1 % DOUBLE_BUFFERING] : tlas[current_index];
    }

    daxa::BufferId get_current_instance_buffer() const { 
        return instance_buffer[current_index]; 
    }

    daxa::BufferId get_previous_instance_buffer() const { 
        return switching ? instance_buffer[current_index - 1 % DOUBLE_BUFFERING] : instance_buffer[current_index];
    }

    daxa::BufferId get_current_aabb_buffer() const { 
        return aabb_buffer[current_index];
    }
    
    daxa::BufferId get_previous_aabb_buffer() const { 
        return switching ? aabb_buffer[current_index - 1 % DOUBLE_BUFFERING] : aabb_buffer[current_index];
    }

    daxa::BufferId get_current_primitive_buffer() const { 
        return primitive_buffer[current_index];
    }
    
    daxa::BufferId get_previous_primitive_buffer() const { 
        return switching ? primitive_buffer[current_index - 1 % DOUBLE_BUFFERING] : primitive_buffer[current_index];
    }

    daxa::BufferId get_remapping_primitive_buffer() const { 
        return remapping_primitive_buffer;
    }

    // TODO: Change this for AABB* device.get_host_address_as<AABB>(as_manager->get_aabb_host_buffer()).value();
    daxa::BufferId get_aabb_host_buffer() const { return aabb_host_buffer; }

    INSTANCE* get_instances() const { return instances.get(); }

    PRIMITIVE* get_primitives() const { return primitives.get(); }

    bool task_queue_add(TASK task) {
        // TODO: Get mutex here
        task_queue.push(task);
        return true;
    }

    // bool add_instance_count(uint32_t buffer_index, uint32_t count) {
    //     if(buffer_index >= DOUBLE_BUFFERING) return false;
    //     if(current_instance_count[buffer_index] + count > MAX_INSTANCES) return false;
    //     current_instance_count[buffer_index] += count;
    //     return true;
    // }

    bool update_scene(bool synchronize = false)
    {
        if (!initialized)
            return false;

        if (!updating && !switching)
        {
            {
                // Get the mutex
                std::unique_lock lock(task_queue_mutex);
                // set the updating flag to true then
                // the worker thread will process the task queue items so far
                // get the number of items to process so far
                items_to_process = task_queue.size();
                // if there are no items to process, return false
                if(items_to_process == 0) return false;
                // set notify flag to false if we are synchronizing
                if(synchronize) {
                    synchronizing = true;
                }
            
                std::cout << "Updating scene" << std::endl;

                // set the updating flag to true
                updating = true;
                // wake up the worker thread
                task_queue_cv.notify_one();
            }

            if(synchronize) {
                std::unique_lock lock(synchronize_mutex);
                synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
            }

            return true;
        }
        else if (switching)
        {
            std::cout << "Switching scene" << std::endl;

            {
                // Get the mutex
                std::unique_lock lock(task_queue_mutex);
                // set the updating flag to false if we are synchronizing
                if(synchronize) {
                    synchronizing = true;
                }
                // set the updating flag to true
                updating = true;
                // wake up the worker thread
                task_queue_cv.notify_one();
            }
            
            if(synchronize) {
                std::unique_lock lock(synchronize_mutex);
                synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
            }
            return true;
        }
            
        return false; // No action to perform
    }

    void process_task_queue();
    void process_switching_task_queue();

    std::mutex task_queue_mutex = {};
    std::condition_variable task_queue_cv = {};
    std::mutex synchronize_mutex = {};
    std::condition_variable synchronize_cv = {};
private:

    
    void upload_primitives(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size);
    bool upload_primitive_device_buffer(uint32_t buffer_index, daxa_u32 primitive_count);
    bool copy_primitive_device_buffer(uint32_t buffer_index, uint32_t primitive_count);

    void upload_aabb_primitives(daxa::BufferId aabb_staging_buffer, daxa::BufferId aabb_buffer, size_t src_aabb_buffer_offset, size_t dst_aabb_buffer_offset, size_t aabb_copy_size);
    bool upload_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);
    bool copy_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);

    bool build_blas(uint32_t buffer_index, uint32_t instance_count);
    bool rebuild_blas(uint32_t buffer_index, uint32_t instance_index);
    bool update_blas(uint32_t buffer_index, uint32_t instance_index);
    bool build_tlas(uint32_t buffer_index, bool synchronize);


    daxa::Device& device;

    size_t proc_blas_scratch_buffer_size = 0; 
    size_t proc_blas_buffer_size = 0;
    size_t max_instance_buffer_size = 0;
    size_t max_aabb_buffer_size = 0;
    size_t max_aabb_host_buffer_size = 0;
    size_t max_primitive_buffer_size = 0;
    size_t max_remapping_primitive_buffer_size = 0;

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
    // uint32_t current_aabb_host_count = 0;

    uint32_t current_primitive_count[DOUBLE_BUFFERING] = {};
    uint32_t max_current_primitive_count = 0;
    std::unique_ptr<PRIMITIVE[]> primitives = {};

    daxa::BufferId primitive_buffer[DOUBLE_BUFFERING] = {};

    // Remapping buffer for primitives when rebuilding BLAS
    daxa::BufferId remapping_primitive_buffer = {};

    // STATUS
    bool initialized = false;
    std::atomic<bool> switching = false;
    std::atomic<bool> updating = false;
    
    std::atomic<bool> synchronizing = true;

    std::jthread worker_thread;
    bool index_updated[DOUBLE_BUFFERING] = {true, true};
    uint32_t current_index = 0;
    uint32_t items_to_process = 0;
    std::queue<TASK> task_queue = {};

    // this queue is used to store the tasks that have been processed
    // TODO: undo tasks in the future?
    std::queue<TASK> done_task_queue = {};

    // used for the worker thread
    std::queue<TASK> temporal_task_queue;
};