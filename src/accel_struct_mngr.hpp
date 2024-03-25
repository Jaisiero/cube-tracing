
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

    enum class AS_MANAGER_STATUS
    {
        IDLE = 0,
        UPDATING = 1,
        SWITCHING = 2,
        SWITCH = 3,
        SETTLING = 4,
        SETTLE = 5,
        BUILDING = 6,
    };
    struct TASK
    {
        enum class TYPE
        {
            BUILD_BLAS_FROM_CPU,
            REBUILD_BLAS_FROM_CPU,
            UPDATE_BLAS,
        };

        struct BLAS_UPDATE
        {
            uint32_t instance_index;
        };

        struct BLAS_REBUILD_FROM_CPU
        {
            uint32_t instance_index;
            uint32_t del_primitive_index;
            uint32_t remap_primitive_index;
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
            BLAS_REBUILD_FROM_CPU blas_rebuild_from_cpu;
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


    bool is_wake_up() const { return wake_up; }
    bool is_initialized() const { return initialized; }
    bool is_synchronizing() const { return synchronizing; }
    bool is_idle() { return (status == AS_MANAGER_STATUS::IDLE); }
    bool is_updating() { return (status == AS_MANAGER_STATUS::UPDATING); }
    bool is_switching() { return (status == AS_MANAGER_STATUS::SWITCHING); }
    bool is_settling() { return (status == AS_MANAGER_STATUS::SETTLING); }
    AS_MANAGER_STATUS get_status() { return status; }
    bool is_synchronizing() { return synchronizing; }
    void set_synchronizing(bool value) { synchronizing = value; }
    void set_wake_up(bool value) { wake_up = value; }


    daxa::TlasId get_current_tlas() { 
        return tlas[current_index]; 
    }

    daxa::TlasId get_previous_tlas() { 
        uint32_t prev_index = current_index - 1 % DOUBLE_BUFFERING;
        return is_switching() ? tlas[prev_index] : tlas[current_index];
    }

    daxa::BufferId get_current_instance_buffer() { 
        return instance_buffer[current_index]; 
    }

    daxa::BufferId get_previous_instance_buffer() { 
        uint32_t prev_index = current_index - 1 % DOUBLE_BUFFERING;
        return is_switching() ? instance_buffer[prev_index] : instance_buffer[current_index];
    }

    daxa::BufferId get_current_aabb_buffer() { 
        return aabb_buffer[current_index];
    }
    
    daxa::BufferId get_previous_aabb_buffer() { 
        // uint32_t prev_index = current_index - 1 % DOUBLE_BUFFERING;
        // return switching ? aabb_buffer[prev_index] : aabb_buffer[current_index];
        return aabb_buffer[current_index];
    }

    daxa::BufferId get_current_primitive_buffer() { 
        return primitive_buffer[current_index];
    }
    
    daxa::BufferId get_previous_primitive_buffer() { 
        // uint32_t prev_index = current_index - 1 % DOUBLE_BUFFERING;
        // return switching ? primitive_buffer[prev_index] : primitive_buffer[current_index];
        return primitive_buffer[current_index];
    }

    bool is_remapping_primitive_active() { 
        return is_switching();
    }

    daxa::BufferId get_remapping_primitive_buffer() { 
        return remapping_primitive_buffer;
    }

    // TODO: Change this for AABB* device.get_host_address_as<AABB>(as_manager->get_aabb_host_buffer()).value();
    daxa::BufferId get_aabb_host_buffer() const { return aabb_host_buffer; }

    INSTANCE* get_instances() const { return instances.get(); }

    PRIMITIVE* get_primitives() const { return primitives.get(); }

    daxa::BufferId get_brush_counter_buffer() const { return brush_counter_buffer; }

    daxa::BufferId get_brush_instance_bitmask_buffer() const { return brush_instance_bitmask_buffer; }

    daxa::BufferId get_brush_primitive_bitmask_buffer() const { return brush_primitive_bitmask_buffer; }



    bool task_queue_add(TASK task) {
        std::unique_lock lock(task_queue_mutex);
        task_queue.push(task);
        return true;
    }

    bool update_scene(bool synchronize = false)
    {
        if (!initialized)
            return false;

        switch (status)
        {
            case AS_MANAGER_STATUS::IDLE:
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
#if DEBUG == 1                    
                    std::cout << "Updating scene" << std::endl;
#endif // DEBUG                    

                    // set the updating flag to true
                    wake_up = true;
                    //
                    status = AS_MANAGER_STATUS::UPDATING;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }

                // if(synchronize) {
                    std::unique_lock lock(synchronize_mutex);
                    synchronizing = true;
                    synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
                // }
            }
            break;
            case AS_MANAGER_STATUS::SWITCHING:
            {
                
#if DEBUG == 1                    
                std::cout << "Switching scene" << std::endl;
#endif //DEBUG                

                {
                    // Get the mutex
                    std::unique_lock lock(task_queue_mutex);
                    // set the wake up flag to true
                    wake_up = true;
                    // status = AS_MANAGER_STATUS::SWITCH;
                    status = AS_MANAGER_STATUS::SWITCH;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }
                
                // Wait for the worker thread to finish
                {
                    std::unique_lock lock(synchronize_mutex);
                    synchronizing = true;
                    synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
                }
            } 
            break;
            case AS_MANAGER_STATUS::SETTLING: {
#if DEBUG == 1                    
                std::cout << "Settling scene" << std::endl;
#endif //DEBUG                
                {
                    // Get the mutex
                    std::unique_lock lock(task_queue_mutex);
                    // set the wake up flag to true
                    wake_up = true;
                    // status = AS_MANAGER_STATUS::SETTLE;
                    status = AS_MANAGER_STATUS::SETTLE;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }
                
                // if(synchronize){
                    std::unique_lock lock(synchronize_mutex);
                    synchronizing = true;
                    synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
                // }
            }
                break;
            default:
                break;
        }
            

        return true;
    }

    void process_task_queue();
    void process_switching_task_queue();
    void process_settling_task_queue();

    void check_voxel_modifications();

    std::mutex task_queue_mutex = {};
    std::condition_variable task_queue_cv = {};
    std::mutex synchronize_mutex = {};
    std::condition_variable synchronize_cv = {};
private:
    void process_voxel_modifications();
    
    void upload_primitives(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size);
    bool upload_primitive_device_buffer(uint32_t buffer_index, daxa_u32 primitive_count);
    bool copy_primitive_device_buffer(uint32_t buffer_index, uint32_t primitive_count);

    void upload_aabb_primitives(daxa::BufferId aabb_staging_buffer, daxa::BufferId aabb_buffer, size_t src_aabb_buffer_offset, size_t dst_aabb_buffer_offset, size_t aabb_copy_size, bool synchronize = true);
    bool upload_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);
    bool copy_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);

    
    bool delete_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);
    bool update_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);

    bool copy_deleted_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);
    bool restore_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);

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
    daxa::TlasId tlas[DOUBLE_BUFFERING] = {}, temp_tlas = {};
    std::vector<daxa::BlasId> proc_blas = {}, temp_proc_blas = {};
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
    std::atomic<AS_MANAGER_STATUS> status = AS_MANAGER_STATUS::IDLE;
    std::atomic<bool> wake_up = false;
    std::atomic<bool> synchronizing = false;

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

    // used for the switching task queue
    std::queue<TASK> switching_task_queue;


    size_t max_instance_bitmask_size = 0;
    size_t max_primitive_bitmask_size = 0;

    // Modification buffer
    daxa::BufferId brush_counter_buffer = {};
    daxa::BufferId brush_instance_bitmask_buffer = {};
    daxa::BufferId brush_primitive_bitmask_buffer = {};

    BRUSH_COUNTER* brush_counters = nullptr;
};