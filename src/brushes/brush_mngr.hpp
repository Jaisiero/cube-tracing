
#pragma once
#include "defines.h"

CL_NAMESPACE_BEGIN

struct BRUSH_MNGR
{
public:
    struct BrushBufferInfo {
        daxa::BufferId status_buffer;
        daxa::BufferId world_buffer;
        daxa::BufferId restir_buffer;
    };
    
    struct WriteSquaredBrush : BrushTaskHead::Task
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
    

    auto record_squared_brush_task_graph(
        daxa::BufferId& squared_brush_indirect_buffer,
        daxa::BufferId status_buffer,
        daxa::BufferId world_buffer,
        daxa::BufferId restir_buffer) -> daxa::TaskGraph
    {
        using namespace BrushTaskHead;
        auto task_graph = daxa::TaskGraph({
            .device = device,
            .record_debug_information = true,
            .name = "brush_task_graph",
        });

        if(squared_brush_indirect_buffer == daxa::BufferId{})
        {
            squared_brush_indirect_buffer = device.create_buffer({
                .size = sizeof(u32) * 3,
                .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                .name = "brush indirect buffer",
            });

            auto *indirect_buffer_ptr = device.get_host_address_as<u32>(squared_brush_indirect_buffer).value();

            indirect_buffer_ptr[0] = 1;
            indirect_buffer_ptr[1] = 1;
            indirect_buffer_ptr[2] = 1;
        }

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

        auto task_restir_buffer = daxa::TaskBuffer({
            .initial_buffers = {
                .buffers = std::array{restir_buffer},
                .latest_access = daxa::AccessConsts::COMPUTE_SHADER_READ_WRITE,
            },
            .name = "restir_buffer", // This name MUST be identical to the name used in the shader.
        });

        task_graph.use_persistent_buffer(task_status_buffer);
        task_graph.use_persistent_buffer(task_world_buffer);
        task_graph.use_persistent_buffer(task_restir_buffer);

        task_graph.add_task(WriteSquaredBrush{
            .views = std::array{
                daxa::attachment_view(AT.status_buffer, task_status_buffer),
                daxa::attachment_view(AT.world_buffer, task_world_buffer),
                daxa::attachment_view(AT.restir_buffer, task_restir_buffer),
            },
            .pipeline = squared_brush_comp,
            .indirect_buffer = squared_brush_indirect_buffer,
            .offset = 0,
        });
        task_graph.submit({});
        task_graph.complete({});

        return task_graph;
    }

    BRUSH_MNGR(daxa::Device& device, daxa::PipelineManager& pipeline_manager, daxa::ShaderCompileOptions slang_shader_compile_options,
    BrushBufferInfo brush_buffer_info)
        : device(device), pipeline_manager(pipeline_manager), _brush_buffer_info(brush_buffer_info)
    {
        auto brush_comp_pipeline_info = slang_shader_compile_options;
        brush_comp_pipeline_info.entry_point = "entry_brush";

        _brush_config_buffer = device.create_buffer({
            .size = sizeof(BRUSH_CONFIG),
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
            .name = "brush config buffer",
        });

        _brush_config_ptr = device.get_host_address_as<BRUSH_CONFIG>(_brush_config_buffer).value();

        _brush_config_ptr->brush_type = BRUSH_TYPE_SQUARE;
        _brush_config_ptr->brush_size.x = VOXEL_EXTENT * 5.0f;
        _brush_config_ptr->brush_size.y = 0.0f;
        _brush_config_ptr->brush_size.z = 0.0f;

        _brush_config_ptr->brush_pixel_size = daxa_u32vec3{50, 0, 0};

        squared_brush_comp =
            pipeline_manager.add_compute_pipeline(
                                daxa::ComputePipelineCompileInfo{
                                    .shader_info = daxa::ShaderCompileInfo{
                                        .source = daxa::ShaderFile{"squared_brush.slang"},
                                        .compile_options = brush_comp_pipeline_info,
                                    },
                                    .push_constant_size = sizeof(changes_push_constant),
                                    .name = "brush shader",
                                })
                .value();

        squared_brush_task_graph = record_squared_brush_task_graph(
            _squared_brush_indirect_buffer,
            brush_buffer_info.status_buffer,
            brush_buffer_info.world_buffer,
            brush_buffer_info.restir_buffer);
    }

    BRUSH_MNGR(const BRUSH_MNGR&) = delete;
    BRUSH_MNGR& operator=(const BRUSH_MNGR&) = delete;
    BRUSH_MNGR(BRUSH_MNGR&&) = default;

    ~BRUSH_MNGR()
    {
        if(_squared_brush_indirect_buffer != daxa::BufferId{})
            device.destroy_buffer(_squared_brush_indirect_buffer);

        if(_brush_config_buffer != daxa::BufferId{})
            device.destroy_buffer(_brush_config_buffer);
    }

    bool execute_brush(daxa_u32vec2 res, bool sync = true)
    {
        auto *indirect_buffer_ptr = device.get_host_address_as<u32>(_squared_brush_indirect_buffer).value();

        indirect_buffer_ptr[0] = (res.x + BRUSH_COMPUTE_X - 1) / BRUSH_COMPUTE_X;
        indirect_buffer_ptr[1] = (res.y + BRUSH_COMPUTE_Y - 1) / BRUSH_COMPUTE_Y;

        if (_brush_config_ptr->brush_type == BRUSH_TYPE_SQUARE)
        {
            // TODO: add more brushes here
            squared_brush_task_graph.execute({});
#if TRACE == 1
            std::cout << brush_task_graph.get_debug_string() << std::endl;
#endif // TRACE
        }
        if (sync)
            device.wait_idle();

        return true;
    }

    daxa::BufferId get_brush_config_buffer() const
    {
        return _brush_config_buffer;
    }
    

private:
    // brush buffer
    BRUSH_CONFIG* _brush_config_ptr = nullptr;
    daxa::BufferId _squared_brush_indirect_buffer = {};
    daxa::BufferId _brush_config_buffer = {};
    std::shared_ptr<daxa::ComputePipeline> squared_brush_comp = {};
    BrushBufferInfo _brush_buffer_info = {};

    daxa::Device& device;
    daxa::PipelineManager& pipeline_manager;

    daxa::TaskGraph squared_brush_task_graph = {};
};

CL_NAMESPACE_END