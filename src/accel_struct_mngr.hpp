
#pragma once
#include "defines.h"
#include <queue>
#include <stack>
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
            UNDO_OP_CPU,
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
            uint32_t del_light_index;
            uint32_t remap_light_index;
            uint32_t remap_primitive_light_index;
        };

        struct BLAS_BUILD_FROM_CPU
        {
            uint32_t instance_count;
            uint32_t primitive_count;
        };

        struct UNDO_OP_CPU
        {
            TASK* undo_task;
        };

        TYPE type;
        union
        {
            BLAS_BUILD_FROM_CPU blas_build_from_cpu;
            BLAS_REBUILD_FROM_CPU blas_rebuild_from_cpu;
            BLAS_UPDATE blas_update;
            UNDO_OP_CPU undo_op_cpu;
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
    
    bool create(uint32_t max_instance_count, uint32_t max_primitive_count, uint32_t max_cube_light_count, uint32_t* cube_light_count);
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

    daxa::BufferId get_remapping_light_buffer() { 
        return remapping_light_buffer;
    }

    uint32_t get_host_instance_count() { 
        return temp_instance_count;
    }

    uint32_t get_host_primitive_count() { 
        return temp_primitive_count;
    }

    // TODO: Change this for AABB* device.get_host_address_as<AABB>(as_manager->get_aabb_host_buffer()).value();
    daxa::BufferId get_aabb_host_buffer() const { return aabb_host_buffer; }

    AABB* get_aabb_host_address() const { return device.get_host_address_as<AABB>(aabb_host_buffer).value(); }

    AABB* get_next_aabb_host_address() const { return get_aabb_host_address() + temp_primitive_count; }

    INSTANCE* get_instances() const { return instances.get(); }

    INSTANCE* get_next_instance_address() const { return instances.get() + temp_instance_count; }

    PRIMITIVE* get_primitives() const { return primitives.get(); }

    PRIMITIVE* get_next_primitive_address() const { return primitives.get() + temp_primitive_count; }

    daxa::BufferId get_cube_light_buffer() const { return cube_light_buffer; }

    LIGHT* get_cube_lights() const { return cube_lights; }

    daxa::BufferId get_brush_counter_buffer() const { return brush_counter_buffer; }

    daxa::BufferId get_brush_instance_bitmask_buffer() const { return brush_instance_bitmask_buffer; }

    daxa::BufferId get_brush_primitive_bitmask_buffer() const { return brush_primitive_bitmask_buffer; }



    bool task_queue_add(TASK task) {
        std::unique_lock lock(task_queue_mutex);
        task_queue.push(task);
        if(task.type == TASK::TYPE::BUILD_BLAS_FROM_CPU) {
            temp_instance_count++;
            temp_primitive_count+= task.blas_build_from_cpu.primitive_count;
        }
        return true;
    }

    bool update_scene(bool synchronize = false)
    {
        if (!initialized)
            return false;

        // TODO: this is not safe with the current implementation
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
                    // Switch to next index
                    current_index = (current_index + 1) % DOUBLE_BUFFERING;

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
                    // Switch to next index
                    current_index = (current_index + 1) % DOUBLE_BUFFERING;
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
    
    void check_voxel_modifications();

    void process_task_queue();
    void process_switching_task_queue();
    void process_settling_task_queue();

    std::mutex task_queue_mutex = {};
    std::condition_variable task_queue_cv = {};
    std::mutex synchronize_mutex = {};
    std::condition_variable synchronize_cv = {};
private:
    // Undo operations
    void process_undo_task_queue(uint32_t next_index, TASK& task);
    void process_undo_switching_task_queue(uint32_t next_index, TASK& task);
    void process_undo_settling_task_queue(uint32_t next_index, TASK& task);

    // Undo updating rebuilding BLAS
    bool restore_aabb_device_buffer(uint32_t buffer_index,
                                    uint32_t instance_index,
                                    uint32_t primitive_to_recover,
                                    uint32_t primitive_exchanged,
                                    uint32_t light_deleted,
                                    uint32_t light_exchanged);
    bool restore_remapping_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t instance_primitive_to_recover, uint32_t instance_primitive_exchanged);
    bool restore_cube_light_remapping_buffer(uint32_t buffer_index, uint32_t light_to_recover, uint32_t light_exchanged);


    // undo switching rebuilding BLAS
    bool restore_light_device_buffer(uint32_t buffer_index, 
        uint32_t light_to_recover_index, uint32_t light_exchanged_index, 
        uint32_t primivite_exchanged_index, uint32_t light_index_from_exchanged_primitive);


    // Checking modification operations
    void process_voxel_modifications();
    

    // Updating operations
    void copy_buffer(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, 
        size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size, bool synchronize = false);
    bool upload_all_instances(uint32_t buffer_index, bool synchronize = false);
    bool upload_primitive_device_buffer(uint32_t buffer_index, daxa_u32 primitive_count);
    bool copy_primitive_device_buffer(uint32_t buffer_index, uint32_t primitive_count);

    // Switching operations
    bool upload_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);
    bool copy_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count);

    // Settling operations
    bool delete_light_device_buffer(uint32_t buffer_index,
                                    uint32_t light_to_delete, uint32_t light_to_exchange,
                                    uint32_t primitive_deleted, uint32_t light_index_from_exchanged_primitive);
    bool update_light_remapping_buffer(uint32_t instance_index, uint32_t light_index, uint32_t light_to_exchange);
    bool clear_light_remapping_buffer(uint32_t instance_index, uint32_t light_index, uint32_t light_to_exchange);
    
    bool delete_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t primitive_index, 
        uint32_t primitive_to_exchange, uint32_t& light_to_delete, uint32_t& light_to_exchange, uint32_t& light_of_the_exchanged_primitive);
    bool update_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);

    bool copy_deleted_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t instance_delete_primitive);
    bool clear_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange);

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
    size_t max_cube_light_buffer_size = 0;
    size_t max_remapping_primitive_buffer_size = 0;
    size_t max_remapping_light_buffer_size = 0;

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
    uint32_t current_instance_count[DOUBLE_BUFFERING] = {0, 0};
    // We store the instance count not uploaded yet
    uint32_t temp_instance_count = 0;
    std::unique_ptr<INSTANCE[]> instances = {};
    
    daxa::BufferId aabb_buffer[DOUBLE_BUFFERING] = {};
    daxa::BufferId aabb_host_buffer = {};
    uint32_t current_aabb_host_idx = 0;

    uint32_t current_primitive_count[DOUBLE_BUFFERING] = {0, 0};
    // We store the primitive count not uploaded yet
    uint32_t temp_primitive_count = 0;
    uint32_t max_current_primitive_count = 0;
    std::unique_ptr<PRIMITIVE[]> primitives = {};

    daxa::BufferId primitive_buffer[DOUBLE_BUFFERING] = {};

    // Remapping buffer for primitives when rebuilding BLAS
    daxa::BufferId remapping_primitive_buffer = {};
    // Remapping buffer for lights when rebuilding BLAS
    daxa::BufferId remapping_light_buffer = {};

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
    std::stack<TASK> done_task_stack = {};

    // used for the worker thread
    std::queue<TASK> temporal_task_queue;
    // used for the switching task queue
    std::queue<TASK> switching_task_queue;


    size_t max_instance_bitmask_size = 0;
    size_t max_primitive_bitmask_size = 0;

    uint32_t *current_cube_light_count = nullptr;
    uint32_t temp_cube_light_count = 0;

    daxa::BufferId cube_light_buffer = {};
    LIGHT *cube_lights = nullptr;

    // Modification buffer
    daxa::BufferId brush_counter_buffer = {};
    daxa::BufferId brush_instance_bitmask_buffer = {};
    daxa::BufferId brush_primitive_bitmask_buffer = {};

    BRUSH_COUNTER* brush_counters = nullptr;
    
    uint32_t backup_primitive_count = 0;
    std::vector<PRIMITIVE> backup_primitives = {};
    std::vector<AABB> backup_aabbs = {};
    uint32_t backup_cube_light_count = 0;
    std::vector<LIGHT> backup_cube_lights = {};
    uint32_t backup_instance_count = 0;
    std::vector<INSTANCE> backup_instances = {};
};