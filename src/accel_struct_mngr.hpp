
#pragma once
#include "defines.h"
#include "math.inl"

#include <queue>
#include <stack>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <thread>

#include <free_list.hpp>
#include <uuid.hpp>

CL_NAMESPACE_BEGIN

struct ACCEL_STRUCT_MNGR
{
public:

    constexpr static u32 PRIMITIVE_ALIGNMENT = 32;

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

    struct PrimitiveChangeInfo {
        std::shared_ptr<daxa::ComputePipeline> primitive_changes_compute_pipeline;
        daxa::BufferId status_buffer;
        daxa::BufferId world_buffer;
    };
    struct TASK
    {
        enum class TYPE
        {
            BUILD_BLAS_FROM_CPU,
            DELETE_PRIMITIVE_BLAS_FROM_CPU,
            DELETE_BLAS_FROM_CPU,
            UPDATE_BLAS_FROM_CPU,
            DELETE_PRIMITIVE_BLAS_FROM_GPU,
            UNDO_OP_CPU,
        };

        struct BLAS_UPDATE
        {
            u32 instance_index;
            daxa_f32mat4x4 transform;
            u32 primitive_count;
            u32 primitive_index_buf_offset;
            u32 aabb_buf_offset;
        };

        struct BLAS_PRIMITIVE_DELETE_FROM_CPU
        {
            u32 instance_index;
            u32 del_primitive_index;
            u32 remap_primitive_index;
            u32 del_light_index;
            u32 remap_light_index;
            u32 remap_primitive_light_index;
        };

        struct BLAS_DEL_PRIM_FROM_GPU
        {
            u32 instance_index;
            u32 del_prim_count;
        };

        struct BLAS_BUILD_FROM_CPU
        {
            u32 instance_count;
            u32 primitive_count;
            daxa_f32mat4x4 transform;
            u32* instance_indices;
        };

        struct BLAS_DELETE_FROM_CPU
        {
            u32 instance_index;
            u32 first_primitive_index;
            u32 deleted_primitive_count;
        };

        struct UNDO_OP_CPU
        {
            TASK* undo_task;
        };

        TYPE type;
        union
        {
            BLAS_BUILD_FROM_CPU blas_build_from_cpu;
            BLAS_PRIMITIVE_DELETE_FROM_CPU blas_delete_primitive_from_cpu;
            BLAS_DEL_PRIM_FROM_GPU blas_del_prim_gpu;
            BLAS_DELETE_FROM_CPU blas_delete_from_cpu;
            BLAS_UPDATE blas_update;
            UNDO_OP_CPU undo_op_cpu;
        };
    };

    struct WritePrimitiveChanges : PrimitiveChangesTaskHead::Task
    {
        AttachmentViews views = {};
        std::shared_ptr<daxa::ComputePipeline> pipeline = {};
        BufferId indirect_buffer = {};
        usize offset = 0;
        void callback(daxa::TaskInterface ti)
        {
            ti.recorder.set_pipeline(*pipeline);
            ti.recorder.push_constant_vptr({
                ti.attachment_shader_blob.data(), 
                ti.attachment_shader_blob.size()});
            ti.recorder.dispatch_indirect({.indirect_buffer = indirect_buffer, .offset = offset});
        }
    };
    

    auto record_primitive_changes_task_graph(
        std::shared_ptr<daxa::ComputePipeline> record_compute_pipeline,
        daxa::BufferId indirect_buffer,
        usize offset,
        daxa::BufferId status_buffer,
        daxa::BufferId world_buffer,
        daxa::BufferId test_brush_primitive_buffer) -> daxa::TaskGraph
    {
        using namespace PrimitiveChangesTaskHead;
        auto task_graph = daxa::TaskGraph({
            .device = device,
            .record_debug_information = true,
            .name = "task_graph",
        });

        auto task_status_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{status_buffer},
                .latest_access = daxa::AccessConsts::HOST_WRITE,
            },
            .name = "status_buffer", // This name MUST be identical to the name used in the shader.
        });

        auto task_world_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{world_buffer},
                .latest_access = daxa::AccessConsts::HOST_WRITE,
            },
            .name = "world_buffer", // This name MUST be identical to the name used in the shader.
        });

        auto task_test_brush_primitive_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{test_brush_primitive_buffer},
                .latest_access = daxa::AccessConsts::COMPUTE_SHADER_READ_WRITE,
            },
            .name = "test_brush_primitive_buffer", // This name MUST be identical to the name used in the shader.
        });

        task_graph.use_persistent_buffer(task_status_buffer);
        task_graph.use_persistent_buffer(task_world_buffer);
        task_graph.use_persistent_buffer(task_test_brush_primitive_buffer);

        task_graph.add_task(WritePrimitiveChanges{
            .views = std::array{
                daxa::attachment_view(AT.status_buffer, task_status_buffer),
                daxa::attachment_view(AT.world_buffer, task_world_buffer),
                daxa::attachment_view(AT.test_brush_primitive_buffer, task_test_brush_primitive_buffer),
            },
            .pipeline = record_compute_pipeline,
            .indirect_buffer = indirect_buffer,
            .offset = offset,
        });
        task_graph.submit({});
        task_graph.complete({});

        return task_graph;
    }

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
    
    bool create(u32 max_instance_count, u32 max_primitive_count, u32 max_cube_light_count, u32* cube_light_count, PrimitiveChangeInfo primitive_change_info);
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
        u32 prev_index = current_index - 1 % DOUBLE_BUFFERING;
        return is_switching() ? tlas[prev_index] : tlas[current_index];
    }

    daxa::BufferId get_current_instance_buffer() { 
        return instance_buffer[current_index]; 
    }

    daxa::BufferId get_previous_instance_buffer() { 
        u32 prev_index = current_index - 1 % DOUBLE_BUFFERING;
        return is_switching() ? instance_buffer[prev_index] : instance_buffer[current_index];
    }

    daxa::BufferId get_current_aabb_buffer() { 
        return aabb_buffer[current_index];
    }
    
    daxa::BufferId get_previous_aabb_buffer() { 
        // u32 prev_index = current_index - 1 % DOUBLE_BUFFERING;
        // return switching ? aabb_buffer[prev_index] : aabb_buffer[current_index];
        return aabb_buffer[current_index];
    }

    daxa::BufferId get_current_primitive_buffer() { 
        return primitive_buffer[current_index];
    }
    
    daxa::BufferId get_previous_primitive_buffer() { 
        // u32 prev_index = current_index - 1 % DOUBLE_BUFFERING;
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

    u32 get_host_instance_count() { 
        return temp_instance_count;
    }

    u32 get_host_primitive_count() { 
        return temp_primitive_count;
    }

    // TODO: Change this for AABB* device.get_host_address_as<AABB>(as_manager->get_aabb_host_buffer()).value();
    daxa::BufferId get_aabb_host_buffer() const { return aabb_host_buffer; }

    AABB* get_aabb_host_address() const { return device.get_host_address_as<AABB>(aabb_host_buffer).value(); }

    AABB* get_next_aabb_host_address() const { return get_aabb_host_address() + temp_primitive_count; }

    AABB* request_aabb_host_buffer_count(u32 count, u32& temp_primitive_offset) {
        // TODO: mutex
        temp_primitive_offset = temp_primitive_count;
        AABB* address = get_aabb_host_address();
        temp_primitive_count += count;
        return address;
    }
    
    daxa::BufferId get_primitive_index_host_buffer() const { return primitive_index_host_buffer; }

    u32* get_primitive_index_host_address() const { return device.get_host_address_as<u32>(primitive_index_host_buffer).value(); }

    u32* get_next_primitive_index_host_address() const { return get_primitive_index_host_address() + temp_primitive_index_count; }

    u32* request_primitive_index_host_buffer_count(u32 count, u32& temp_primitive_index_offset) { 
        // TODO: mutex
        temp_primitive_index_offset = temp_primitive_index_count; 
        u32* address = get_primitive_index_host_address();
        temp_primitive_index_count += count;
        return address;
    }

    INSTANCE* get_instances() const { return temp_instances.get(); }

    INSTANCE* get_next_instance_address() const { return temp_instances.get() + temp_instance_count; }

    PRIMITIVE* get_primitives() const { return primitives.get(); }

    PRIMITIVE* get_next_primitive_address() const { return primitives.get() + temp_primitive_count; }

    daxa::BufferId get_cube_light_buffer() const { return cube_light_buffer; }

    LIGHT* get_cube_lights() const { return cube_lights; }

    daxa::BufferId get_brush_counter_buffer() const { return brush_counter_buffer; }

    daxa::BufferId get_brush_instance_bitmask_buffer() const { return brush_instance_bitmask_buffer; }

    daxa::BufferId get_brush_primitive_bitmask_buffer() const { return brush_primitive_bitmask_buffer; }



    bool task_queue_add(TASK task) {
        std::unique_lock lock(task_queue_mutex);
        // Check if the task is valid before pushing it to the queue
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
                    // if(synchronize) {
                        synchronizing = true;
                    // }

                    // set the updating flag to true
                    wake_up = true;
                    //
                    status = AS_MANAGER_STATUS::UPDATING;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }

                {
                // if(synchronize) {
                    std::unique_lock lock(synchronize_mutex);
                    synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
                // }
                }
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
                    // set the synchronize flag to true
                    synchronizing = true;
                    // status = AS_MANAGER_STATUS::SWITCH;
                    status = AS_MANAGER_STATUS::SWITCH;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }
                
                // Wait for the worker thread to finish
                {
                    std::unique_lock lock(synchronize_mutex);
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
                    // set the synchronize flag to true
                    synchronizing = true;
                    // status = AS_MANAGER_STATUS::SETTLE;
                    status = AS_MANAGER_STATUS::SETTLE;
                    // wake up the worker thread
                    task_queue_cv.notify_one();
                }
                
                {
                // if(synchronize){
                    std::unique_lock lock(synchronize_mutex);
                    synchronize_cv.wait(lock, [&] { return !is_synchronizing(); });
                // }
                }
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
    void process_undo_task_queue(u32 next_index, TASK& task);
    void process_undo_switching_task_queue(u32 next_index, TASK& task);
    void process_undo_settling_task_queue(u32 next_index, TASK& task);

    // Undo deleting rebuilding BLAS
    bool restore_aabb_device_buffer(u32 buffer_index,
                                    u32 instance_index,
                                    u32 primitive_to_recover,
                                    u32 primitive_exchanged,
                                    u32 light_deleted,
                                    u32 light_exchanged);
    bool restore_remapping_buffer(u32 buffer_index, u32 instance_index, u32 instance_primitive_to_recover, u32 instance_primitive_exchanged);
    bool restore_cube_light_remapping_buffer(u32 buffer_index, u32 light_to_recover, u32 light_exchanged);

    void restore_bitmask_buffers(const daxa::BufferId &instance_bitmask_staging_buffer, const daxa::BufferId &primitive_bitmask_staging_buffer);


    // undo switching rebuilding BLAS
    bool restore_light_device_buffer(u32 buffer_index, 
        u32 light_to_recover_index, u32 light_exchanged_index, 
        u32 primivite_exchanged_index, u32 light_index_from_exchanged_primitive);


    // Checking modification operations
    void process_voxel_modifications();
    

    // Deleting operations
    void copy_buffer(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, 
        size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size, bool synchronize = false);
    bool upload_all_instances(u32 buffer_index, bool synchronize = false);
    bool upload_primitive_device_buffer(u32 buffer_index, u32 primitive_count, u32 host_buffer_offset_count, u32 buffer_offset_count);
    bool copy_primitive_device_buffer(u32 buffer_index, u32 primitive_count, u32 buffer_offset_count);
    bool update_remapping_buffer(u32 instance_index, u32 primitive_index, u32 primitive_to_exchange);
    
    bool update_instance_remapping_buffer(u32 first_primitive_index, u32 primitive_count, u32 value);

    // Updating operations
    bool update_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 primitive_count, u32 indices_buffer_offset, u32 aabb_buffer_offset);
    bool copy_updated_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 primitive_count, u32 indices_buffer_offset, u32 aabb_buffer_offset);

    // Switching operations
    bool upload_aabb_device_buffer(u32 buffer_index, u32 aabb_host_count, u32 host_buffer_offset_count, u32 buffer_offset_count);
    bool copy_aabb_device_buffer(u32 buffer_index, u32 aabb_host_count, u32 buffer_offset_count);
    bool copy_deleted_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 instance_delete_primitive);
    bool copy_instance_aabb_device_buffer(u32 buffer_index, u32 instance_index);

    // Settling operations
    bool delete_light_device_buffer(u32 buffer_index,
                                    u32 light_to_delete, u32 light_to_exchange,
                                    u32 primitive_deleted, u32 light_index_from_exchanged_primitive);
    bool update_light_remapping_buffer(u32 light_index, u32 light_to_exchange);
    bool clear_light_remapping_buffer(u32 instance_index, u32 light_index, u32 light_to_exchange);
    
    bool delete_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 primitive_index, 
        u32 primitive_to_exchange, u32& light_to_delete, u32& light_to_exchange, u32& light_of_the_exchanged_primitive);
    bool clear_remapping_buffer(u32 instance_index, u32 primitive_index, u32 primitive_to_exchange);
    bool clear_instance_remapping_buffer(u32 instance_index);

    bool build_blases(u32 buffer_index, std::vector<u32>& instance_list);
    bool rebuild_blases(u32 buffer_index, std::vector<u32>& instance_list);
    bool update_blases(u32 buffer_index, std::vector<u32>& instance_list);
    bool build_tlas(u32 buffer_index, bool synchronize);


    daxa::Device& device;

    size_t proc_blas_scratch_buffer_size = 0; 
    size_t proc_blas_buffer_size = 0;
    size_t max_instance_buffer_size = 0;
    size_t max_aabb_buffer_size = 0;
    size_t max_aabb_host_buffer_size = 0;
    size_t max_primitive_index_host_buffer_size = 0;
    size_t max_primitive_buffer_size = 0;
    size_t max_cube_light_buffer_size = 0;
    size_t max_remapping_primitive_buffer_size = 0;
    size_t max_remapping_light_buffer_size = 0;


    // Acceleration structures
    daxa::TlasId tlas[DOUBLE_BUFFERING] = {}, temp_tlas = {};
    std::vector<daxa::BlasId> proc_blas = {}, temp_proc_blas = {};
    daxa::BufferId proc_blas_scratch_buffer = {};
    u64 proc_blas_scratch_buffer_offset = 0;
    u32 acceleration_structure_scratch_offset_alignment = 0;
    daxa::BufferId proc_blas_buffer = {};
    std::unique_ptr<gpu_free_list<daxa::BlasId, gpu_allocator<daxa::BlasId>>> blas_free_list = nullptr;
    u64 proc_blas_buffer_offset = 0;
    static constexpr u64 ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT = 256;
    std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
    std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};
    
    // TODO: revisit every atomic variable
    daxa::BufferId instance_buffer[DOUBLE_BUFFERING] = {};
    u32 current_instance_count[DOUBLE_BUFFERING] = {0, 0};
    // TODO: find a better way to copy to the instance buffer
    u32 max_wide_instance_count[DOUBLE_BUFFERING] = {0, 0};
    daxa::BufferId host_instance_buffer = {};
    INSTANCE* instances = nullptr;
    std::unique_ptr<free_uuid_list<uuid32>> instance_free_list = nullptr;

    // We store the instance count not uploaded yet
    std::atomic<u32> temp_instance_count = 0;
    std::unique_ptr<INSTANCE[]> temp_instances = {};
    
    daxa::BufferId aabb_buffer[DOUBLE_BUFFERING] = {};
    daxa::BufferId aabb_host_buffer = {};
    u32 current_aabb_host_idx = 0;

    std::atomic<u32> temp_primitive_index_count = 0;
    daxa::BufferId primitive_index_host_buffer = {};
    u32 current_primitive_host_idx = 0;

    u32 current_primitive_count[DOUBLE_BUFFERING] = {0, 0};
    // We store the primitive count not uploaded yet
    u32 temp_primitive_count = 0;
    u32 max_current_primitive_count = 0;
    std::unique_ptr<PRIMITIVE[]> primitives = {};
    daxa::BufferId primitive_buffer[DOUBLE_BUFFERING] = {};

    std::unique_ptr<gpu_free_list<VoxelBuffer, gpu_allocator<VoxelBuffer>>> primitive_free_list = nullptr;

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
    u32 current_index = 0;
    u32 items_to_process = 0;
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

    u32 *current_cube_light_count = nullptr;
    u32 temp_cube_light_count = 0;

    daxa::BufferId cube_light_buffer = {};
    LIGHT *cube_lights = nullptr;

    // Modification buffer
    daxa::BufferId brush_counter_buffer = {};
    daxa::BufferId brush_instance_bitmask_buffer = {};
    daxa::BufferId brush_primitive_bitmask_buffer = {};
    daxa::BufferId brush_indirect_buffer = {};
    // TODO: TEST
    daxa::BufferId test_brush_primitive_buffer = {};

    BRUSH_COUNTER* brush_counters = nullptr;
    
    u32 backup_primitive_count = 0;
    std::vector<PRIMITIVE> backup_primitives = {};
    std::vector<AABB> backup_aabbs = {};
    u32 backup_cube_light_count = 0;
    std::vector<LIGHT> backup_cube_lights = {};
    u32 backup_instance_count = 0;
    std::vector<INSTANCE> backup_instances = {};

    daxa::TaskGraph brush_task_graph = {};
    PrimitiveChangeInfo change_info = {};
};

CL_NAMESPACE_END