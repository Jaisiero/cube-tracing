#include "ACCEL_STRUCT_MNGR.hpp"

bool ACCEL_STRUCT_MNGR::create() {
    if(device.is_valid()) {
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

        initialized = true;

        return true;
    }

    return false;
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

        initialized = false;
    }

    return !initialized;
}

bool ACCEL_STRUCT_MNGR::build_new_blas(uint32_t frame_index, daxa::BufferId aabb_buffer[DOUBLE_BUFFERING], INSTANCE instances[], bool synchronize)
{
    if (!device.is_valid() || !initialized)
    {
        std::cout << "device.is_valid()" << std::endl;
        return false;
    }

    // Blas buffer offset to zero
    proc_blas_buffer_offset = 0;

    if (frame_index >= DOUBLE_BUFFERING)
    {
        std::cout << "frame_index >= tlas.size()" << std::endl;
        return false;
    }

    // this->proc_blas.reserve(current_instance_count[frame_index]);

    // reserve blas build infos
    blas_build_infos.clear();
    blas_build_infos.reserve(current_instance_count[frame_index]);

    // TODO: As much geometry as instances for now
    aabb_geometries.clear();
    aabb_geometries.resize(current_instance_count[frame_index]);

    uint32_t current_instance_index = 0;

    // build procedural blas
    for (uint32_t i = 0; i < current_instance_count[frame_index]; i++)
    {
        aabb_geometries.at(i).push_back(daxa::BlasAabbGeometryInfo{
            .data = device.get_device_address(aabb_buffer[frame_index]).value() + (instances[i].first_primitive_index * sizeof(AABB)),
            .stride = sizeof(AABB),
            .count = instances[i].primitive_count,
            // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
            .flags = 0x1, // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
        });

        // Crear un daxa::Span a partir del vector
        daxa::Span<const daxa::BlasAabbGeometryInfo> geometry_span(aabb_geometries.at(i).data(), aabb_geometries.at(i).size());

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
            std::cout << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
            abort();
        }
        blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
        proc_blas_scratch_buffer_offset += scratch_alignment_size;

        uint32_t build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

        if ((proc_blas_buffer_offset + build_aligment_size) > proc_blas_buffer_size)
        {
            // TODO: Try to resize buffer
            std::cout << "proc_blas_buffer_offset > proc_blas_buffer_size" << std::endl;
            abort();
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
    if (current_instance_index != current_instance_count[frame_index])
    {
        std::cout << "current_instance_index != current_instance_count" << std::endl;
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
    if (synchronize)
    {
        device.wait_idle();
    }
    /// NOTE:
    /// No need to wait idle here.
    /// Daxa will defer all the destructions of the buffers until the submitted as build commands are complete.

    return true;
}

bool ACCEL_STRUCT_MNGR::build_tlas(uint32_t frame_index, INSTANCE instances[], bool synchronize)
{
    if (!device.is_valid() || !initialized)
    {
        std::cout << "device.is_valid()" << std::endl;
        return false;
    }

    if (frame_index >= DOUBLE_BUFFERING)
    {
        std::cout << "frame_index >= tlas.size()" << std::endl;
        return false;
    }

    if (tlas[frame_index] != daxa::TlasId{})
        device.destroy_tlas(tlas[frame_index]);

    std::vector<daxa_BlasInstanceData> blas_instance_array = {};
    blas_instance_array.reserve(current_instance_count[frame_index]);

    // build procedural blas
    for (uint32_t i = 0; i < current_instance_count[frame_index]; i++)
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
        .size = sizeof(daxa_BlasInstanceData) * current_instance_count[frame_index],
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
            .count = current_instance_count[frame_index],
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
    this->tlas[frame_index] = device.create_tlas({
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
    tlas_build_info.dst_tlas = this->tlas[frame_index];
    tlas_build_info.scratch_data = device.get_device_address(tlas_scratch_buffer).value();
    blas_instances[0].data = device.get_device_address(blas_instances_buffer).value();

    // Copy instances to buffer
    uint32_t instance_buffer_size = static_cast<uint32_t>(current_instance_count[frame_index] * sizeof(INSTANCE));
    if (instance_buffer_size > max_instance_buffer_size)
    {
        std::cout << "instance_buffer_size > max_instance_buffer_size" << std::endl;
        abort();
    }

    auto instance_staging_buffer = device.create_buffer({
        .size = instance_buffer_size,
        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
        .name = ("instance_staging_buffer"),
    });
    defer { device.destroy_buffer(instance_staging_buffer); };

    auto *instance_buffer_ptr = device.get_host_address_as<INSTANCE>(instance_staging_buffer).value();
    std::memcpy(instance_buffer_ptr,
                instances,
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
            .dst_buffer = instance_buffer[frame_index],
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