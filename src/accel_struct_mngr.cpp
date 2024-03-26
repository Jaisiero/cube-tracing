#include "ACCEL_STRUCT_MNGR.hpp"

using AS_MANAGER_STATUS = ACCEL_STRUCT_MNGR::AS_MANAGER_STATUS;

void worker_thread_fn(std::stop_token stoken, ACCEL_STRUCT_MNGR* as_manager)
{
    while(!stoken.stop_requested())
    {
#if DEBUG == 1                    
        std::cout << "Worker thread is sleeping" << std::endl;
#endif // DEBUG                             
        // Wait for task queue to wake up
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->task_queue_cv.wait(lock, [&] { return as_manager->is_wake_up() || stoken.stop_requested(); });
        }
#if DEBUG == 1                    
        std::cout << "Worker thread woke up" << std::endl;
#endif // DEBUG                             

        // Check if stop is requested
        if(stoken.stop_requested()) {
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
            std::cerr << "Unknown status" << std::endl;
            break;
        }

        // set update done
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->set_wake_up(false);
        }

        // Notify that the task is done
        if(as_manager->is_synchronizing()) {
            std::unique_lock lock(as_manager->synchronize_mutex);

            // Set synchronizing to false
            as_manager->set_synchronizing(false);

            as_manager->synchronize_cv.notify_one();
        }

    };
}

bool ACCEL_STRUCT_MNGR::create(uint32_t max_instance_count, uint32_t max_primitive_count, uint32_t max_cube_light_count, uint32_t* cube_light_count) {
    if(device.is_valid() && !initialized) {
        proc_blas_scratch_buffer_size = max_instance_count * 1024ULL * 2ULL; // TODO: is this a good estimation?
        proc_blas_buffer_size = max_instance_count * 1024ULL * 2ULL;         // TODO: is this a good estimation?
        max_instance_buffer_size = sizeof(INSTANCE) * max_instance_count;
        max_aabb_buffer_size = sizeof(AABB) * max_primitive_count;
        max_aabb_host_buffer_size = sizeof(AABB) * max_primitive_count * 0.1;
        max_primitive_buffer_size = sizeof(PRIMITIVE) * max_primitive_count;
        max_cube_light_buffer_size = sizeof(LIGHT) * max_cube_light_count;
        max_remapping_primitive_buffer_size = sizeof(uint32_t) * max_primitive_count;
        max_remapping_light_buffer_size = sizeof(uint32_t) * max_cube_light_count;
        max_instance_bitmask_size = max_instance_count / sizeof(uint32_t) + 1;
        max_primitive_bitmask_size = max_primitive_count / sizeof(uint32_t) + 1;

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

        // Clear previous procedural blas
        this->proc_blas.clear();

        for(uint32_t i = 0; i < DOUBLE_BUFFERING; i++) {
            tlas[i] = daxa::TlasId{};
            instance_buffer[i] = device.create_buffer({
                .size = max_instance_buffer_size,
                .name = ("instance_buffer_" + std::to_string(i)),
            });
        }

        for(uint32_t i = 0; i < DOUBLE_BUFFERING; i++) {
            primitive_buffer[i] = device.create_buffer({
                .size = max_primitive_buffer_size,
                .name = ("primitive_buffer_" + std::to_string(i)),
            });
        }

        for(uint32_t i = 0; i < DOUBLE_BUFFERING; i++) {
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

bool ACCEL_STRUCT_MNGR::destroy() {

    if (device.is_valid() && initialized)
    {
        for (auto _tlas : tlas)
            if (_tlas != daxa::TlasId{})
                device.destroy_tlas(_tlas);
        for (auto blas : proc_blas)
            if(blas != daxa::BlasId{})
                device.destroy_blas(blas);

        if (proc_blas_scratch_buffer != daxa::BufferId{})
            device.destroy_buffer(proc_blas_scratch_buffer);
        if (proc_blas_buffer != daxa::BufferId{})
            device.destroy_buffer(proc_blas_buffer);

        for (auto buffer : instance_buffer)
            if (buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);

        for (auto buffer : aabb_buffer)
            if(buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);
        
        if(aabb_host_buffer != daxa::BufferId{})
            device.destroy_buffer(aabb_host_buffer);
        
        for(auto buffer : primitive_buffer)
            if(buffer != daxa::BufferId{})
                device.destroy_buffer(buffer);

        if(remapping_primitive_buffer != daxa::BufferId{})
            device.destroy_buffer(remapping_primitive_buffer);

        if(cube_light_buffer != daxa::BufferId{})
            device.destroy_buffer(cube_light_buffer);

        if(remapping_light_buffer != daxa::BufferId{})
            device.destroy_buffer(remapping_light_buffer);

        if(brush_counter_buffer != daxa::BufferId{})
            device.destroy_buffer(brush_counter_buffer);

        if(brush_instance_bitmask_buffer != daxa::BufferId{})
            device.destroy_buffer(brush_instance_bitmask_buffer);

        if(brush_primitive_bitmask_buffer != daxa::BufferId{})
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

void ACCEL_STRUCT_MNGR::upload_primitives(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size, bool synchronize)
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
    if(synchronize) {
        device.wait_idle();
    }
}

bool ACCEL_STRUCT_MNGR::upload_primitive_device_buffer(uint32_t buffer_index, uint32_t primitive_count)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t previous_primitive_count = current_primitive_count[buffer_index];
    uint32_t primitive_count_offset = previous_primitive_count * sizeof(PRIMITIVE);
    uint32_t primitive_buffer_size = primitive_count * sizeof(PRIMITIVE);
    uint32_t current_primitive_count = previous_primitive_count + primitive_count;
    uint32_t current_primitive_count_offset = current_primitive_count * sizeof(PRIMITIVE);

    if (current_primitive_count_offset > max_primitive_buffer_size)
    {
        std::cerr << "primitive_buffer_size > max_primitive_buffer_size" << std::endl;
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
                primitives.get(),
                primitive_buffer_size);

    upload_primitives(primitive_staging_buffer, primitive_buffer[buffer_index], primitive_count_offset, primitive_count_offset, primitive_buffer_size);

    return true;
}

bool ACCEL_STRUCT_MNGR::copy_primitive_device_buffer(uint32_t buffer_index, uint32_t primitive_count)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t previous_primitive_count = current_primitive_count[buffer_index];
    uint32_t primitive_count_offset = previous_primitive_count * sizeof(PRIMITIVE);
    uint32_t primitive_buffer_size = primitive_count * sizeof(PRIMITIVE);
    uint32_t current_primitive_count = previous_primitive_count + primitive_count;
    uint32_t current_primitive_count_offset = current_primitive_count * sizeof(PRIMITIVE);

    if (current_primitive_count_offset > max_primitive_buffer_size)
    {
        std::cerr << "primitive_buffer_size > max_primitive_buffer_size" << std::endl;
        return false;
    }

    uint32_t previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;
    upload_primitives(primitive_buffer[previous_buffer_index], primitive_buffer[buffer_index], primitive_count_offset, primitive_count_offset, primitive_buffer_size);

    return true;
}

void ACCEL_STRUCT_MNGR::upload_aabb_primitives(daxa::BufferId src_abb_buffer, daxa::BufferId dst_aabb_buffer, size_t src_aabb_buffer_offset, size_t dst_aabb_buffer_offset, size_t aabb_copy_size, bool synchronize)
{
    /// Record build commands:
    auto exec_cmds = [&]()
    {
        auto recorder = device.create_command_recorder({});

        recorder.copy_buffer_to_buffer({
            .src_buffer = src_abb_buffer,
            .dst_buffer = dst_aabb_buffer,
            .src_offset = src_aabb_buffer_offset,
            .dst_offset = dst_aabb_buffer_offset,
            .size = aabb_copy_size,
        });

        return recorder.complete_current_commands();
    }();
    device.submit_commands({.command_lists = std::array{exec_cmds}});
    if(synchronize) {
        device.wait_idle();
    }
}

bool ACCEL_STRUCT_MNGR::upload_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    if (aabb_host_count > 0)
    {
        size_t aabb_copy_size = aabb_host_count * sizeof(AABB);
        size_t aabb_buffer_offset = current_primitive_count[buffer_index] * sizeof(AABB);
        upload_aabb_primitives(aabb_host_buffer, aabb_buffer[buffer_index], aabb_buffer_offset, aabb_buffer_offset, aabb_copy_size);

        if(!upload_primitive_device_buffer(buffer_index, aabb_host_count)) {
            std::cerr << "Failed to load primitives" << std::endl;
            return false;
        }
        // current_aabb_host_count = 0;
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::copy_aabb_device_buffer(uint32_t buffer_index, uint32_t aabb_host_count)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    if (aabb_host_count > 0)
    {
        size_t aabb_copy_size = aabb_host_count * sizeof(AABB);
        size_t aabb_buffer_offset = current_primitive_count[buffer_index] * sizeof(AABB);
        uint32_t previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;
        upload_aabb_primitives(aabb_buffer[previous_buffer_index], aabb_buffer[buffer_index], aabb_buffer_offset, aabb_buffer_offset, aabb_copy_size);

        if(!copy_primitive_device_buffer(buffer_index, aabb_host_count)) {
            std::cerr << "Failed to load primitives" << std::endl;
            return false;
        }
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::delete_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange, uint32_t& light_to_delete, uint32_t& light_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t first_primitive_index = instances[instance_index].first_primitive_index;


    // Copy last primitive to deleted primitive
    if(primitive_to_exchange != primitive_index) {

        uint32_t last_primitive_index = first_primitive_index + primitive_to_exchange;
        uint32_t primitive_to_delete = first_primitive_index + primitive_index;

        // Keep track of primitive light to delete
        if (primitives[primitive_to_delete].light_index != -1)
        {
            light_to_delete = primitives[primitive_to_delete].light_index;
            // Decrement temp light count
            light_to_exchange = --temp_cube_light_count;
        }

        // Backup of the deleted primitive and light
        {

            size_t multipurpose_staging_buffer_size = sizeof(AABB) + sizeof(PRIMITIVE);

            auto multipurpose_staging_buffer = device.create_buffer({
                .size = multipurpose_staging_buffer_size,
                .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                .name = ("primitive_staging_buffer"),
            });
            defer { device.destroy_buffer(multipurpose_staging_buffer); };

            // Copy backup of AABB to delete
            upload_aabb_primitives(aabb_buffer[buffer_index], multipurpose_staging_buffer, primitive_to_delete * sizeof(AABB), 0, sizeof(AABB));
            // Copy backup of primitive to delete
            upload_primitives(primitive_buffer[buffer_index], multipurpose_staging_buffer, primitive_to_delete * sizeof(PRIMITIVE), sizeof(AABB), sizeof(PRIMITIVE), true);
            
            auto *primitive_buffer_ptr = device.get_host_address_as<uint8_t>(multipurpose_staging_buffer).value();

            // Store backup of AABB
            backup_aabbs.push_back(*(reinterpret_cast<AABB*>(primitive_buffer_ptr)));
            // Sotre backup of PRIMITIVE
            backup_primitives.push_back(*(reinterpret_cast<PRIMITIVE*>(primitive_buffer_ptr + sizeof(AABB))));

            // increase backup primitive counter
            ++backup_primitive_count;
            
            if(light_to_delete != -1) {
                // keep backup of light to delete
                backup_cube_lights.push_back(cube_lights[light_to_delete]);
                // increase backup light counter
                ++backup_light_count;
            }
        }

        // Copying last primitive to deleted primitive
        {
            // Copy AABB
            upload_aabb_primitives(aabb_buffer[buffer_index], aabb_buffer[buffer_index], last_primitive_index * sizeof(AABB), primitive_to_delete * sizeof(AABB), sizeof(AABB));
            // Copy primitive
            upload_primitives(primitive_buffer[buffer_index], primitive_buffer[buffer_index], last_primitive_index * sizeof(PRIMITIVE), primitive_to_delete * sizeof(PRIMITIVE), sizeof(PRIMITIVE));
        }
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::copy_deleted_aabb_device_buffer(uint32_t buffer_index, uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t first_primitive_index = instances[instance_index].first_primitive_index;

    // Copy last primitive to deleted primitive
    if(primitive_to_exchange != primitive_index) {

        uint32_t last_primitive_index = first_primitive_index + primitive_to_exchange;
        uint32_t primitive_to_delete = first_primitive_index + primitive_index;

        uint32_t previous_buffer_index = (buffer_index - 1) % DOUBLE_BUFFERING;

        // Copy AABB from previous buffer to current buffer
        upload_aabb_primitives(aabb_buffer[previous_buffer_index], aabb_buffer[buffer_index], primitive_to_delete * sizeof(AABB), primitive_to_delete * sizeof(AABB), sizeof(AABB));
        // Copy primitive from previous buffer to current buffer
        upload_primitives(primitive_buffer[previous_buffer_index], primitive_buffer[buffer_index], primitive_to_delete * sizeof(PRIMITIVE), primitive_to_delete * sizeof(PRIMITIVE), sizeof(PRIMITIVE));
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::delete_light_device_buffer(uint32_t buffer_index, uint32_t light_to_delete, uint32_t light_to_exchange)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    if(light_to_delete != -1) {
        // Copy light
        cube_lights[light_to_delete] = cube_lights[light_to_exchange];
    }

    return true;
}



bool ACCEL_STRUCT_MNGR::update_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange) {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t first_primitive_index = instances[instance_index].first_primitive_index;

    // Copy last primitive to deleted primitive
    if(primitive_to_exchange != primitive_index) {

        uint32_t last_primitive_index = first_primitive_index + primitive_to_exchange;
        uint32_t primitive_to_delete = first_primitive_index + primitive_index;

        size_t remapped_primitive_buffer_size = sizeof(uint32_t) * 2;

        auto remapped_primitive_staging_buffer = device.create_buffer({
            .size = remapped_primitive_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

        uint32_t remapped_primitive_indexes[2] = {static_cast<uint32_t>(-1), primitive_to_delete};

        auto *remapped_primitive_buffer_ptr = device.get_host_address_as<uint32_t>(remapped_primitive_staging_buffer).value();
        std::memcpy(remapped_primitive_buffer_ptr,
                    remapped_primitive_indexes,
                    remapped_primitive_buffer_size);

    
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, primitive_to_delete * sizeof(uint32_t), sizeof(uint32_t));
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, sizeof(uint32_t), last_primitive_index * sizeof(uint32_t), sizeof(uint32_t));
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::update_light_remapping_buffer(uint32_t instance_index, uint32_t light_to_delete, uint32_t light_to_exchange) {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    // Copy last primitive to deleted primitive
    if(light_to_delete != light_to_exchange) {

        size_t remapped_light_buffer_size = sizeof(uint32_t) * 2;

        auto remapped_light_staging_buffer = device.create_buffer({
            .size = remapped_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_light_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_light_staging_buffer); };

        uint32_t remapped_light_indexes[2] = {static_cast<uint32_t>(-1), light_to_delete};

        auto *remapped_light_buffer_ptr = device.get_host_address_as<uint32_t>(remapped_light_staging_buffer).value();
        std::memcpy(remapped_light_buffer_ptr,
                    remapped_light_indexes,
                    remapped_light_buffer_size);

    
        upload_primitives(remapped_light_staging_buffer, remapping_light_buffer, 0, light_to_delete * sizeof(uint32_t), sizeof(uint32_t));
        upload_primitives(remapped_light_staging_buffer, remapping_light_buffer, sizeof(uint32_t), light_to_exchange * sizeof(uint32_t), sizeof(uint32_t));
    }

    return true;
}


bool ACCEL_STRUCT_MNGR::restore_remapping_buffer(uint32_t instance_index, uint32_t primitive_index, uint32_t primitive_to_exchange) {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    uint32_t first_primitive_index = instances[instance_index].first_primitive_index;

    // Copy last primitive to deleted primitive
    if(primitive_to_exchange != primitive_index) {

        uint32_t last_primitive_index = first_primitive_index + primitive_to_exchange;
        uint32_t primitive_to_delete = first_primitive_index + primitive_index;

        size_t remapped_primitive_buffer_size = sizeof(uint32_t) * 2;

        auto remapped_primitive_staging_buffer = device.create_buffer({
            .size = remapped_primitive_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

        uint32_t remapped_primitive_indexes[2] = {0, 0};

        auto *remapped_primitive_buffer_ptr = device.get_host_address_as<uint32_t>(remapped_primitive_staging_buffer).value();
        std::memcpy(remapped_primitive_buffer_ptr,
                    remapped_primitive_indexes,
                    remapped_primitive_buffer_size);

    
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, primitive_to_delete * sizeof(uint32_t), sizeof(uint32_t));
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, sizeof(uint32_t), last_primitive_index * sizeof(uint32_t), sizeof(uint32_t));
    }

    return true;
}

bool ACCEL_STRUCT_MNGR::restore_light_remapping_buffer(uint32_t instance_index, uint32_t light_index, uint32_t light_to_exchange) {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    // Copy last primitive to deleted primitive
    if(light_index != light_to_exchange && light_index != -1) {
        size_t remapped_primitive_buffer_size = sizeof(uint32_t) * 2;

        auto remapped_primitive_staging_buffer = device.create_buffer({
            .size = remapped_primitive_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("remapped_primitive_staging_buffer"),
        });
        defer { device.destroy_buffer(remapped_primitive_staging_buffer); };

        uint32_t remapped_primitive_indexes[2] = {0, 0};

        auto *remapped_primitive_buffer_ptr = device.get_host_address_as<uint32_t>(remapped_primitive_staging_buffer).value();
        std::memcpy(remapped_primitive_buffer_ptr,
                    remapped_primitive_indexes,
                    remapped_primitive_buffer_size);

    
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, 0, light_index * sizeof(uint32_t), sizeof(uint32_t));
        upload_primitives(remapped_primitive_staging_buffer, remapping_primitive_buffer, sizeof(uint32_t), light_to_exchange * sizeof(uint32_t), sizeof(uint32_t));
    }

    return true;
}



bool ACCEL_STRUCT_MNGR::build_blas(uint32_t buffer_index, uint32_t instance_count)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    // Get previous instance count
    uint32_t previous_instance_count = current_instance_count[buffer_index];
    // Get all instance count
    uint32_t all_instance_count = previous_instance_count + instance_count;

    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(instance_count);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(instance_count);


    uint32_t current_instance_index = 0;

    // build procedural blas
    for (uint32_t i = previous_instance_count; i < all_instance_count; i++)
    {
        aabb_geometries.at(current_instance_index).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[buffer_index]).value() + (instances[i].first_primitive_index * sizeof(AABB)),
            .stride = sizeof(AABB),
            .count = instances[i].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = 0x1, // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

        // Crear un daxa::Span a partir del vector
        daxa::Span<const daxa::BlasAabbGeometryInfo> geometry_span(aabb_geometries.at(current_instance_index).data(), aabb_geometries.at(current_instance_index).size());

        /// Create Procedural Blas:
        blas_build_infos.push_back(daxa::BlasBuildInfo{
            .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD, // Is also default
            .dst_blas = {},                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .geometries = geometry_span,
            .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
        });

        daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

        auto get_aligned = [&](uint64_t operand, uint64_t granularity) -> uint64_t
        {
            return ((operand + (granularity - 1)) & ~(granularity - 1));
        };

        uint32_t scratch_alignment_size = get_aligned(proc_build_size_info.build_scratch_size, acceleration_structure_scratch_offset_alignment);

        if ((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size)
        {
            // TODO: Try to resize buffer
            std::cerr << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
            return false;
        }
        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        uint32_t build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        if ((proc_blas_buffer_offset + build_aligment_size) > proc_blas_buffer_size)
        {
            // TODO: Try to resize buffer
            std::cerr << "proc_blas_buffer_offset > proc_blas_buffer_size" << std::endl;
            return false;
        }
        proc_blas.push_back(device.create_blas_from_buffer({
            .blas_info = {
                .size = proc_build_size_info.acceleration_structure_size,
                .name = "procedural blas",
            },
            .buffer_id = proc_blas_buffer,
            .offset = proc_blas_buffer_offset,
        }));

        proc_blas_buffer_offset += build_aligment_size;

        blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = proc_blas.at(proc_blas.size() - 1);

        ++current_instance_index;
    }

    proc_blas_scratch_buffer_offset = 0;

    // Check if all instances were processed
    if (current_instance_index != instance_count)
    {
        std::cerr << "current_instance_index != current_instance_count" << std::endl;
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



bool ACCEL_STRUCT_MNGR::rebuild_blas(uint32_t buffer_index, uint32_t instance_index)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    // TODO: adapt this to rebuild many BLAS at once
    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(1);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(1);

    // if(proc_blas.at(instance_index) != daxa::BlasId{})
    //     device.destroy_blas(proc_blas.at(instance_index));
    
    if(proc_blas.at(instance_index) != daxa::BlasId{})
        temp_proc_blas.push_back(proc_blas.at(instance_index));

    uint32_t current_instance_index = 0;

    // build procedural blas
    // for (uint32_t i = previous_instance_count; i < all_instance_count; i++)
    // {
        aabb_geometries.at(current_instance_index).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[buffer_index]).value() + (instances[instance_index].first_primitive_index * sizeof(AABB)),
            .stride = sizeof(AABB),
            .count = instances[instance_index].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = 0x1, // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

        // Crear un daxa::Span a partir del vector
        daxa::Span<const daxa::BlasAabbGeometryInfo> geometry_span(aabb_geometries.at(current_instance_index).data(), aabb_geometries.at(current_instance_index).size());

        /// Create Procedural Blas:
        blas_build_infos.push_back(daxa::BlasBuildInfo{
            .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_BUILD, // Is also default
            .dst_blas = {},                                                       // Ignored in get_acceleration_structure_build_sizes.       // Is also default
            .geometries = geometry_span,
            .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
        });

        daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

        auto get_aligned = [&](uint64_t operand, uint64_t granularity) -> uint64_t
        {
            return ((operand + (granularity - 1)) & ~(granularity - 1));
        };

        uint32_t scratch_alignment_size = get_aligned(proc_build_size_info.build_scratch_size, acceleration_structure_scratch_offset_alignment);

        if ((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size)
        {
            // TODO: Try to resize buffer
            std::cerr << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
            return false;
        }
        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        uint32_t build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        if ((proc_blas_buffer_offset + build_aligment_size) > proc_blas_buffer_size)
        {
            // TODO: Try to resize buffer
            std::cerr << "proc_blas_buffer_offset > proc_blas_buffer_size" << std::endl;
            return false;
        }


        // Replace old BLAS
        proc_blas.at(instance_index) = device.create_blas_from_buffer({
            .blas_info = {
                .size = proc_build_size_info.acceleration_structure_size,
                .name = "procedural blas",
            },
            .buffer_id = proc_blas_buffer,
            .offset = proc_blas_buffer_offset,
        });

        proc_blas_buffer_offset += build_aligment_size;

        blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = proc_blas.at(proc_blas.size() - 1);

        ++current_instance_index;
    // }

    proc_blas_scratch_buffer_offset = 0;

    // // Check if all instances were processed
    // if (current_instance_index != instance_count)
    // {
    //     std::cerr << "current_instance_index != current_instance_count" << std::endl;
    //     return false;
    // }

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




bool ACCEL_STRUCT_MNGR::update_blas(uint32_t buffer_index, uint32_t instance_index)
{
    // TODO: update blas here
    return true;
}

bool ACCEL_STRUCT_MNGR::build_tlas(uint32_t buffer_index, bool synchronize)
{
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return false;
    }

    if (buffer_index >= DOUBLE_BUFFERING)
    {
        std::cerr << "buffer_index >= tlas.size()" << std::endl;
        return false;
    }

    if (tlas[buffer_index] != daxa::TlasId{})
        device.destroy_tlas(tlas[buffer_index]);

    std::vector<daxa_BlasInstanceData> blas_instance_array = {};
    blas_instance_array.reserve(current_instance_count[buffer_index]);

    // build procedural blas
    for (uint32_t i = 0; i < current_instance_count[buffer_index]; i++)
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
            .flags = 0x1,
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

    // Copy instances to buffer
    uint32_t instance_buffer_size = static_cast<uint32_t>(current_instance_count[buffer_index] * sizeof(INSTANCE));
    if (instance_buffer_size > max_instance_buffer_size)
    {
        std::cerr << "instance_buffer_size > max_instance_buffer_size" << std::endl;
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

        recorder.copy_buffer_to_buffer({
            .src_buffer = instance_staging_buffer,
            .dst_buffer = instance_buffer[buffer_index],
            .size = instance_buffer_size,
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




void ACCEL_STRUCT_MNGR::process_undo_task_queue(uint32_t next_index, TASK& task) {

    uint32_t primitive_to_exchange = 0;
    uint32_t light_to_exchange = -1;
    uint32_t light_to_delete = -1;
    temp_cube_light_count = *current_cube_light_count;

    // Process task
    switch (task.type)
    {
    case TASK::TYPE::BUILD_BLAS_FROM_CPU:
        // TODO: Destroy BLAS
        break;
    case TASK::TYPE::REBUILD_BLAS_FROM_CPU:
        TASK::BLAS_REBUILD_FROM_CPU rebuild_task = task.blas_rebuild_from_cpu;
        // // TODO: this will need a mutex if manager is parallelized
        // {
        //     // Update instance primitive count
        //     primitive_to_exchange = --instances[rebuild_task.instance_index].primitive_count;
        // }
        // // delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
        // delete_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index, primitive_to_exchange, light_to_delete, light_to_exchange);
        // // Update remapping buffer
        // update_remapping_buffer(next_index, rebuild_task.del_primitive_index, primitive_to_exchange);
        // // update light remapping buffer
        // update_light_remapping_buffer(next_index, light_to_delete, light_to_exchange);
        // // rebuild blas
        // rebuild_blas(next_index, rebuild_task.instance_index);
        break;
    case TASK::TYPE::UPDATE_BLAS:
        TASK::BLAS_UPDATE update_task = task.blas_update;
        // update_blas(next_index, update_task.instance_index);
        break;
    case TASK::TYPE::UNDO_OP_CPU:
        std::cerr << "UNDO_OP_CPU impossible option" << std::endl;
        break;
    default:
        break;
    }
    
}







using TASK = ACCEL_STRUCT_MNGR::TASK;

void ACCEL_STRUCT_MNGR::process_task_queue() {

    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return;
    }

    if(items_to_process == 0) {
        // Set switching to false
        status = AS_MANAGER_STATUS::IDLE;
        return;
    }

    uint32_t next_index = (current_index + 1) % DOUBLE_BUFFERING;

    uint32_t primitive_to_exchange = 0;
    uint32_t light_to_exchange = -1;
    uint32_t light_to_delete = -1;
    temp_cube_light_count = *current_cube_light_count;

    // Iterate over all tasks to process
    for(uint32_t i = 0; i < items_to_process; i++)
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
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
            upload_aabb_device_buffer(next_index, build_task.primitive_count);
            current_primitive_count[next_index] += build_task.primitive_count;
            build_blas(next_index, build_task.instance_count);
            current_instance_count[next_index] += build_task.instance_count;
            break;
        case TASK::TYPE::REBUILD_BLAS_FROM_CPU:
            TASK::BLAS_REBUILD_FROM_CPU rebuild_task = task.blas_rebuild_from_cpu;
            // TODO: this will need a mutex if manager is parallelized
            {
                // Update instance primitive count
                primitive_to_exchange = --instances[rebuild_task.instance_index].primitive_count;
            }
            // delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
            delete_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index, primitive_to_exchange, light_to_delete, light_to_exchange);
            // Update remapping buffer
            update_remapping_buffer(next_index, rebuild_task.del_primitive_index, primitive_to_exchange);
            // update light remapping buffer
            update_light_remapping_buffer(next_index, light_to_delete, light_to_exchange);
            // rebuild blas
            rebuild_blas(next_index, rebuild_task.instance_index);
            // save primitive to exchange for next frame
            task.blas_rebuild_from_cpu.remap_primitive_index = primitive_to_exchange;
            // save light to delete if any
            task.blas_rebuild_from_cpu.del_light_index = light_to_delete;
            // save light to exchange for next frame
            task.blas_rebuild_from_cpu.remap_light_index = light_to_exchange;
            break;
        case TASK::TYPE::UPDATE_BLAS:
            TASK::BLAS_UPDATE update_task = task.blas_update;
            // update_blas(next_index, update_task.instance_index);
            break;
        case TASK::TYPE::UNDO_OP_CPU:
            // TODO: handle undo task
            if(!done_task_stack.empty()) {
                task.undo_op_cpu.undo_task = &done_task_stack.top();
                process_undo_task_queue(next_index, *task.undo_op_cpu.undo_task);
            }
            break;
        default:
            break;
        }

        // archieve task
        temporal_task_queue.push(task);
    }

    // Set items to process to zero
    items_to_process = 0;

    // Build TLAS
    build_tlas(next_index, true);

    // Set current index as updated
    index_updated[next_index] = true;

    // This should 

    {
        // TODO: mutex here
        // Switch to next index
        current_index = next_index;

        // Set switching to true
        status = AS_MANAGER_STATUS::SWITCHING;
    }
    
}


void ACCEL_STRUCT_MNGR::process_switching_task_queue() {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return;
    }
    
    uint32_t next_index = (current_index + 1) % DOUBLE_BUFFERING;

    while(!temporal_task_queue.empty()) {
        auto task = temporal_task_queue.front();
        temporal_task_queue.pop();
        // Process task
        switch (task.type)
        {
        case TASK::TYPE::BUILD_BLAS_FROM_CPU:
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
            copy_aabb_device_buffer(next_index, build_task.primitive_count);
            current_primitive_count[next_index] += build_task.primitive_count;
            // NOTE: build_blas is already called for the previous index
            current_instance_count[next_index] += build_task.instance_count;
            break;
        case TASK::TYPE::REBUILD_BLAS_FROM_CPU:
            TASK::BLAS_REBUILD_FROM_CPU rebuild_task = task.blas_rebuild_from_cpu;
            // delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
            copy_deleted_aabb_device_buffer(next_index, rebuild_task.instance_index, rebuild_task.del_primitive_index, task.blas_rebuild_from_cpu.remap_primitive_index);
            // delete light from buffer
            delete_light_device_buffer(next_index, task.blas_rebuild_from_cpu.del_light_index, task.blas_rebuild_from_cpu.remap_light_index);
            break;
        case TASK::TYPE::UPDATE_BLAS:
            TASK::BLAS_UPDATE update_task = task.blas_update;
            // update_blas(next_index, update_task.instance_index);
            break;
        case TASK::TYPE::UNDO_OP_CPU:
            // TODO: undo task
            if(task.undo_op_cpu.undo_task) {
                std::cerr << "  UNDO_OP_CPU not implemented yet" << std::endl;
            }
            break;
        default:
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


void ACCEL_STRUCT_MNGR::process_settling_task_queue() {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return;
    }
    
    uint32_t next_index = (current_index + 1) % DOUBLE_BUFFERING;

    while(!switching_task_queue.empty()) {
        auto task = switching_task_queue.front();
        switching_task_queue.pop();
        // Process task
        switch (task.type)
        {
        case TASK::TYPE::BUILD_BLAS_FROM_CPU:
            TASK::BLAS_BUILD_FROM_CPU build_task = task.blas_build_from_cpu;
            break;
        case TASK::TYPE::REBUILD_BLAS_FROM_CPU:
            TASK::BLAS_REBUILD_FROM_CPU rebuild_task = task.blas_rebuild_from_cpu;
            // Restore remapping buffer
            restore_remapping_buffer(next_index, rebuild_task.del_primitive_index, task.blas_rebuild_from_cpu.remap_primitive_index);
            // Restore light remapping buffer
            restore_light_remapping_buffer(next_index, rebuild_task.del_light_index, task.blas_rebuild_from_cpu.remap_light_index);
            // NOTE: build_blas is already called for the previous index
            break;
        case TASK::TYPE::UPDATE_BLAS:
            TASK::BLAS_UPDATE update_task = task.blas_update;
            // update_blas(next_index, update_task.instance_index);
            break;
        case TASK::TYPE::UNDO_OP_CPU:
            // TODO: undo task
            if(task.undo_op_cpu.undo_task) {
                std::cerr << "      UNDO_OP_CPU not implemented yet" << std::endl;
            }
        default:
            break;
        }

        if(task.type != TASK::TYPE::UNDO_OP_CPU) {
            // archieve task
            done_task_stack.push(task);
        } else if(!done_task_stack.empty()) {
            // pop undo task
            done_task_stack.pop();
        }
    }

    // Build TLAS
    build_tlas(next_index, true);

    // Set current index as updated
    index_updated[next_index] = true;

    {
        // TODO: mutex here
        // Switch to next index
        current_index = next_index;

        // Set updating to false
        status = AS_MANAGER_STATUS::IDLE;
    }


    // delete temp proc blas
    for(auto blas : temp_proc_blas)
        if(blas != daxa::BlasId{})
            device.destroy_blas(blas);

    temp_proc_blas.clear();
}


void ACCEL_STRUCT_MNGR::process_voxel_modifications() {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return;
    }

    // Bring bitmask to host
    auto instance_bitmask_staging_buffer = device.create_buffer({
        .size = max_instance_bitmask_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
        .name = ("instance_bitmask_staging_buffer"),
    });
    defer { device.destroy_buffer(instance_bitmask_staging_buffer); };
    
    upload_aabb_primitives(brush_instance_bitmask_buffer, instance_bitmask_staging_buffer, 0, 0, max_instance_bitmask_size, false);

    // Bring voxel modifications to host
    auto primitive_bitmask_staging_buffer = device.create_buffer({
        .size = max_primitive_bitmask_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
        .name = ("voxel_modifications_staging_buffer"),
    });
    defer { device.destroy_buffer(primitive_bitmask_staging_buffer); };

    upload_aabb_primitives(brush_primitive_bitmask_buffer, primitive_bitmask_staging_buffer, 0, 0, max_primitive_bitmask_size);
    

    auto *instance_bitmask_buffer_ptr = device.get_host_address_as<uint32_t>(instance_bitmask_staging_buffer).value();

    auto *voxel_modifications_buffer_ptr = device.get_host_address_as<uint32_t>(primitive_bitmask_staging_buffer).value();

    uint32_t changes_so_far = 0;

    // Check instances first
    for(uint32_t i = 0; i < (current_instance_count[current_index] << 5); i++) {
        if(instance_bitmask_buffer_ptr[i] != 0U) {
            for(uint32_t j = 0; j < 32; j++) {
                if(instance_bitmask_buffer_ptr[i] & (1 << j)) {
                    uint32_t instance_index = i * 32 + j;
                    // Process instance
                    INSTANCE instance = instances[instance_index];
                    for(uint32_t k = 0; k < instance.primitive_count; k++) {
                        if(voxel_modifications_buffer_ptr[instance.first_primitive_index + k] != 0U) {
                            for(uint32_t l = 0; l < 32; l++) {
                                if(voxel_modifications_buffer_ptr[instance.first_primitive_index + k] & (1 << l)) {
                                    changes_so_far++;
                                    uint32_t instance_primitive = k * 32 + l;
                                    // Process primitive
#if DEBUG == 1                    
                                    std::cout << "Instance: " << instance_index << " Primitive: " << instance_primitive << std::endl;
#endif // DEBUG                                    
                                    {
                                        
                                        auto task_queue = TASK{
                                            .type = TASK::TYPE::REBUILD_BLAS_FROM_CPU,
                                            .blas_rebuild_from_cpu = {.instance_index = i, .del_primitive_index = instance_primitive},
                                        };
                                        task_queue_add(task_queue);
                                    }

                                    // Check if all changes were processed
                                    if(changes_so_far >= brush_counters->primitive_count) {
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

    // Reset bitmasks
    std::memset(instance_bitmask_buffer_ptr, 0, max_instance_bitmask_size);

    std::memset(voxel_modifications_buffer_ptr, 0, max_primitive_bitmask_size);

    upload_aabb_primitives(instance_bitmask_staging_buffer, brush_instance_bitmask_buffer, 0, 0, max_instance_bitmask_size, false);

    upload_aabb_primitives(primitive_bitmask_staging_buffer, brush_primitive_bitmask_buffer, 0, 0, max_primitive_bitmask_size);
}



void ACCEL_STRUCT_MNGR::check_voxel_modifications() {
    if (!device.is_valid() || !initialized)
    {
        std::cerr << "device.is_valid()" << std::endl;
        return;
    }


    if(brush_counters->instance_count > 0) {
#if DEBUG == 1                    
        std::cout << "  Modifications instances: " << brush_counters->instance_count << " primitives: " << brush_counters->primitive_count << std::endl;
#endif // DEBUG                             

        // Bring bitmask to host
        process_voxel_modifications();


        // zero out brush counters
        brush_counters->instance_count = 0;
        brush_counters->primitive_count = 0;
    }
}