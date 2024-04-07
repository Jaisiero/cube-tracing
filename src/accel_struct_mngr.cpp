#include "accel_struct_mngr.hpp"

#include <map>

using AS_MANAGER_STATUS = cubeland::ACCEL_STRUCT_MNGR::AS_MANAGER_STATUS;
using ACCEL_STRUCT_MNGR = cubeland::ACCEL_STRUCT_MNGR;

void worker_thread_fn(std::stop_token stoken, ACCEL_STRUCT_MNGR *as_manager)
{
    while (!stoken.stop_requested())
    {
#if TRACE == 1
        std::cout << "Worker thread is sleeping" << std::endl;
#endif // TRACE
       // Wait for task queue to wake up
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->task_queue_cv.wait(lock, [&]
                                           { return as_manager->is_wake_up() || stoken.stop_requested(); });
        }
#if TRACE == 1
        std::cout << "Worker thread woke up" << std::endl;
#endif // TRACE

        // Check if stop is requested
        if (stoken.stop_requested())
        {
            break;
        }

        // Process task queue
        switch (as_manager->get_status())
        {
        case AS_MANAGER_STATUS::IDLE:
#if DEBUG == 1
            std::cout << "Idle" << std::endl;
#endif // DEBUG
            break;
        case AS_MANAGER_STATUS::UPDATING:
#if DEBUG == 1
            std::cout << "Processing task queue" << std::endl;
#endif // DEBUG
            as_manager->process_task_queue();
            break;
        case AS_MANAGER_STATUS::SWITCH:
#if DEBUG == 1
            std::cout << "Processing switching task queue" << std::endl;
#endif // DEBUG
            as_manager->process_switching_task_queue();
            break;
        case AS_MANAGER_STATUS::SETTLE:
#if DEBUG == 1
            std::cout << "Processing settling task queue" << std::endl;
#endif // DEBUG
            as_manager->process_settling_task_queue();
            break;
        default:
#if WARN
            std::cerr << "Unknown status" << std::endl;
#endif // WARN
            break;
        }

        // set update done
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->set_wake_up(false);
        }

        // Notify that the task is done
        if (as_manager->is_synchronizing())
        {
            std::unique_lock lock(as_manager->synchronize_mutex);

            // Set synchronizing to false
            as_manager->set_synchronizing(false);

            as_manager->synchronize_cv.notify_one();
        }
    };
}

bool ACCEL_STRUCT_MNGR::create(u32 max_instance_count, u32 max_primitive_count, u32 max_cube_light_count, u32 *cube_light_count)
{
    if (device.is_valid() && !initialized)
    {
        proc_blas_scratch_buffer_size = max_instance_count * 1024ULL * 2ULL; // TODO: is this a good estimation?
        proc_blas_buffer_size = max_instance_count * 1024ULL * 2ULL;         // TODO: is this a good estimation?
        max_instance_buffer_size = sizeof(INSTANCE) * max_instance_count;
        max_aabb_buffer_size = sizeof(AABB) * max_primitive_count;
        max_aabb_host_buffer_size = sizeof(AABB) * max_primitive_count * 0.1;
        max_primitive_index_host_buffer_size = max_primitive_count * sizeof(u32) * 0.1;
        max_primitive_buffer_size = sizeof(PRIMITIVE) * max_primitive_count;
        max_cube_light_buffer_size = sizeof(LIGHT) * max_cube_light_count;
        max_remapping_primitive_buffer_size = sizeof(u32) * max_primitive_count;
        max_remapping_light_buffer_size = sizeof(u32) * max_cube_light_count;
        max_instance_bitmask_size = max_instance_count / sizeof(u32) + 1;
        max_primitive_bitmask_size = max_primitive_count / sizeof(u32) + 1;

        instances = std::make_unique<INSTANCE[]>(max_instance_count);
        primitives = std::make_unique<PRIMITIVE[]>(max_primitive_count);

        current_cube_light_count = cube_light_count;

        proc_blas_scratch_buffer = device.create_buffer({
            .size = proc_blas_scratch_buffer_size,
            .name = "proc blas build scratch buffer",
        });

        proc_blas_buffer = device.create_buffer({
            .size = proc_blas_buffer_size,
            .name = "proc blas buffer",
        });

        blas_free_list =
            std::make_unique<gpu_free_list<daxa::BlasId,
                                           gpu_allocator<daxa::BlasId>>>(device,
                                                                         proc_blas_buffer_size,
                                                                         proc_blas_buffer);

        // Clear previous procedural blas
        this->proc_blas.clear();

        instance_free_list = std::make_unique<free_uuid_list<uuid32>>(max_instance_count);

        for (u32 i = 0; i < DOUBLE_BUFFERING; i++)
        {
            tlas[i] = daxa::TlasId{};
            instance_buffer[i] = device.create_buffer({
                .size = max_instance_buffer_size,
                .name = ("instance_buffer_" + std::to_string(i)),
            });
        }

        primitive_free_list =
            std::make_unique<gpu_free_list<VoxelBuffer, gpu_allocator<VoxelBuffer>>>(device,
                                                                                           max_primitive_count,
                                                                                           primitive_buffer[0]);

        for (u32 i = 0; i < DOUBLE_BUFFERING; i++)
        {
            primitive_buffer[i] = device.create_buffer({
                .size = max_primitive_buffer_size,
                .name = ("primitive_buffer_" + std::to_string(i)),
            });
        }

        for (u32 i = 0; i < DOUBLE_BUFFERING; i++)
        {
            aabb_buffer[i] = device.create_buffer({
                .size = max_aabb_buffer_size,
                .name = ("aabb_buffer_" + std::to_string(i)),
            });
        }

        aabb_host_buffer = device.create_buffer({
            .size = max_aabb_host_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = "aabb host buffer",
        });

        primitive_index_host_buffer = device.create_buffer({
            .size = max_primitive_index_host_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = "primitive index host buffer",
        });

        remapping_primitive_buffer = device.create_buffer({
            .size = max_remapping_primitive_buffer_size,
            .name = "remapping primitive buffer",
        });

        cube_light_buffer = device.create_buffer(daxa::BufferInfo{
            .size = max_cube_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("cube_light_buffer"),
        });

        cube_lights = device.get_host_address_as<LIGHT>(cube_light_buffer).value();

        remapping_light_buffer = device.create_buffer({
            .size = max_remapping_light_buffer_size,
            .name = "remapping light buffer",
        });

        brush_counter_buffer = device.create_buffer({
            .size = sizeof(BRUSH_COUNTER),
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
            .name = "brush counter buffer",
        });

        brush_instance_bitmask_buffer = device.create_buffer({
            .size = max_instance_bitmask_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
            .name = "brush instance bitmask buffer",
        });

        brush_primitive_bitmask_buffer = device.create_buffer({
            .size = max_primitive_bitmask_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
            .name = "brush primitive bitmask buffer",
        });

        brush_counters = device.get_host_address_as<BRUSH_COUNTER>(brush_counter_buffer).value();

        initialized = true;

        worker_thread = std::jthread(worker_thread_fn, this);
    }

    return initialized;
}

bool ACCEL_STRUCT_MNGR::destroy()
{

    if (device.is_valid() && initialized)
    {
        for (auto _tlas : tlas)
            if (_tlas != daxa::TlasId{})
                device.destroy_tlas(_tlas);
        for (auto blas : proc_blas)
            if (blas != daxa::BlasId{})
                device.destroy_blas(blas);

        if (proc_blas_scratch_buffer != daxa::BufferId{})
            device.destroy_buffer(proc_blas_scratch_buffer);
        if (proc_blas_buffer != daxa::BufferId{})
            device.destroy_buffer(proc_blas_buffer);

        for (auto buffer : instance_buffer)
            if (buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);

        for (auto buffer : aabb_buffer)
            if (buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);

        if (aabb_host_buffer != daxa::BufferId{})
            device.destroy_buffer(aabb_host_buffer);

        if (primitive_index_host_buffer != daxa::BufferId{})
            device.destroy_buffer(primitive_index_host_buffer);

        for (auto buffer : primitive_buffer)
            if (buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);

        if (remapping_primitive_buffer != daxa::BufferId{})
            device.destroy_buffer(remapping_primitive_buffer);

        if (cube_light_buffer != daxa::BufferId{})
            device.destroy_buffer(cube_light_buffer);

        if (remapping_light_buffer != daxa::BufferId{})
            device.destroy_buffer(remapping_light_buffer);

        if (brush_counter_buffer != daxa::BufferId{})
            device.destroy_buffer(brush_counter_buffer);

        if (brush_instance_bitmask_buffer != daxa::BufferId{})
            device.destroy_buffer(brush_instance_bitmask_buffer);

        if (brush_primitive_bitmask_buffer != daxa::BufferId{})
            device.destroy_buffer(brush_primitive_bitmask_buffer);

        initialized = false;

        worker_thread.request_stop();

        {
            std::unique_lock lock(task_queue_mutex);
            task_queue_cv.notify_one();
        }

        worker_thread.join();
    }

    return !initialized;
}

void ACCEL_STRUCT_MNGR::copy_buffer(daxa::BufferId src_primitive_buffer,
                                    daxa::BufferId dst_primitive_buffer, size_t src_primitive_buffer_offset,
                                    size_t dst_primitive_buffer_offset, size_t primitive_copy_size, bool synchronize)
{

    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});

        recorder.copy_buffer_to_buffer({
            .src_buffer = src_primitive_buffer,
            .dst_buffer = dst_primitive_buffer,
            .src_offset = src_primitive_buffer_offset,
            .dst_offset = dst_primitive_buffer_offset,
            .size = primitive_copy_size,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});
    if (synchronize)
    {
        device.wait_idle();
    }
}

bool ACCEL_STRUCT_MNGR::upload_all_instances(u32 buffer_index, bool synchronize)
{

    // TODO: optimize by range copy?
    //  Copy instances to buffer
    u32 instance_buffer_size = static_cast<u32>(current_instance_count[buffer_index] * sizeof(INSTANCE));
    if (instance_buffer_size > max_instance_buffer_size)
    {
#if WARN
        std::cerr << "instance_buffer_size > max_instance_buffer_size" << std::endl;
#endif // WARN
        return false;
    }

    auto instance_staging_buffer = device.create_buffer({
        .size = instance_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("instance_staging_buffer"),
    });
    defer { device.destroy_buffer(instance_staging_buffer); };

    auto *instance_buffer_ptr = device.get_host_address_as<INSTANCE>(instance_staging_buffer).value();
    std::memcpy(instance_buffer_ptr,
                instances.get(),
                instance_buffer_size);

#if TRACE == 1
    std::cout << "  upload_all_instances: buffer_index: " << buffer_index << ", current_instance_count: " << current_instance_count[buffer_index] << std::endl;
    for (u32 i = 0; i < current_instance_count[buffer_index]; i++)
    {
        std::cout << "  instance[" << i << "] - first index: " << instance_buffer_ptr[i].first_primitive_index << ", primitive count: " << instance_buffer_ptr[i].primitive_count << std::endl;
    }
#endif // TRACE

    copy_buffer(instance_staging_buffer, instance_buffer[buffer_index], 0, 0, instance_buffer_size, synchronize);

    return true;
}

//////////////////////////////// UPDATING //////////////////////////////////////

bool ACCEL_STRUCT_MNGR::upload_primitive_device_buffer(u32 buffer_index, u32 primitive_count)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 previous_primitive_count = current_primitive_count[buffer_index];
    u32 primitive_count_offset = previous_primitive_count * sizeof(PRIMITIVE);
    u32 primitive_buffer_size = primitive_count * sizeof(PRIMITIVE);
    u32 current_primitive_count = previous_primitive_count + primitive_count;
    u32 current_primitive_count_offset = current_primitive_count * sizeof(PRIMITIVE);

    if (current_primitive_count_offset > max_primitive_buffer_size)
    {
#if WARN
        std::cerr << "primitive_buffer_size > max_primitive_buffer_size" << std::endl;
#endif // WARN
        // TODO: handle this case
        return false;
    }

    auto primitive_staging_buffer = device.create_buffer({
        .size = primitive_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("primitive_staging_buffer"),
    });
    defer { device.destroy_buffer(primitive_staging_buffer); };

    auto *primitive_buffer_ptr = device.get_host_address_as<PRIMITIVE>(primitive_staging_buffer).value();
    std::memcpy(primitive_buffer_ptr,
                primitives.get() + previous_primitive_count,
                primitive_buffer_size);

    copy_buffer(primitive_staging_buffer, primitive_buffer[buffer_index], 0, primitive_count_offset, primitive_buffer_size);

    return true;
}

bool ACCEL_STRUCT_MNGR::copy_primitive_device_buffer(u32 buffer_index, u32 primitive_count)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 previous_primitive_count = current_primitive_count[buffer_index];
    u32 primitive_count_offset = previous_primitive_count * sizeof(PRIMITIVE);
    u32 primitive_buffer_size = primitive_count * sizeof(PRIMITIVE);
    u32 current_primitive_count = previous_primitive_count + primitive_count;
    u32 current_primitive_count_offset = current_primitive_count * sizeof(PRIMITIVE);

    if (current_primitive_count_offset > max_primitive_buffer_size)
    {
#if WARN
        std::cerr << "primitive_buffer_size > max_primitive_buffer_size" << std::endl;
#endif // WARN
        return false;
    }

    u32 previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;
    copy_buffer(primitive_buffer[previous_buffer_index], primitive_buffer[buffer_index], primitive_count_offset, primitive_count_offset, primitive_buffer_size);

    return true;
}

bool ACCEL_STRUCT_MNGR::upload_aabb_device_buffer(u32 buffer_index, u32 aabb_host_count, size_t buffer_offset)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    if (aabb_host_count > 0)
    {
        size_t aabb_copy_size = aabb_host_count * sizeof(AABB);
        size_t aabb_buffer_offset = current_aabb_host_idx * sizeof(AABB);
        copy_buffer(aabb_host_buffer, aabb_buffer[buffer_index], aabb_buffer_offset, aabb_buffer_offset, aabb_copy_size, true);

        if (!upload_primitive_device_buffer(buffer_index, aabb_host_count))
        {
#if WARN
            std::cerr << "Failed to load primitives" << std::endl;
#endif // WARN
            return false;
        }
        current_aabb_host_idx += aabb_host_count;
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::update_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 primitive_count, u32 indices_buffer_offset, u32 aabb_buffer_offset)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // NOTE: We assume that the AABBs are already in the staging buffer from the aabb_buffer_offset
    // There's another staging buffer for the indices where the indices are stored for each AABB
    // The indices are the primitive indices that are associated with the AABBs
    // Copy all AABBs to the aabb buffer based on the primitive indices

    if(primitive_count > 0)
    {
        u32 first_primitive_index = instances[instance_index].first_primitive_index;

        // Get aabb staging buffer
        auto aabb_host_buffer = get_aabb_host_buffer();

        // Get the primitive indices host buffer pointer
        auto primitive_index_host_buffer_ptr = get_primitive_index_host_address() + indices_buffer_offset;
        
        // Iterate over the primitive indices and copy the AABBs to the aabb buffer
        for (u32 i = 0; i < primitive_count; i++)
        {
            // Get aabb index to change
            u32 primitive_index = primitive_index_host_buffer_ptr[i];

            if(primitive_index > instances[instance_index].primitive_count)
            {
#if WARN
                std::cerr << "primitive_index > instances[instance_index].primitive_count" << std::endl;
#endif // WARN
                continue;
            }

            // Get the host buffer AABB index
            u32 host_buffer_aabb_index = aabb_buffer_offset + i;
            // Get the primitive buffer offset
            u32 primitive_buffer_offset = first_primitive_index + primitive_index;

            // Copy AABB to the aabb buffer
            copy_buffer(aabb_host_buffer,
                        aabb_buffer[buffer_index],
                        host_buffer_aabb_index * sizeof(AABB),
                        primitive_buffer_offset * sizeof(AABB),
                        sizeof(AABB), i == primitive_count - 1);
        }


    }

    return true;
}



bool ACCEL_STRUCT_MNGR::copy_updated_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 primitive_count, u32 indices_buffer_offset, u32 aabb_buffer_offset)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // NOTE: We assume that the AABBs are already in the staging buffer from the aabb_buffer_offset
    // There's another staging buffer for the indices where the indices are stored for each AABB
    // The indices are the primitive indices that are associated with the AABBs
    // Copy all AABBs to the aabb buffer based on the primitive indices

    if(primitive_count > 0)
    {
        u32 first_primitive_index = instances[instance_index].first_primitive_index;

        // Get the primitive indices host buffer pointer
        auto primitive_index_host_buffer_ptr = get_primitive_index_host_address() + indices_buffer_offset;
        
        // Iterate over the primitive indices and copy the AABBs to the aabb buffer
        for (u32 i = 0; i < primitive_count; i++)
        {
            // Get aabb index to change
            u32 primitive_index = primitive_index_host_buffer_ptr[i];

            if(primitive_index > instances[instance_index].primitive_count)
            {
#if WARN
                std::cerr << "primitive_index > instances[instance_index].primitive_count" << std::endl;
#endif // WARN
                continue;
            }

            // Get the primitive buffer offset
            u32 primitive_buffer_offset = first_primitive_index + primitive_index;
            // Get the previous index
            u32 previous_index = (buffer_index - 1) % DOUBLE_BUFFERING;

            // Copy previous AABB buffer to the current buffer
            copy_buffer(aabb_buffer[previous_index],
                        aabb_buffer[buffer_index],
                        primitive_buffer_offset * sizeof(AABB),
                        primitive_buffer_offset * sizeof(AABB),
                        sizeof(AABB), i == primitive_count - 1);
        }
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::delete_aabb_device_buffer(u32 buffer_index,
                                                  u32 instance_index, u32 primitive_index,
                                                  u32 primitive_to_exchange,
                                                  u32 &light_to_delete, u32 &light_to_exchange,
                                                  u32 &light_of_the_exchanged_primitive)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    size_t multipurpose_staging_buffer_size = std::max(sizeof(AABB) + sizeof(PRIMITIVE), sizeof(u32)) * 2;

    auto multipurpose_staging_buffer = device.create_buffer({
        .size = multipurpose_staging_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("primitive_staging_buffer"),
    });
    defer { device.destroy_buffer(multipurpose_staging_buffer); };

    u32 first_primitive_index = instances[instance_index].first_primitive_index;
    // Copy primitive to delete
    u32 primitive_to_delete = first_primitive_index + primitive_index;
    // Copy last primitive
    u32 last_primitive_index = first_primitive_index + primitive_to_exchange;

    // Copy backup of primitive to delete
    copy_buffer(primitive_buffer[buffer_index], multipurpose_staging_buffer, primitive_to_delete * sizeof(PRIMITIVE), 0, sizeof(PRIMITIVE), true);
    // // Copy backup of primitive to exchange
    // copy_buffer(primitive_buffer[buffer_index], multipurpose_staging_buffer, last_primitive_index * sizeof(PRIMITIVE), sizeof(PRIMITIVE), sizeof(PRIMITIVE), true);

    auto *primitive_buffer_ptr = device.get_host_address_as<uint8_t>(multipurpose_staging_buffer).value();

    // Store primitive to delete
    primitives[primitive_to_delete] = *(reinterpret_cast<PRIMITIVE *>(primitive_buffer_ptr));
    // Copy primitive to exchange
    // PRIMITIVE primitive_to_exchange_gpu = *(reinterpret_cast<PRIMITIVE *>(primitive_buffer_ptr + sizeof(PRIMITIVE)));

    // Keep track of primitive light to delete
    if (primitives[primitive_to_delete].light_index != -1)
    {
        light_to_delete = primitives[primitive_to_delete].light_index;
        // Decrement temp light count
        light_to_exchange = --temp_cube_light_count;

        if (light_to_exchange == light_to_delete)
        {
            light_to_exchange = -1;
        }
    }

    // Backup of the deleted primitive and light
    {

        // Copy backup of AABB to delete
        copy_buffer(aabb_buffer[buffer_index], multipurpose_staging_buffer, primitive_to_delete * sizeof(AABB), 0, sizeof(AABB));
        // Copy backup of primitive to delete
        copy_buffer(primitive_buffer[buffer_index], multipurpose_staging_buffer, primitive_to_delete * sizeof(PRIMITIVE), sizeof(AABB), sizeof(PRIMITIVE), true);

        auto *primitive_buffer_ptr = device.get_host_address_as<uint8_t>(multipurpose_staging_buffer).value();

        // Store backup of AABB
        backup_aabbs.push_back(*(reinterpret_cast<AABB *>(primitive_buffer_ptr)));
        // Sotre backup of PRIMITIVE
        backup_primitives.push_back(*(reinterpret_cast<PRIMITIVE *>(primitive_buffer_ptr + sizeof(AABB))));

        // increase backup primitive counter
        ++backup_primitive_count;

        if (light_to_delete != -1)
        {
            // keep backup of light to delete
            backup_cube_lights.push_back(cube_lights[light_to_delete]);
            // increase backup light counter
            ++backup_cube_light_count;
        }
    }

    // Copying last primitive to deleted primitive
    if (primitive_to_exchange != primitive_index)
    {
        // Copy AABB
        copy_buffer(aabb_buffer[buffer_index], aabb_buffer[buffer_index], last_primitive_index * sizeof(AABB), primitive_to_delete * sizeof(AABB), sizeof(AABB), false);
        // Copy primitive
        copy_buffer(primitive_buffer[buffer_index], primitive_buffer[buffer_index], last_primitive_index * sizeof(PRIMITIVE), primitive_to_delete * sizeof(PRIMITIVE), sizeof(PRIMITIVE), true);
#if TRACE == 1
        std::cout << "  delete_aabb_device_buffer: primitive_to_exchange: " << primitive_to_exchange << ", primitive_index: " << primitive_index << std::endl;
#endif // TRACE
        if (light_to_exchange != -1)
        {
            u32 primitive_index_from_light_to_exchange =
                instances[cube_lights[light_to_exchange].instance_info.instance_id].first_primitive_index +
                cube_lights[light_to_exchange].instance_info.primitive_id;
            auto *multipurpose_staging_buffer_ptr =
                device.get_host_address_as<u32>(multipurpose_staging_buffer).value();
            std::memcpy(multipurpose_staging_buffer_ptr,
                        &light_to_delete,
                        sizeof(u32));
            copy_buffer(multipurpose_staging_buffer,
                        primitive_buffer[buffer_index], 0,
                        primitive_index_from_light_to_exchange * sizeof(PRIMITIVE) + sizeof(u32),
                        sizeof(u32));

            // Get light of the exchanged primitive
            copy_buffer(primitive_buffer[buffer_index],
                        multipurpose_staging_buffer,
                        last_primitive_index * sizeof(PRIMITIVE) + sizeof(u32),
                        0,
                        sizeof(u32), true);

            memcpy(&light_of_the_exchanged_primitive, multipurpose_staging_buffer_ptr, sizeof(u32));

#if TRACE == 1
            std::cout << "  delete_aabb_device_buffer primitive["
                      << primitive_index_from_light_to_exchange << "]: light_to_delete: "
                      << light_to_delete << ", light_to_exchange: " << light_to_exchange
                      << ", light_of_the_exchanged_primitive: " << light_of_the_exchanged_primitive << std::endl;
#endif // TRACE
        }
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::update_remapping_buffer(u32 instance_index, u32 primitive_index, u32 primitive_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 first_primitive_index = instances[instance_index].first_primitive_index;

    // Copy last primitive to deleted primitive
    u32 primitive_to_delete = first_primitive_index + primitive_index;

    size_t remapped_primitive_buffer_size = sizeof(u32) * 2;

    auto remapped_primitive_staging_buffer = device.create_buffer({
        .size = remapped_primitive_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("remapped_primitive_staging_buffer"),
    });
    defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

    u32 remapped_primitive_indexes[2] = {static_cast<u32>(-1), primitive_index};

    auto *remapped_primitive_buffer_ptr = device.get_host_address_as<u32>(remapped_primitive_staging_buffer).value();
    std::memcpy(remapped_primitive_buffer_ptr,
                remapped_primitive_indexes,
                remapped_primitive_buffer_size);

    copy_buffer(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, primitive_to_delete * sizeof(u32), sizeof(u32));
    if (primitive_to_exchange != primitive_index)
    {
        u32 last_primitive_index = first_primitive_index + primitive_to_exchange;
        copy_buffer(remapped_primitive_staging_buffer, remapping_primitive_buffer, sizeof(u32), last_primitive_index * sizeof(u32), sizeof(u32));
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::update_light_remapping_buffer(u32 light_to_delete, u32 light_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

#if TRACE == 1
    std::cout << "  *light_to_delete: " << light_to_delete << ", light_to_exchange: " << light_to_exchange << std::endl;
#endif // TRACE
    // Copy last primitive to deleted primitive

    if (light_to_delete != -1)
    {
        size_t remapped_light_buffer_size = sizeof(u32) * 2;

        auto remapped_light_staging_buffer = device.create_buffer({
            .size = remapped_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_light_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_light_staging_buffer); };

        u32 remapped_light_indexes[2] = {static_cast<u32>(-1), light_to_delete};

        auto *remapped_light_buffer_ptr = device.get_host_address_as<u32>(remapped_light_staging_buffer).value();
        std::memcpy(remapped_light_buffer_ptr,
                    remapped_light_indexes,
                    remapped_light_buffer_size);

        copy_buffer(remapped_light_staging_buffer, remapping_light_buffer, 0, light_to_delete * sizeof(u32), sizeof(u32));
        if (light_to_exchange != -1)
        {
            copy_buffer(remapped_light_staging_buffer, remapping_light_buffer, sizeof(u32), light_to_exchange * sizeof(u32), sizeof(u32));
        }
    }

    return true;
}

//////////////////////////////// UPDATING - UNDO  STARTS//////////////////////////////////////

void ACCEL_STRUCT_MNGR::process_undo_task_queue(u32 next_index, TASK &task)
{

    std::vector<u32> rebuild_blas_index_list = {};

    // Process task
    switch (task.type)
    {
    case TASK::TYPE::BUILD_BLAS_FROM_CPU:
    {
        // TODO: Destroy BLAS
    }
    break;
    case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
    {
        TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
#if TRACE == 1
        std::cout << "  *light_deleted: " << rebuild_task.del_light_index << ", light_exchanged: " << rebuild_task.remap_light_index << std::endl;
#endif // TRACE
       // restore primitive buffer
        restore_aabb_device_buffer(next_index, rebuild_task.instance_index,
                                   rebuild_task.del_primitive_index, rebuild_task.remap_primitive_index,
                                   rebuild_task.del_light_index, rebuild_task.remap_light_index);
        // Update remapping buffer
        restore_remapping_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index, rebuild_task.remap_primitive_index);
        // update light remapping buffer
        restore_cube_light_remapping_buffer(next_index, rebuild_task.del_light_index, rebuild_task.remap_light_index);
        // increment instance primitive count
        {
            instances[rebuild_task.instance_index].primitive_count++;
#if TRACE == 1
            std::cout << "  >Instance primitive count: " << instances[rebuild_task.instance_index].primitive_count << std::endl;
#endif // TRACE
        }
        // rebuild blas
        rebuild_blas_index_list.push_back(rebuild_task.instance_index);
    }
    break;
    case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
    {
        // TODO: Update BLAS
        TASK::BLAS_UPDATE update_task = task.blas_update;
        // update_blas(next_index, update_task.instance_index);
    }
    break;
    case TASK::TYPE::UNDO_OP_CPU:
    {
#if FATAL
        std::cerr << "      UNDO_OP_CPU impossible option for process_undo_task_queue" << std::endl;
#endif // FATAL
        std::abort();
    }
    break;
    default:
        break;
    }

    // Rebuild BLASes
    if (!rebuild_blas_index_list.empty())
        rebuild_blases(next_index, rebuild_blas_index_list);
}

bool ACCEL_STRUCT_MNGR::restore_aabb_device_buffer(u32 buffer_index, u32 instance_index,
                                                   u32 primitive_to_recover, u32 primitive_exchanged, u32 light_deleted, u32 light_exchanged)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // Copy last primitive to deleted primitive

    // Backup of the deleted primitive and light
    {
        size_t multipurpose_staging_buffer_size = sizeof(AABB) + sizeof(PRIMITIVE) + sizeof(u32);

        auto multipurpose_staging_buffer = device.create_buffer({
            .size = multipurpose_staging_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(multipurpose_staging_buffer); };

        --backup_primitive_count;

        u32 first_primitive_index = instances[instance_index].first_primitive_index;

        u32 exchanged_primitive_index = first_primitive_index + primitive_exchanged;
        u32 deleted_primitive_index = first_primitive_index + primitive_to_recover;

        auto *multipurpose_staging_buffer_ptr =
            device.get_host_address_as<uint8_t>(multipurpose_staging_buffer).value();

        if (primitive_exchanged != primitive_to_recover)
        {
            // Copy back of AABB exchanged to original place
            copy_buffer(aabb_buffer[buffer_index],
                        aabb_buffer[buffer_index], deleted_primitive_index * sizeof(AABB),
                        exchanged_primitive_index * sizeof(AABB), sizeof(AABB), false);
            // Copy back of primitive exchanged to original place
            copy_buffer(primitive_buffer[buffer_index],
                        primitive_buffer[buffer_index], deleted_primitive_index * sizeof(PRIMITIVE),
                        exchanged_primitive_index * sizeof(PRIMITIVE), sizeof(PRIMITIVE), true);

#if TRACE == 1
            std::cout << "  restore_aabb_device_buffer: primitive_exchanged: " << primitive_exchanged << ", primitive_to_recover: " << primitive_to_recover << std::endl;
#endif // TRACE

            if (light_exchanged != -1)
            {
                u32 primitive_index_from_light_exchanged =
                    instances[cube_lights[light_deleted].instance_info.instance_id].first_primitive_index +
                    cube_lights[light_deleted].instance_info.primitive_id;
                std::memcpy(multipurpose_staging_buffer_ptr + sizeof(AABB) + sizeof(PRIMITIVE),
                            &light_exchanged,
                            sizeof(u32));
                copy_buffer(multipurpose_staging_buffer,
                            primitive_buffer[buffer_index], sizeof(AABB) + sizeof(PRIMITIVE),
                            primitive_index_from_light_exchanged * sizeof(PRIMITIVE) + sizeof(u32),
                            sizeof(u32), true);
#if TRACE == 1
                std::cout << "  restore_aabb_device_buffer primitive["
                          << primitive_index_from_light_exchanged << "]: light_exchanged: "
                          << light_exchanged << ", light_deleted: " << light_deleted << std::endl;
#endif // TRACE
            }
        }

        memcpy(multipurpose_staging_buffer_ptr,
               &backup_aabbs[backup_primitive_count], sizeof(AABB));

        memcpy(multipurpose_staging_buffer_ptr + sizeof(AABB),
               &backup_primitives[backup_primitive_count], sizeof(PRIMITIVE));

        // Upload backup of AABB to deleted primitive place
        copy_buffer(multipurpose_staging_buffer, aabb_buffer[buffer_index], 0,
                    deleted_primitive_index * sizeof(AABB), sizeof(AABB));
        // Upload backup of AABB to deleted primitive place
        copy_buffer(multipurpose_staging_buffer, primitive_buffer[buffer_index],
                    sizeof(AABB), deleted_primitive_index * sizeof(PRIMITIVE), sizeof(PRIMITIVE), true);

        // Delete backup of AABB
        backup_aabbs.pop_back();
        // Delete backup of PRIMITIVE
        backup_primitives.pop_back();
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::restore_remapping_buffer(u32 buffer_index, u32 instance_index, u32 instance_primitive_to_recover, u32 instance_primitive_exchanged)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // Remapping exchanged primitive to the original primitive index
    if (instance_primitive_exchanged != instance_primitive_to_recover)
    {

        u32 first_primitive_index = instances[instance_index].first_primitive_index;

        // Actual primitive index in the buffer
        u32 primitive_to_recover = first_primitive_index + instance_primitive_to_recover;
        u32 primitive_exchanged = first_primitive_index + instance_primitive_exchanged;

        // Staging buffer
        auto remapped_primitive_staging_buffer = device.create_buffer({
            .size = sizeof(u32),
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

        auto *remapped_primitive_buffer_ptr = device.get_host_address_as<u32>(remapped_primitive_staging_buffer).value();
        std::memcpy(remapped_primitive_buffer_ptr,
                    &primitive_exchanged,
                    sizeof(u32));

        copy_buffer(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, primitive_to_recover * sizeof(u32), sizeof(u32));
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::restore_cube_light_remapping_buffer(u32 buffer_index, u32 light_to_recover, u32 light_exchanged)
{

    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // Copy deleted light to exchanged light & delete light from backup
    if (light_to_recover != -1)
    {

        size_t remapped_light_buffer_size = sizeof(u32);

        auto remapped_light_staging_buffer = device.create_buffer({
            .size = remapped_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_light_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_light_staging_buffer); };

        auto *remapped_light_buffer_ptr = device.get_host_address_as<u32>(remapped_light_staging_buffer).value();
        std::memcpy(remapped_light_buffer_ptr,
                    &light_exchanged,
                    sizeof(u32));

        // Copy exchanged light index to the recovered light index into device buffer
        copy_buffer(remapped_light_staging_buffer, remapping_light_buffer, 0, light_to_recover * sizeof(u32), sizeof(u32));
    }

    return true;
}

//////////////////////////////// UPDATING - UNDO  ENDS//////////////////////////////////////

//////////////////////////////// SWITCHING //////////////////////////////////////

bool ACCEL_STRUCT_MNGR::copy_aabb_device_buffer(u32 buffer_index, u32 aabb_host_count)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    if (aabb_host_count > 0)
    {
        size_t aabb_copy_size = aabb_host_count * sizeof(AABB);
        size_t aabb_buffer_offset = current_primitive_count[buffer_index] * sizeof(AABB);
        u32 previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;
        copy_buffer(aabb_buffer[previous_buffer_index], aabb_buffer[buffer_index], aabb_buffer_offset, aabb_buffer_offset, aabb_copy_size, true);

        if (!copy_primitive_device_buffer(buffer_index, aabb_host_count))
        {
#if WARN
            std::cerr << "Failed to load primitives" << std::endl;
#endif // WARN
            return false;
        }
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::copy_deleted_aabb_device_buffer(u32 buffer_index, u32 instance_index, u32 instance_primitive_to_copy)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 first_primitive_index = instances[instance_index].first_primitive_index;

    u32 instance_primitive_to_copy_index = first_primitive_index + instance_primitive_to_copy;

    u32 previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;

    // Copy AABB from previous buffer to current buffer
    copy_buffer(aabb_buffer[previous_buffer_index], aabb_buffer[buffer_index], instance_primitive_to_copy_index * sizeof(AABB), instance_primitive_to_copy_index * sizeof(AABB), sizeof(AABB));
    // Copy primitive from previous buffer to current buffer
    copy_buffer(primitive_buffer[previous_buffer_index], primitive_buffer[buffer_index], instance_primitive_to_copy_index * sizeof(PRIMITIVE), instance_primitive_to_copy_index * sizeof(PRIMITIVE), sizeof(PRIMITIVE), true);

    return true;
}

bool ACCEL_STRUCT_MNGR::delete_light_device_buffer(u32 buffer_index,
                                                   u32 light_to_delete, u32 light_to_exchange,
                                                   u32 primitive_deleted, u32 light_index_from_exchanged_primitive)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

#if TRACE == 1
    std::cout << " delete_light_device_buffer: light_to_delete: " << light_to_delete << ", light_to_exchange: " << light_to_exchange << std::endl;
#endif // TRACE

    if (light_to_exchange != -1)
    {
        // Copy light
        cube_lights[light_to_delete] = cube_lights[light_to_exchange];

        if (light_index_from_exchanged_primitive != -1)
        {
            // Copy light index from exchanged primitive
            cube_lights[light_index_from_exchanged_primitive].instance_info.primitive_id = primitive_deleted;

#if TRACE == 1
            std::cout << "  delete_light_device_buffer: cube_lights[" << light_index_from_exchanged_primitive << "].instance_info.primitive_id: "
                      << cube_lights[light_index_from_exchanged_primitive].instance_info.primitive_id << std::endl;
#endif // TRACE
        }

#if TRACE == 1
        std::cout << "  delete_light_device_buffer: cube_lights[" << light_to_delete << "].instance_info.primitive_id: "
                  << cube_lights[light_to_delete].instance_info.primitive_id << std::endl;
#endif // TRACE
    }

    return true;
}

//////////////////////////////// SWITCHING - UNDO  STARTS//////////////////////////////////////

void ACCEL_STRUCT_MNGR::process_undo_switching_task_queue(u32 next_index, TASK &task)
{

    switch (task.type)
    {
    case TASK::TYPE::BUILD_BLAS_FROM_CPU:
    {
        // TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
        // copy_aabb_device_buffer(next_index, build_task.primitive_count);
        // current_primitive_count[next_index] += build_task.primitive_count;
        // // NOTE: build_blas is already called for the previous index
        // current_instance_count[next_index] += build_task.instance_count;
    }
    break;
    case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
    {
        TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
        if (rebuild_task.del_primitive_index != rebuild_task.remap_primitive_index)
        {
            // copy deleted primtive from device buffer to double buffer
            copy_deleted_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index);
            // copy exchanged primitive from device buffer to double buffer
            copy_deleted_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.remap_primitive_index);
        }
        // delete light from buffer
        restore_light_device_buffer(next_index, rebuild_task.del_light_index,
                                    rebuild_task.remap_light_index,
                                    rebuild_task.remap_primitive_index, rebuild_task.remap_primitive_light_index);
    }
    break;
    case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
    {
        TASK::BLAS_UPDATE update_task = task.blas_update;
        // update_blas(next_index, update_task.instance_index);
    }
    break;
    case TASK::TYPE::UNDO_OP_CPU:
    {
#if FATAL
        std::cerr << "UNDO_OP_CPU impossible option for process_undo_switching_task_queue" << std::endl;
#endif // FATAL
        std::abort();
    }
    break;
    default:
    {
        break;
    }
    }
}

bool ACCEL_STRUCT_MNGR::restore_light_device_buffer(u32 buffer_index,
                                                    u32 light_to_recover_index, u32 light_exchanged_index,
                                                    u32 primivite_exchanged_index, u32 light_index_from_exchanged_primitive)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

#if TRACE == 1
    std::cout << "  restore_light_device_buffer: light_to_recover_index: " << light_to_recover_index << ", light_exchanged_index: " << light_exchanged_index << std::endl;
#endif // TRACE
    if (light_to_recover_index != -1)
    {

        if (light_exchanged_index != -1)
        {
            // Restore exchanged light to the original light index
            cube_lights[light_exchanged_index] = cube_lights[light_to_recover_index];
            // cube_lights[light_exchanged_index].instance_info.primitive_id = primivite_exchanged_index;

#if TRACE == 1
            std::cout << "  restore_light_device_buffer: cube_lights[" << light_exchanged_index << "].instance_info.primitive_id: "
                      << cube_lights[light_exchanged_index].instance_info.primitive_id << std::endl;
#endif // TRACE
        }

        if (light_index_from_exchanged_primitive != -1)
        {
            cube_lights[light_index_from_exchanged_primitive].instance_info.primitive_id = primivite_exchanged_index;
        }

        // Restore light to recover index
        // NOTE: Decrease backup light count
        cube_lights[light_to_recover_index] = backup_cube_lights.at(--backup_cube_light_count);

#if TRACE == 1
        std::cout << "  restore_light_device_buffer: cube_lights[" << light_to_recover_index << "].instance_info.primitive_id: "
                  << cube_lights[light_to_recover_index].instance_info.primitive_id << std::endl;
#endif // TRACE

        backup_cube_lights.pop_back();

        ++temp_cube_light_count;
    }

    return true;
}

//////////////////////////////// UPDATING - UNDO  ENDS//////////////////////////////////////

//////////////////////////////// SETTLING //////////////////////////////////////

bool ACCEL_STRUCT_MNGR::clear_remapping_buffer(u32 instance_index, u32 primitive_index, u32 primitive_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN  
        return false;
    }

    u32 first_primitive_index = instances[instance_index].first_primitive_index;

    // Copy last primitive to deleted primitive
    u32 primitive_to_delete = first_primitive_index + primitive_index;

    size_t remapped_primitive_buffer_size = sizeof(u32) * 2;

    auto remapped_primitive_staging_buffer = device.create_buffer({
        .size = remapped_primitive_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("remapped_primitive_staging_buffer"),
    });
    defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

    u32 remapped_primitive_indexes[2] = {0, 0};

    auto *remapped_primitive_buffer_ptr = device.get_host_address_as<u32>(remapped_primitive_staging_buffer).value();
    std::memcpy(remapped_primitive_buffer_ptr,
                remapped_primitive_indexes,
                remapped_primitive_buffer_size);

    copy_buffer(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, primitive_to_delete * sizeof(u32), sizeof(u32));
    if (primitive_to_exchange != primitive_index)
    {
        u32 last_primitive_index = first_primitive_index + primitive_to_exchange;
        copy_buffer(remapped_primitive_staging_buffer, remapping_primitive_buffer, sizeof(u32), last_primitive_index * sizeof(u32), sizeof(u32));
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::build_blases(u32 buffer_index, std::vector<u32>& instance_list)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 instance_count = instance_list.size();

    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(instance_count);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(instance_count);

    u32 current_instance_index = 0;

    // build procedural blas
    for (auto i : instance_list)
    {
#if TRACE == 1
        std::cout << "  build_blas: i: " << i << ", first primitive index: " << instances[i].first_primitive_index << ", primitive count: " << instances[i].primitive_count << std::endl;
#endif // TRACE

        aabb_geometries.at(current_instance_index).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[buffer_index]).value() + (instances[i].first_primitive_index * sizeof(AABB)), .stride = sizeof(AABB), .count = instances[i].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = static_cast<daxa::GeometryFlags>(0x1), // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

#if TRACE == 1
        std::cout << "      build_blas: aabb_geometries[" << current_instance_index << "].size(): " << aabb_geometries.at(current_instance_index).size() << std::endl;
        for (auto &aabb_geometry : aabb_geometries.at(current_instance_index))
        {
            std::cout << "      build_blas: aabb_geometry.data: " << aabb_geometry.data << ", aabb_geometry.stride: " << aabb_geometry.stride << ", aabb_geometry.count: " << aabb_geometry.count << std::endl;
        }
#endif // TRACE

        /// Create Procedural Blas:
        blas_build_infos.push_back(daxa::BlasBuildInfo{
            .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD | daxa::AccelerationStructureBuildFlagBits::ALLOW_UPDATE, // Is also default
            .dst_blas = {},                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .geometries = daxa::Span<const daxa::BlasAabbGeometryInfo>(aabb_geometries.at(current_instance_index).data(), aabb_geometries.at(current_instance_index).size()),
            .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
        });

        daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

        auto get_aligned = [&](u64 operand, u64 granularity) -> u64
        {
            return ((operand + (granularity - 1)) & ~(granularity - 1));
        };

        u32 scratch_alignment_size = get_aligned(proc_build_size_info.build_scratch_size, acceleration_structure_scratch_offset_alignment);

        if ((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size)
        {
            // TODO: Try to resize buffer
#if WARN
            std::cerr << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
#endif // WARN
            return false;
        }
        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        u32 build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        size_t offset = 0;
        auto blas = blas_free_list->allocate(build_aligment_size, offset);
        if(blas == daxa::BlasId{})
        {
#if FATAL
            std::cerr << " Could not allocate BLAS from free list" << std::endl;
#endif // FATAL
            // TODO: abort for now but try to resize buffer
            std::abort();
            // return false;
        }
#if TRACE
    std::cout << "  build_blases - allocated blas index: " << blas.index << ", version: " << blas.version << std::endl;
#endif

        proc_blas.push_back(blas);

        blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = proc_blas.at(i);

#if TRACE == 1
        std::cout << "      build_blas: blas_build_infos[" << blas_build_infos.size() - 1 
            << "].dst_blas: " << blas_build_infos.at(blas_build_infos.size() - 1).dst_blas.index 
            << ", proc_blas[" << i << "]: " << proc_blas.at(i).index << ", blas_build_infos[" 
            << blas_build_infos.size() - 1 << "].scratch_data: " 
            << blas_build_infos.at(blas_build_infos.size() - 1).scratch_data << std::endl;
#endif // TRACE

        ++current_instance_index;
    }

    proc_blas_scratch_buffer_offset = 0;

    // Check if all instances were processed
    if (current_instance_index != instance_count)
    {
#if WARN
        std::cerr << "current_instance_index != current_instance_count" << std::endl;
#endif // WARN
        return false;
    }

    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::HOST_WRITE,
            .dst_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_READ_WRITE,
        });

#if TRACE == 1
        std::cout << "      build_blas infos.size(): " << blas_build_infos.size() << std::endl;
        for (auto &blas_build_info : blas_build_infos)
        {
            std::cout << "      build_blas: blas_build_info.dst_blas: " << blas_build_info.dst_blas.index << ", blas_build_info.scratch_data: " << blas_build_info.scratch_data << std::endl;
        }
#endif // TRACE

        recorder.build_acceleration_structures({
            .blas_build_infos = blas_build_infos,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});

    return true;
}

bool ACCEL_STRUCT_MNGR::rebuild_blases(u32 buffer_index, std::vector<u32>& instance_list)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 instance_count = instance_list.size();

    // TODO: adapt this to rebuild many BLAS at once
    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(instance_count);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(instance_count);

    // if(proc_blas.at(instance_index) != daxa::BlasId{})
    //     device.destroy_blas(proc_blas.at(instance_index));

    for (auto instance_index : instance_list)
    {
        if (proc_blas.at(instance_index) != daxa::BlasId{})
            temp_proc_blas.push_back(proc_blas.at(instance_index));
    }

    u32 current_instance_index = 0;

    // build procedural blas
    for (auto instance_index : instance_list)
    {
#if TRACE == 1
        std::cout << "  build_blas: i: " << instance_index 
        << ", first primitive index: " << instances[instance_index].first_primitive_index 
        << ", primitive count: " << instances[instance_index].primitive_count << std::endl;
#endif // TRACE

        aabb_geometries.at(current_instance_index).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[buffer_index]).value() + (instances[instance_index].first_primitive_index * sizeof(AABB)), .stride = sizeof(AABB), .count = instances[instance_index].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = static_cast<daxa::GeometryFlags>(0x1), // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

        /// Create Procedural Blas:
        blas_build_infos.push_back(daxa::BlasBuildInfo{
            // TODO: allow update per instance
            .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD | daxa::AccelerationStructureBuildFlagBits::ALLOW_UPDATE, // Is also default
            .dst_blas = {},                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .geometries = daxa::Span<const daxa::BlasAabbGeometryInfo>(aabb_geometries.at(current_instance_index).data(), aabb_geometries.at(current_instance_index).size()),
            .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
        });

#if TRACE == 1
        std::cout << "      build_blas: aabb_geometries[" << current_instance_index << "].size(): " << aabb_geometries.at(current_instance_index).size() << std::endl;
        for (auto &aabb_geometry : aabb_geometries.at(current_instance_index))
        {
            std::cout << "      build_blas: aabb_geometry.data: " << aabb_geometry.data << ", aabb_geometry.stride: " << aabb_geometry.stride << ", aabb_geometry.count: " << aabb_geometry.count << std::endl;
        }
#endif // TRACE

        daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

        auto get_aligned = [&](u64 operand, u64 granularity) -> u64
        {
            return ((operand + (granularity - 1)) & ~(granularity - 1));
        };

        u32 scratch_alignment_size = get_aligned(proc_build_size_info.build_scratch_size, acceleration_structure_scratch_offset_alignment);

        if ((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size)
        {
            // TODO: Try to resize buffer
#if WARN
            std::cerr << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
#endif // WARN
            return false;
        }
        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        u32 build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        size_t offset = 0;
        auto blas = blas_free_list->allocate(build_aligment_size, offset);
        if(blas == daxa::BlasId{})
        {
#if FATAL
            std::cerr << " Could not allocate BLAS from free list" << std::endl;
#endif // FATAL
            // TODO: abort for now but try to resize buffer
            std::abort();
            // return false;
        }
#if TRACE
    std::cout << "  rebuild_blases - allocated blas index: " << blas.index << ", version: " << blas.version << std::endl;
#endif

        proc_blas.at(instance_index) = blas;

        // Here BLAS buffer is updated
        blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = proc_blas.at(instance_index);

#if TRACE == 1
        std::cout << "  build_blas: blas_build_infos[" << blas_build_infos.size() - 1 << "].dst_blas: " 
            << blas_build_infos.at(blas_build_infos.size() - 1).dst_blas.index << ", proc_blas[" << instance_index << "]: " 
                << proc_blas.at(instance_index).index << ", blas_build_infos[" << blas_build_infos.size() - 1 << "].scratch_data: " 
                << blas_build_infos.at(blas_build_infos.size() - 1).scratch_data << std::endl;

        auto aabb_geometries = daxa::get<daxa::Span<daxa::BlasAabbGeometryInfo const>>(blas_build_infos.at(blas_build_infos.size() - 1).geometries);

        for (u32 i = 0; i < aabb_geometries.size(); i++)
        {
            std::cout << "      build_blas: aabb_geometry.data: " << aabb_geometries[i].data << ", aabb_geometry.stride: " 
            << aabb_geometries[i].stride << ", aabb_geometry.count: " << aabb_geometries[i].count << std::endl;
        }
#endif // TRACE

        ++current_instance_index;
    }

    proc_blas_scratch_buffer_offset = 0;

    // Check if all instances were processed
    if (current_instance_index != instance_count)
    {
#if WARN
        std::cerr << "current_instance_index != current_instance_count" << std::endl;
#endif // WARN
        return false;
    }

    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::HOST_WRITE,
            .dst_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_READ_WRITE,
        });
        recorder.build_acceleration_structures({
            .blas_build_infos = blas_build_infos,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});

    return true;
}

bool ACCEL_STRUCT_MNGR::update_blases(u32 buffer_index, std::vector<u32>& instance_list)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    u32 instance_count = instance_list.size();

    // TODO: adapt this to rebuild many BLAS at once
    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(instance_count);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(instance_count);

    // if(proc_blas.at(instance_index) != daxa::BlasId{})
    //     device.destroy_blas(proc_blas.at(instance_index));

    std::map<u32, daxa::BlasId> blas_to_update;

    for (auto instance_index : instance_list)
    {
        if (proc_blas.at(instance_index) != daxa::BlasId{}) {
            blas_to_update[instance_index] = proc_blas.at(instance_index);
        }
    }

    u32 current_instance_index = 0;

    // build procedural blas
    for (auto instance_index : instance_list)
    {
#if TRACE == 1
        std::cout << "  build_blas: i: " << instance_index << ", first primitive index: " << instances[instance_index].first_primitive_index << ", primitive count: " << instances[instance_index].primitive_count << std::endl;
#endif // TRACE

        aabb_geometries.at(current_instance_index).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[buffer_index]).value() + (instances[instance_index].first_primitive_index * sizeof(AABB)), .stride = sizeof(AABB), .count = instances[instance_index].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = static_cast<daxa::GeometryFlags>(0x1), // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

        /// Create Procedural Blas:
        blas_build_infos.push_back(daxa::BlasBuildInfo{
            .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD | daxa::AccelerationStructureBuildFlagBits::ALLOW_UPDATE, // Is also default
            .update = true,
            .src_blas = blas_to_update[instance_index],                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .dst_blas = {},                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .geometries = daxa::Span<const daxa::BlasAabbGeometryInfo>(aabb_geometries.at(current_instance_index).data(), aabb_geometries.at(current_instance_index).size()),
            .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
        });

#if TRACE == 1
        std::cout << "      build_blas: aabb_geometries[" << current_instance_index << "].size(): " << aabb_geometries.at(current_instance_index).size() << std::endl;
        for (auto &aabb_geometry : aabb_geometries.at(current_instance_index))
        {
            std::cout << "      build_blas: aabb_geometry.data: " << aabb_geometry.data << ", aabb_geometry.stride: " << aabb_geometry.stride << ", aabb_geometry.count: " << aabb_geometry.count << std::endl;
        }
#endif // TRACE

        daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

        auto get_aligned = [&](u64 operand, u64 granularity) -> u64
        {
            return ((operand + (granularity - 1)) & ~(granularity - 1));
        };

        u32 scratch_alignment_size = get_aligned(proc_build_size_info.update_scratch_size, acceleration_structure_scratch_offset_alignment);

        if(scratch_alignment_size == 0)
        {
            blas_build_infos.pop_back();
#if WARN
            std::cerr << "  build_blas: update not allowed for instance_index: " << instance_index << std::endl;
#endif // WARN
            return false;
        }

        if ((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size)
        {
            // TODO: Try to resize buffer
#if WARN
            std::cerr << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
#endif // WARN
            return false;
        }
        
        if (proc_blas.at(instance_index) != daxa::BlasId{}) {
            temp_proc_blas.push_back(proc_blas.at(instance_index));
        }

        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        u32 build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        size_t offset = 0;
        auto blas = blas_free_list->allocate(build_aligment_size, offset);
        if(blas == daxa::BlasId{})
        {
#if FATAL
           std::cerr << " Could not allocate BLAS from free list" << std::endl;
#endif // FATAL
            // TODO: abort for now but try to resize buffer
            std::abort();
            // return false;
        }
#if TRACE
    std::cout << "  update_blases - allocated blas index: " << blas.index << ", version: " << blas.version << std::endl;
#endif
        
        proc_blas.at(instance_index) = blas;

        // Here BLAS buffer is updated
        blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = proc_blas.at(instance_index);

        // blas_build_infos.at(blas_build_infos.size() - 1).src_blas = blas_to_update[instance_index];

        // blas_build_infos.at(blas_build_infos.size() - 1).update = true;

#if TRACE == 1
        std::cout << "  build_blas: blas_build_infos[" << blas_build_infos.size() - 1 << "].dst_blas: " 
            << blas_build_infos.at(blas_build_infos.size() - 1).dst_blas.index << ", proc_blas[" << instance_index 
            << "]: " << proc_blas.at(instance_index).index << ", blas_build_infos[" << blas_build_infos.size() - 1 
            << "].scratch_data: " << blas_build_infos.at(blas_build_infos.size() - 1).scratch_data << std::endl;

        auto aabb_geometries = daxa::get<daxa::Span<daxa::BlasAabbGeometryInfo const>>(blas_build_infos.at(blas_build_infos.size() - 1).geometries);

        for (u32 i = 0; i < aabb_geometries.size(); i++)
        {
            std::cout << "      build_blas: aabb_geometry.data: " << aabb_geometries[i].data 
                << ", aabb_geometry.stride: " << aabb_geometries[i].stride << ", aabb_geometry.count: " 
                << aabb_geometries[i].count << std::endl;
        }
#endif // TRACE

        ++current_instance_index;
    }

    proc_blas_scratch_buffer_offset = 0;

    // Check if all instances were processed
    if (current_instance_index != instance_count)
    {
#if WARN
        std::cerr << "current_instance_index != current_instance_count" << std::endl;
#endif // WARN
        return false;
    }

    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::HOST_WRITE,
            .dst_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_READ_WRITE,
        });
        recorder.build_acceleration_structures({
            .blas_build_infos = blas_build_infos,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});

    return true;
}

bool ACCEL_STRUCT_MNGR::build_tlas(u32 buffer_index, bool synchronize)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    if (buffer_index >= DOUBLE_BUFFERING)
    {
#if WARN
        std::cerr << "buffer_index >= tlas.size()" << std::endl;
#endif // WARN
        return false;
    }

    if (tlas[buffer_index] != daxa::TlasId{})
        device.destroy_tlas(tlas[buffer_index]);

    std::vector<daxa_BlasInstanceData> blas_instance_array = {};
    blas_instance_array.reserve(current_instance_count[buffer_index]);

    // build procedural blas
    for (u32 i = 0; i < current_instance_count[buffer_index]; i++)
    {
        blas_instance_array.push_back(daxa_BlasInstanceData{
            .transform =
                daxa_f32mat4x4_to_daxa_f32mat3x4(instances[i].transform),
            .instance_custom_index = i, // Is also default
            .mask = 0xFF,
            .instance_shader_binding_table_record_offset = {}, // Is also default
            .flags = {},                                       // Is also default
            .blas_device_address = device.get_device_address(this->proc_blas.at(i)).value(),
        });
    }

    /// create blas instances for tlas:
    auto blas_instances_buffer = device.create_buffer({
        .size = sizeof(daxa_BlasInstanceData) * current_instance_count[buffer_index],
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = "blas instances array buffer",
    });
    defer { device.destroy_buffer(blas_instances_buffer); };
    std::memcpy(device.get_host_address_as<daxa_BlasInstanceData>(blas_instances_buffer).value(),
                blas_instance_array.data(),
                blas_instance_array.size() * sizeof(daxa_BlasInstanceData));

    auto blas_instances = std::array{
        daxa::TlasInstanceInfo{
            .data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
            .count = current_instance_count[buffer_index],
            .is_data_array_of_pointers = false, // Buffer contains flat array of instances, not an array of pointers to instances.
            // .flags = daxa::GeometryFlagBits::OPAQUE,
            .flags = static_cast<daxa::GeometryFlags>(0x1),
        }};
    auto tlas_build_info = daxa::TlasBuildInfo{
        .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD,
        .dst_tlas = {}, // Ignored in get_acceleration_structure_build_sizes.
        .instances = blas_instances,
        .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.
    };
    daxa::AccelerationStructureBuildSizesInfo tlas_build_sizes = device.get_tlas_build_sizes(tlas_build_info);
    // TODO: Try to resize buffer if necessary and not build everytime
    /// Create Tlas:
    this->tlas[buffer_index] = device.create_tlas({
        .size = tlas_build_sizes.acceleration_structure_size,
        .name = "tlas",
    });
    /// Create Build Scratch buffer
    auto tlas_scratch_buffer = device.create_buffer({
        .size = tlas_build_sizes.build_scratch_size,
        .name = "tlas build scratch buffer",
    });
    defer { device.destroy_buffer(tlas_scratch_buffer); };
    /// Update build info:
    tlas_build_info.dst_tlas = this->tlas[buffer_index];
    tlas_build_info.scratch_data = device.get_device_address(tlas_scratch_buffer).value();
    blas_instances[0].data = device.get_device_address(blas_instances_buffer).value();

    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::HOST_WRITE,
            .dst_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_READ_WRITE,
        });
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_WRITE,
            .dst_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_READ_WRITE,
        });
        recorder.build_acceleration_structures({
            .tlas_build_infos = std::array{tlas_build_info},
        });
        recorder.pipeline_barrier({
            .src_access = daxa::AccessConsts::ACCELERATION_STRUCTURE_BUILD_WRITE,
            .dst_access = daxa::AccessConsts::READ_WRITE,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});
    if (synchronize)
    {
        device.wait_idle();
    }
    /// NOTE:
    /// No need to wait idle here.
    /// Daxa will defer all the destructions of the buffers until the submitted as build commands are complete.

    return true;
}

bool ACCEL_STRUCT_MNGR::clear_light_remapping_buffer(u32 instance_index, u32 light_index, u32 light_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return false;
    }

    // Copy last primitive to deleted primitive
    if (light_index != -1)
    {
        size_t remapped_primitive_buffer_size = sizeof(u32) * 2;

        auto remapped_primitive_staging_buffer = device.create_buffer({
            .size = remapped_primitive_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

        u32 remapped_primitive_indexes[2] = {0, 0};

        auto *remapped_primitive_buffer_ptr = device.get_host_address_as<u32>(remapped_primitive_staging_buffer).value();
        std::memcpy(remapped_primitive_buffer_ptr,
                    remapped_primitive_indexes,
                    remapped_primitive_buffer_size);

        copy_buffer(remapped_primitive_staging_buffer, remapping_light_buffer, 0, light_index * sizeof(u32), sizeof(u32));
        if (light_to_exchange != -1)
        {
            copy_buffer(remapped_primitive_staging_buffer, remapping_light_buffer, sizeof(u32), light_to_exchange * sizeof(u32), sizeof(u32));
        }
    }

    return true;
}

//////////////////////////////// SETTLING - UNDO  STARTS//////////////////////////////////////

void ACCEL_STRUCT_MNGR::process_undo_settling_task_queue(u32 next_index, TASK &task)
{

    // Process task
    switch (task.type)
    {
    case TASK::TYPE::BUILD_BLAS_FROM_CPU:
    {
        TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
    }
    break;
    case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
    {
        TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
        // TODO: this can be optimize cause just deleted primitive is needed to be cleared
        // Restore remapping buffer
        clear_remapping_buffer(next_index, rebuild_task.del_primitive_index, rebuild_task.remap_primitive_index);
        // Restore light remapping buffer
        clear_light_remapping_buffer(next_index, rebuild_task.del_light_index, rebuild_task.remap_light_index);
        // NOTE: build_blas is already called for the previous index
    }
    break;
    case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
    {
        TASK::BLAS_UPDATE update_task = task.blas_update;
        // update_blas(next_index, update_task.instance_index);
    }
    break;
    case TASK::TYPE::UNDO_OP_CPU:
    {
        if (task.undo_op_cpu.undo_task)
        {
#if FATAL
            std::cerr << "      UNDO_OP_CPU should not reach process_undo_settling_task_queue" << std::endl;
#endif // FATAL
            std::abort();
        }
    }
    break;
    default:
    {
    }
    break;
    }
}

//////////////////////////////// SETTLING - UNDO  ENDS//////////////////////////////////////

//////////////////////////////// PROCESSING //////////////////////////////////////

using TASK = cubeland::ACCEL_STRUCT_MNGR::TASK;

void ACCEL_STRUCT_MNGR::process_task_queue()
{

    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return;
    }

    if (items_to_process == 0)
    {
        // Set switching to false
        status = AS_MANAGER_STATUS::IDLE;
        return;
    }

    u32 next_index = (current_index + 1) % DOUBLE_BUFFERING;

    u32 primitive_to_exchange = 0;
    u32 light_to_exchange = -1;
    u32 light_to_delete = -1;
    u32 light_index_from_exchanged_primitive = -1;
    temp_cube_light_count = *current_cube_light_count;
    size_t primitive_buffer_offset = 0;

    std::vector<u32> blas_index_list = {};
    std::vector<u32> rebuild_blas_index_list = {};
    std::vector<u32> update_blas_index_list = {};

    // Iterate over all tasks to process
    for (u32 i = 0; i < items_to_process; i++)
    {
        auto task = task_queue.front();
        {
            // TODO: mutex here
            task_queue.pop();
        }
        // Process task
        switch (task.type)
        {
        case TASK::TYPE::BUILD_BLAS_FROM_CPU:
        {
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
            // Allocate new instance
            uuid32 new_instance_id = instance_free_list->allocate();
            if (new_instance_id == static_cast<uuid32>(-1))
            {
#if FATAL
                std::cerr << " Could not allocate instance from free list" << std::endl;
#endif // FATAL
                std::abort();
            }
            primitive_free_list->allocate(build_task.primitive_count, primitive_buffer_offset, new_instance_id);
            // Update primitive buffers
            upload_aabb_device_buffer(next_index, build_task.primitive_count, primitive_buffer_offset);
            // Update primitive count
            current_primitive_count[next_index] += build_task.primitive_count;
            // Update instance
            instances[new_instance_id].transform = build_task.transform;
            instances[new_instance_id].first_primitive_index = primitive_buffer_offset;
            instances[new_instance_id].primitive_count = build_task.primitive_count;
            // Keep blas id for building blas
            blas_index_list.push_back(new_instance_id);
            // Global instance count
            current_instance_count[next_index] += build_task.instance_count;
        }
        break;
        case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
        {
            TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
            // TODO: this will need a mutex if manager is parallelized
            {
                // Update instance primitive count
                primitive_to_exchange = --instances[rebuild_task.instance_index].primitive_count;
#if TRACE == 1
                std::cout << "  >Instance primitive count: " << instances[rebuild_task.instance_index].primitive_count << std::endl;
#endif // TRACE
            }
            // delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
            delete_aabb_device_buffer(next_index,
                                      rebuild_task.instance_index,
                                      rebuild_task.del_primitive_index,
                                      primitive_to_exchange,
                                      light_to_delete,
                                      light_to_exchange,
                                      light_index_from_exchanged_primitive);
            // Update remapping buffer
            update_remapping_buffer(rebuild_task.instance_index, rebuild_task.del_primitive_index, primitive_to_exchange);
            // update light remapping buffer
            update_light_remapping_buffer(light_to_delete, light_to_exchange);
            // keep blas id for rebuilding blas
            rebuild_blas_index_list.push_back(rebuild_task.instance_index);
            // save primitive to exchange for next frame
            task.blas_delete_primitive_from_cpu.remap_primitive_index = primitive_to_exchange;
            // save light to delete if any
            task.blas_delete_primitive_from_cpu.del_light_index = light_to_delete;
            // save light to exchange for next frame
            task.blas_delete_primitive_from_cpu.remap_light_index = light_to_exchange;
            // save light index of the exchanged primitive
            task.blas_delete_primitive_from_cpu.remap_primitive_light_index = light_index_from_exchanged_primitive;
        }
        break;
        case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
        {
            TASK::BLAS_UPDATE update_task = task.blas_update;
            instances[update_task.instance_index].transform = 
                daxa_f32mat4x4_mult(instances[update_task.instance_index].transform, update_task.transform);

#if TRACE == 1
            // print transform matrix
            std::cout << "matrix instance_index: " << update_task.instance_index << std::endl;
            std::cout << "  [" << instances[update_task.instance_index].transform.x.x << ", " << 
                instances[update_task.instance_index].transform.x.y << ", " << 
                instances[update_task.instance_index].transform.x.z << ", " << 
                instances[update_task.instance_index].transform.x.w << "]" << std::endl;
            std::cout << "  [" << instances[update_task.instance_index].transform.y.x << ", " <<
                instances[update_task.instance_index].transform.y.y << ", " <<
                instances[update_task.instance_index].transform.y.z << ", " <<
                instances[update_task.instance_index].transform.y.w << "]" << std::endl;
            std::cout << "  [" << instances[update_task.instance_index].transform.z.x << ", " <<
                instances[update_task.instance_index].transform.z.y << ", " <<
                instances[update_task.instance_index].transform.z.z << ", " <<
                instances[update_task.instance_index].transform.z.w << "]" << std::endl;
            std::cout << "  [" << instances[update_task.instance_index].transform.w.x << ", " <<
                instances[update_task.instance_index].transform.w.y << ", " <<
                instances[update_task.instance_index].transform.w.z << ", " <<
                instances[update_task.instance_index].transform.w.w << "]" << std::endl;
#endif // TRACE

            if(update_task.primitive_count > 0)
            {
                    // update aabb buffer
                update_aabb_device_buffer(next_index, 
                    update_task.instance_index, 
                    update_task.primitive_count, 
                    update_task.primitive_index_buf_offset,
                    update_task.aabb_buf_offset);
            }

            update_blas_index_list.push_back(update_task.instance_index);
        }
        break;
        case TASK::TYPE::DELETE_BLAS_FROM_CPU:
        {
            TASK::BLAS_DELETE_FROM_CPU delete_task = task.blas_delete_from_cpu;
            // TODO: this will need a mutex if manager is parallelized
            {
                // Update instance count
                current_instance_count[next_index]--;
            }
            // TODO: free instance buffers (aabb & primitive) free list
            // delete_aabb_device_buffer(next_index, delete_task.instance_index);
            // TODO: delete emissive light buffer(in the next step?)
            // delete_light_device_buffer(next_index, delete_task.instance_index);
            // free instance
            instance_free_list->deallocate(delete_task.instance_index);
        }
        break;
        case TASK::TYPE::UNDO_OP_CPU:
        {
            if (!done_task_stack.empty())
            {
                task.undo_op_cpu.undo_task = &done_task_stack.top();
                process_undo_task_queue(next_index, *task.undo_op_cpu.undo_task);
            }
        }
        break;
        default:
        {
        }
        break;
        }

        // archieve task
        temporal_task_queue.push(task);
    }

    // Set items to process to zero
    items_to_process = 0;

    // update instances
    upload_all_instances(next_index, false);

    // TODO: issue builds, rebuilds & updates together?
    // Build BLASes
    if (!blas_index_list.empty())
        build_blases(next_index, blas_index_list);

    // Rebuild BLASes
    if (!rebuild_blas_index_list.empty()) {
        rebuild_blases(next_index, rebuild_blas_index_list);
    }

    
    // Build BLASes
    if (!update_blas_index_list.empty()) {
        // TODO: find a better way to get unique indices
        auto ip = std::unique(update_blas_index_list.begin(), update_blas_index_list.begin() + update_blas_index_list.size());
        update_blas_index_list.resize(std::distance(update_blas_index_list.begin(), ip));
        update_blases(next_index, update_blas_index_list);
    }

    // Build TLAS
    build_tlas(next_index, true);

    // Set current index as updated
    index_updated[next_index] = true;
    // Reset host aabb buffer to the next index
    current_aabb_host_idx = 0;
    // Reset temp instance count
    temp_instance_count = 0;
    // Reset temp primitive count
    temp_primitive_count = 0;
    // Reset temp primitive index count
    temp_primitive_index_count = 0;

    {
        // TODO: mutex here
        // Set switching to true
        status = AS_MANAGER_STATUS::SWITCHING;
    }
}

void ACCEL_STRUCT_MNGR::process_switching_task_queue()
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return;
    }

    u32 next_index = (current_index + 1) % DOUBLE_BUFFERING;

    while (!temporal_task_queue.empty())
    {
        auto task = temporal_task_queue.front();
        temporal_task_queue.pop();
        // Process task
        switch (task.type)
        {
        case TASK::TYPE::BUILD_BLAS_FROM_CPU:
        {
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
            copy_aabb_device_buffer(next_index, build_task.primitive_count);
            current_primitive_count[next_index] += build_task.primitive_count;
            // NOTE: build_blas is already called for the previous index
            current_instance_count[next_index] += build_task.instance_count;
        }
        break;
        case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
        {
            TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
            if (rebuild_task.del_primitive_index != rebuild_task.remap_primitive_index)
            {
                // Copy deleted primitive to the double buffer
                copy_deleted_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index);
            }
            // delete light from buffer
            delete_light_device_buffer(next_index, rebuild_task.del_light_index, rebuild_task.remap_light_index,
                                       rebuild_task.del_primitive_index, rebuild_task.remap_primitive_light_index);
        }
        break;
        case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
        {
            TASK::BLAS_UPDATE update_task = task.blas_update;
            if(update_task.primitive_count > 0)
            {
                // update aabb buffer
                copy_updated_aabb_device_buffer(next_index, 
                    update_task.instance_index, 
                    update_task.primitive_count, 
                    update_task.primitive_index_buf_offset,
                    update_task.aabb_buf_offset);
            }
            // TODO: update light buffer
        }
        break;
        case TASK::TYPE::UNDO_OP_CPU:
        {
            // TODO: undo task
            if (task.undo_op_cpu.undo_task)
            {
                process_undo_switching_task_queue(next_index, *task.undo_op_cpu.undo_task);
            }
        }
        break;
        default:
        {
        }
        break;
        }

        // archieve task
        switching_task_queue.push(task);
    }

    // update light count
    *current_cube_light_count = temp_cube_light_count;

    {
        // TODO: mutex here
        // Set updating to false
        status = AS_MANAGER_STATUS::SETTLING;
    }
}

void ACCEL_STRUCT_MNGR::process_settling_task_queue()
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return;
    }

    u32 next_index = (current_index + 1) % DOUBLE_BUFFERING;

    while (!switching_task_queue.empty())
    {
        auto task = switching_task_queue.front();
        switching_task_queue.pop();
        // Process task
        switch (task.type)
        {
        case TASK::TYPE::BUILD_BLAS_FROM_CPU:
        {
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
        }
        break;
        case TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU:
        {
            TASK::BLAS_PRIMITIVE_DELETE_FROM_CPU rebuild_task = task.blas_delete_primitive_from_cpu;
            // Restore remapping buffer
            clear_remapping_buffer(next_index, rebuild_task.del_primitive_index, rebuild_task.remap_primitive_index);
            // Restore light remapping buffer
            clear_light_remapping_buffer(next_index, rebuild_task.del_light_index, rebuild_task.remap_light_index);
            // NOTE: build_blas is already called for the previous index
        }
        break;
        case TASK::TYPE::UPDATE_BLAS_FROM_CPU:
        { 
            // TODO: do we need to do something here?
        }
        break;
        case TASK::TYPE::UNDO_OP_CPU:
        {
            if (task.undo_op_cpu.undo_task)
            {
                process_undo_settling_task_queue(next_index, *task.undo_op_cpu.undo_task);
            }
        }
        break;
        default:
        {
        }
        break;
        };

        if (task.type != TASK::TYPE::UNDO_OP_CPU)
        {
            // archieve task
            done_task_stack.push(task);
        }
        else if (!done_task_stack.empty())
        {
            // pop undo task
            done_task_stack.pop();
        }
    }

    // update instances
    upload_all_instances(next_index, false);

    // Build TLAS
    build_tlas(next_index, true);

    // Set current index as updated
    index_updated[next_index] = true;

    {
        // TODO: mutex here
        // Set updating to false
        status = AS_MANAGER_STATUS::IDLE;
    }

    // delete temp proc blas
    for (auto blas : temp_proc_blas)
        if (blas != daxa::BlasId{}) {      
#if TRACE
    std::cout << "  delete temp proc blas: " << blas.index << ", version: " << blas.version << std::endl;
#endif
            blas_free_list->deallocate(blas);
        }

    temp_proc_blas.clear();
}

void ACCEL_STRUCT_MNGR::process_voxel_modifications()
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return;
    }

    // Bring bitmask to host
    auto instance_bitmask_staging_buffer = device.create_buffer({
        .size = max_instance_bitmask_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
        .name = ("instance_bitmask_staging_buffer"),
    });
    defer { device.destroy_buffer(instance_bitmask_staging_buffer); };

    copy_buffer(brush_instance_bitmask_buffer, instance_bitmask_staging_buffer, 0, 0, max_instance_bitmask_size, false);

    // Bring voxel modifications to host
    auto primitive_bitmask_staging_buffer = device.create_buffer({
        .size = max_primitive_bitmask_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
        .name = ("voxel_modifications_staging_buffer"),
    });
    defer { device.destroy_buffer(primitive_bitmask_staging_buffer); };

    copy_buffer(brush_primitive_bitmask_buffer, primitive_bitmask_staging_buffer, 0, 0, max_primitive_bitmask_size, true);

    auto *instance_bitmask_buffer_ptr = device.get_host_address_as<u32>(instance_bitmask_staging_buffer).value();

    auto *voxel_modifications_buffer_ptr = device.get_host_address_as<u32>(primitive_bitmask_staging_buffer).value();

    u32 changes_so_far = 0;

    // Check instances first
    for (u32 i = 0; i < (current_instance_count[current_index]); i++)
    {
        if (instance_bitmask_buffer_ptr[i] != 0U)
        {
            for (u32 j = 0; j < 32 && j < current_instance_count[current_index]; j++)
            {
                if (instance_bitmask_buffer_ptr[i] & (1 << j))
                {
                    u32 instance_index = i * 32 + j;
                    // Process instance
                    INSTANCE instance = instances[instance_index];
#if TRACE == 1
                    std::cout << "Instance: " << instance_index << " Primitive count: " << instance.primitive_count << " First primitive index: " << instance.first_primitive_index << std::endl;
#endif // TRACE
                    u32 first_primitive_mask_index = (instance.first_primitive_index) >> 5;
                    u32 max_instance_bitmask_size = (instance.first_primitive_index + instance.primitive_count) >> 5;
                    u32 first_l = 0;
                    for (u32 k = first_primitive_mask_index; k <= max_instance_bitmask_size; k++)
                    {
                        u32 l = 0;
                        u32 last_l = 32;
                        if (k == first_primitive_mask_index)
                            first_l = l = (instance.first_primitive_index) & 31;
                        else if (k == max_instance_bitmask_size)
                        {
                            last_l = (instance.first_primitive_index + instance.primitive_count) & 31;
                        }
                        if (voxel_modifications_buffer_ptr[k] != 0U)
                        {
                            for (; l < last_l; l++)
                            {
                                if (voxel_modifications_buffer_ptr[k] & (1 << l))
                                {
                                    changes_so_far++;
                                    u32 instance_primitive = (32 - first_l) + ((k - first_primitive_mask_index - 1) * 32) + l;
                                    // Process primitive
#if TRACE == 1
                                    std::cout << "Instance: " << instance_index << " Primitive: " << instance_primitive << std::endl;
#endif // TRACE
                                    {

                                        auto task_queue = TASK{
                                            .type = TASK::TYPE::DELETE_PRIMITIVE_BLAS_FROM_CPU,
                                            .blas_delete_primitive_from_cpu = {.instance_index = instance_index, .del_primitive_index = instance_primitive},
                                        };
                                        task_queue_add(task_queue);
                                    }

                                    // Check if all changes were processed
                                    if (changes_so_far >= brush_counters->primitive_count)
                                    {
                                        goto restore_buffers;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

restore_buffers:
    if (brush_counters->primitive_count > 0)
    {
        // Reset bitmasks
        std::memset(instance_bitmask_buffer_ptr, 0, max_instance_bitmask_size);

        std::memset(voxel_modifications_buffer_ptr, 0, max_primitive_bitmask_size);

        copy_buffer(instance_bitmask_staging_buffer, brush_instance_bitmask_buffer, 0, 0, max_instance_bitmask_size, false);

        copy_buffer(primitive_bitmask_staging_buffer, brush_primitive_bitmask_buffer, 0, 0, max_primitive_bitmask_size, true);
    }
}

void ACCEL_STRUCT_MNGR::check_voxel_modifications()
{
    if (!device.is_valid() || !initialized)
    {
#if WARN
        std::cerr << "device.is_valid()" << std::endl;
#endif // WARN
        return;
    }

    if (brush_counters->instance_count > 0)
    {
#if TRACE == 1
        std::cout << "  Modifications instances: " << brush_counters->instance_count << " primitives: " << brush_counters->primitive_count << std::endl;
#endif // TRACE

        // Bring bitmask to host
        process_voxel_modifications();

        // zero out brush counters
        brush_counters->instance_count = 0;
        brush_counters->primitive_count = 0;
    }
}