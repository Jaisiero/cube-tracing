#include "ACCEL_STRUCT_MNGR.hpp"


void worker_thread_fn(std::stop_token stoken, ACCEL_STRUCT_MNGR* as_manager)
{
    while(!stoken.stop_requested())
    {
        // Wait for task queue to wake up
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->task_queue_cv.wait(lock, [&] { return as_manager->is_updating() || stoken.stop_requested(); });
        }
        std::cout << "Worker thread woke up" << std::endl;

        // Check if stop is requested
        if(stoken.stop_requested()) {
            break;
        }

        // Process task queue
        if(!as_manager->is_switching()) {
            as_manager->process_task_queue();
            std::cout << "Processing task queue" << std::endl;
        } else {
            as_manager->process_switching_task_queue();
            std::cout << "Processing switching task queue" << std::endl;
        }

        // set update done
        {
            std::unique_lock lock(as_manager->task_queue_mutex);
            as_manager->set_updating(false);
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

bool ACCEL_STRUCT_MNGR::create(uint32_t max_instance_count, uint32_t max_primitive_count) {
    if(device.is_valid() && !initialized) {
        proc_blas_scratch_buffer_size = max_instance_count * 1024ULL * 2ULL; // TODO: is this a good estimation?
        proc_blas_buffer_size = max_instance_count * 1024ULL * 2ULL;         // TODO: is this a good estimation?
        max_instance_buffer_size = sizeof(INSTANCE) * max_instance_count;
        max_aabb_buffer_size = sizeof(AABB) * max_primitive_count;
        max_aabb_host_buffer_size = sizeof(AABB) * max_primitive_count * 0.1;
        max_primitive_buffer_size = sizeof(PRIMITIVE) * max_primitive_count;

        instances = std::make_unique<INSTANCE[]>(max_instance_count);
        primitives = std::make_unique<PRIMITIVE[]>(max_primitive_count);

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

void ACCEL_STRUCT_MNGR::upload_primitives(daxa::BufferId src_primitive_buffer, daxa::BufferId dst_primitive_buffer, size_t src_primitive_buffer_offset, size_t dst_primitive_buffer_offset, size_t primitive_copy_size)
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


void ACCEL_STRUCT_MNGR::upload_aabb_primitives(daxa::BufferId src_abb_buffer, daxa::BufferId dst_aabb_buffer, size_t src_aabb_buffer_offset, size_t dst_aabb_buffer_offset, size_t aabb_copy_size) {
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
    device.wait_idle();
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

    // Blas buffer offset to zero
    proc_blas_buffer_offset = 0;

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
    // TODO: rebuild blas here
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

using TASK = ACCEL_STRUCT_MNGR::TASK;

void ACCEL_STRUCT_MNGR::process_task_queue() {

    if (!device.is_valid() || !initialized)
    {
        std::cout << "device.is_valid()" << std::endl;
        return;
    }

    if(items_to_process == 0) {
        // Set switching to false
        updating = false;
        return;
    }

    uint32_t next_index = (current_index + 1) % DOUBLE_BUFFERING;

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
        case TASK::TYPE::REBUILD_BLAS:
            TASK::BLAS_REBUILD rebuild_task = task.blas_rebuild;
            // uint32_t primitive_index = rebuild_task.del_primitive_index;
            // TODO: delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
            // TODO: update instance buffer substraction of primitive count
            // TODO: update remapping primitive index
            rebuild_blas(next_index, rebuild_task.instance_index);
            break;
        case TASK::TYPE::UPDATE_BLAS:
            TASK::BLAS_UPDATE update_task = task.blas_update;
            update_blas(next_index, update_task.instance_index);
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
        switching = true;
    }
    
}


void ACCEL_STRUCT_MNGR::process_switching_task_queue() {
    if (!device.is_valid() || !initialized)
    {
        std::cout << "device.is_valid()" << std::endl;
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
        case TASK::TYPE::REBUILD_BLAS:
            TASK::BLAS_REBUILD rebuild_task = task.blas_rebuild;
            // uint32_t primitive_index = rebuild_task.del_primitive_index;
            // TODO: delete primitive from buffer by copying the last primitive to the deleted primitive (aabb & primitive buffer)
            // TODO: update instance buffer substraction of primitive count
            // TODO: update remapping primitive index
            // rebuild_blas(next_index, rebuild_task.instance_index);
            break;
        case TASK::TYPE::UPDATE_BLAS:
            TASK::BLAS_UPDATE update_task = task.blas_update;
            // update_blas(next_index, update_task.instance_index);
            break;
        default:
            break;
        }

        // archieve task
        done_task_queue.push(task);
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
        updating = false;

        // Set switching to false
        switching = false;
    }
}