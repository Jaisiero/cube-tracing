
#pragma once
#include "defines.h"

CL_NAMESPACE_BEGIN

#if MPM_ON == 1

struct MPM_MNGR
{
public:
    struct MPMBufferInfo {
        daxa::BufferId status_buffer;
        daxa::BufferId world_buffer;
    };
    
    struct WriteMPMP2G : MPMTaskHead::Task
    {
        AttachmentViews views = {};
        std::shared_ptr<daxa::ComputePipeline> pipeline = {};
        BufferId indirect_buffer = {};
        usize offset = 0;
        daxa::BufferClearInfo clear_info = {};
        void callback(daxa::TaskInterface ti)
        {
            ti.recorder.clear_buffer(clear_info);
            ti.recorder.set_pipeline(*pipeline);
            ti.recorder.push_constant_vptr({
                ti.attachment_shader_blob.data(), 
                ti.attachment_shader_blob.size()});
            ti.recorder.dispatch_indirect({.indirect_buffer = indirect_buffer, .offset = offset});
        }
    };

    struct WriteMPMgrid : MPMTaskHead::Task
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

    struct WriteMPMG2P : MPMTaskHead::Task
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
    

    auto record_MPM_task_graph(
        daxa::BufferId& MPM_indirect_buffer,
        daxa::BufferId status_buffer,
        daxa::BufferId world_buffer) -> daxa::TaskGraph
    {
        using namespace MPMTaskHead;
        auto task_graph = daxa::TaskGraph({
            .device = device,
            .record_debug_information = true,
            .name = "MPM_task_graph",
        });

        if(MPM_indirect_buffer == daxa::BufferId{})
        {
            MPM_indirect_buffer = device.create_buffer({
                .size = sizeof(u32) * 6,
                .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                .name = "MPM indirect buffer",
            });

            auto *indirect_buffer_ptr = device.get_host_address_as<u32>(MPM_indirect_buffer).value();

            indirect_buffer_ptr[0] = 1;
            indirect_buffer_ptr[1] = 1;
            indirect_buffer_ptr[2] = 1;
            indirect_buffer_ptr[3] = (GRID_DIM + MPM_GRID_COMPUTE_X -1) / MPM_GRID_COMPUTE_X;
            indirect_buffer_ptr[4] = (GRID_DIM + MPM_GRID_COMPUTE_Y -1) / MPM_GRID_COMPUTE_Y;
            indirect_buffer_ptr[5] = (GRID_DIM + MPM_GRID_COMPUTE_Z -1) / MPM_GRID_COMPUTE_Z;
        }

        auto task_status_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{status_buffer},
                .latest_access = daxa::AccessConsts::COMPUTE_SHADER_READ_WRITE,
            },
            .name = "status_buffer", // This name MUST be identical to the name used in the shader.
        });

        auto task_world_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{world_buffer},
                .latest_access = daxa::AccessConsts::COMPUTE_SHADER_READ_WRITE,
            },
            .name = "world_buffer", // This name MUST be identical to the name used in the shader.
        });

        task_graph.use_persistent_buffer(task_status_buffer);
        task_graph.use_persistent_buffer(task_world_buffer);

        task_graph.add_task(WriteMPMP2G{
            .views = std::array{
                daxa::attachment_view(AT.status_buffer, task_status_buffer),
                daxa::attachment_view(AT.world_buffer, task_world_buffer),
            },
            .pipeline = _MPM_P2G_comp,
            .indirect_buffer = MPM_indirect_buffer,
            .offset = 0,
            .clear_info = {_MPM_grid_buffer, 0, _grid_buffer_size, 0},
        });
        task_graph.add_task(WriteMPMgrid{
            .views = std::array{
                daxa::attachment_view(AT.status_buffer, task_status_buffer),
                daxa::attachment_view(AT.world_buffer, task_world_buffer),
            },
            .pipeline = _MPM_grid_comp,
            .indirect_buffer = MPM_indirect_buffer,
            .offset = sizeof(u32) * 3,
        });
        task_graph.add_task(WriteMPMG2P{
            .views = std::array{
                daxa::attachment_view(AT.status_buffer, task_status_buffer),
                daxa::attachment_view(AT.world_buffer, task_world_buffer),
            },
            .pipeline = _MPM_G2P_comp,
            .indirect_buffer = MPM_indirect_buffer,
            .offset = 0,
        });
        task_graph.submit({});
        task_graph.complete({});

        return task_graph;
    }

    MPM_MNGR(daxa::Device& device, daxa::PipelineManager& pipeline_manager, daxa::ShaderCompileOptions slang_shader_compile_options,
    MPMBufferInfo MPM_buffer_info)
        : device(device), pipeline_manager(pipeline_manager), _MPM_buffer_info(MPM_buffer_info)
    {
        auto MPM_comp_pipeline_info = slang_shader_compile_options;
        MPM_comp_pipeline_info.entry_point = "entry_MPM_P2G";

        _MPM_config_buffer = device.create_buffer({
            .size = sizeof(MPM_CONFIG),
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
            .name = "MPM config buffer",
        });

        _grid_buffer_size = sizeof(MPM_CELL) * GRID_DIM * GRID_DIM * GRID_DIM;

        _MPM_grid_buffer = device.create_buffer({
            .size = _grid_buffer_size,
            .name = "MPM grid buffer",
        });

        _MPM_config_ptr = device.get_host_address_as<MPM_CONFIG>(_MPM_config_buffer).value();

        _MPM_config_ptr->p_count = 1;
        
        _MPM_config_ptr->grid_dim.x = GRID_DIM;
        _MPM_config_ptr->grid_dim.y = GRID_DIM;
        _MPM_config_ptr->grid_dim.z = GRID_DIM;

        _MPM_config_ptr->dt = 0.0f;
        _MPM_config_ptr->dx = 1.0f / static_cast<f32>(GRID_DIM * VOXEL_EXTENT);
        _MPM_config_ptr->inv_dx = 1.0f / _MPM_config_ptr->dx;
        _MPM_config_ptr->gravity = -9.81f;

        _MPM_P2G_comp =
            pipeline_manager.add_compute_pipeline(
                                daxa::ComputePipelineCompileInfo{
                                    .shader_info = daxa::ShaderCompileInfo{
                                        .source = daxa::ShaderFile{"MPM.slang"},
                                        .compile_options = MPM_comp_pipeline_info,
                                    },
                                    .push_constant_size = sizeof(mpm_push_constant),
                                    .name = "MPM P2G shader",
                                })
                .value();

        auto MPM_grid_comp_pipeline_info = slang_shader_compile_options;
        MPM_grid_comp_pipeline_info.entry_point = "entry_MPM_grid";

        _MPM_grid_comp =
            pipeline_manager.add_compute_pipeline(
                                daxa::ComputePipelineCompileInfo{
                                    .shader_info = daxa::ShaderCompileInfo{
                                        .source = daxa::ShaderFile{"MPM.slang"},
                                        .compile_options = MPM_grid_comp_pipeline_info,
                                    },
                                    .push_constant_size = sizeof(mpm_push_constant),
                                    .name = "MPM GRID shader",
                                })
                .value();

        auto MPM_G2P_comp_pipeline_info = slang_shader_compile_options;
        MPM_G2P_comp_pipeline_info.entry_point = "entry_MPM_G2P";

        _MPM_G2P_comp =
            pipeline_manager.add_compute_pipeline(
                                daxa::ComputePipelineCompileInfo{
                                    .shader_info = daxa::ShaderCompileInfo{
                                        .source = daxa::ShaderFile{"MPM.slang"},
                                        .compile_options = MPM_G2P_comp_pipeline_info,
                                    },
                                    .push_constant_size = sizeof(mpm_push_constant),
                                    .name = "MPM GRID shader",
                                })
                .value();

        MPM_task_graph = record_MPM_task_graph(
            _MPM_indirect_buffer,
            MPM_buffer_info.status_buffer,
            MPM_buffer_info.world_buffer);
    }

    MPM_MNGR(const MPM_MNGR&) = delete;
    MPM_MNGR& operator=(const MPM_MNGR&) = delete;
    MPM_MNGR(MPM_MNGR&&) = default;

    ~MPM_MNGR()
    {
        if(_MPM_indirect_buffer != daxa::BufferId{})
            device.destroy_buffer(_MPM_indirect_buffer);

        if(_MPM_config_buffer != daxa::BufferId{})
            device.destroy_buffer(_MPM_config_buffer);

        if(_MPM_grid_buffer != daxa::BufferId{})
            device.destroy_buffer(_MPM_grid_buffer);
    }

    bool execute_mpm(daxa_u32 num_particles, daxa_f32 dt, bool sync = false)
    {
        auto *indirect_buffer_ptr = device.get_host_address_as<u32>(_MPM_indirect_buffer).value();

        indirect_buffer_ptr[0] = (num_particles + MPM_P2G_COMPUTE_X - 1) / MPM_P2G_COMPUTE_X;

        if (true)
        {
            _MPM_config_ptr->dt = dt;
            _MPM_config_ptr->p_count = num_particles;

            // TODO: add more MPMes here
            MPM_task_graph.execute({});
#if TRACE == 1
            std::cout << MPM_task_graph.get_debug_string() << std::endl;
#endif // TRACE
        }
        if (sync)
            device.wait_idle();

        return true;
    }

    daxa::BufferId get_MPM_config_buffer() const
    {
        return _MPM_config_buffer;
    }

    daxa::BufferId get_MPM_grid_buffer() const
    {
        return _MPM_grid_buffer;
    }
    

private:
    // MPM buffer
    MPM_CONFIG* _MPM_config_ptr = nullptr;
    daxa::BufferId _MPM_indirect_buffer = {};
    daxa::BufferId _MPM_config_buffer = {};
    usize _grid_buffer_size = 0;
    daxa::BufferId _MPM_grid_buffer = {};
    std::shared_ptr<daxa::ComputePipeline> _MPM_P2G_comp = {};
    std::shared_ptr<daxa::ComputePipeline> _MPM_grid_comp = {};
    std::shared_ptr<daxa::ComputePipeline> _MPM_G2P_comp = {};
    MPMBufferInfo _MPM_buffer_info = {};

    daxa::Device& device;
    daxa::PipelineManager& pipeline_manager;

    daxa::TaskGraph MPM_task_graph = {};
};

#endif // MPM_ON

CL_NAMESPACE_END