#include <iostream>
#include <algorithm>

#include <daxa/daxa.hpp>
#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>

#include <window.hpp>
#include <shared.hpp>

#include "shaders/shared.inl"
#include "random.hpp"

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

namespace tests
{
    void ray_querry_triangle()
    {
        struct App : AppWindow<App>
        {
            const f32 AXIS_DISPLACEMENT = HALF_EXTENT * VOXEL_COUNT_BY_AXIS; //(2^4)
            const u32 INSTANCE_X_AXIS_COUNT = 1; // 2^2 (mirrored on both sides of the x axis)
            const u32 INSTANCE_Z_AXIS_COUNT = 1; // 2^2 (mirrored on both sides of the z axis)
            // const u32 INSTANCE_COUNT = INSTANCE_X_AXIS_COUNT * INSTANCE_Z_AXIS_COUNT;
            const u32 MATERIAL_COUNT = 1000;
            const f32 SPEED = 0.1f;

            glm::vec3 camera_pos = {0, 0, 2.5};
            glm::vec3 camera_center = {0, 0, 0};
            glm::vec3 camera_up = {0, 1, 0};

           Status status = {};


            daxa::Instance daxa_ctx = {};
            daxa::Device device = {};
            daxa::Swapchain swapchain = {};
            daxa::PipelineManager pipeline_manager = {};
            std::shared_ptr<daxa::ComputePipeline> comp_pipeline = {};
            daxa::TlasId tlas = {};
            std::vector<daxa::BlasId> proc_blas = {};

            // BUFFERS
            daxa::BufferId cam_buffer = {};
            u32 cam_buffer_size = sizeof(Camera);

            daxa::BufferId status_buffer = {};
            u32 status_buffer_size = sizeof(Status);

            daxa::BufferId instance_buffer = {};
            u32 max_instance_buffer_size = sizeof(INSTANCE) * MAX_INSTANCES;

            daxa::BufferId primitive_buffer = {};
            u32 max_primitive_buffer_size = sizeof(PRIMITIVE) * MAX_PRIMITIVES;

            daxa::BufferId material_buffer = {};
            u32 max_material_buffer_size = sizeof(MATERIAL) * MAX_MATERIALS;

            daxa::BufferId status_output_buffer = {};
            u32 max_status_output_buffer_size = sizeof(STATUS_OUTPUT);

            // DEBUGGING
            // daxa::BufferId hit_distance_buffer = {};
            // u32 max_hit_distance_buffer_size = sizeof(HIT_DISTANCE) * WIDTH_RES * HEIGHT_RES;
            // std::vector<HIT_DISTANCE> hit_distances = {};
            // DEBUGGING
            
            // CPU DATA
            u32 current_instance_count = 0;
            std::array<INSTANCE, MAX_INSTANCES> instances = {};

            u32 current_primitive_count = 0;
            u32 max_current_primitive_count = 0;
            std::vector<PRIMITIVE> primitives = {};

            u32 current_material_count = 0;
            std::vector<MATERIAL> materials = {};

            std::vector<daxa_f32mat4x4> transforms = {};

            App() : AppWindow<App>("ray query test") {}

            ~App()
            {
                if (device.is_valid())
                {
                    device.destroy_tlas(tlas);
                    for(auto blas : proc_blas)
                        device.destroy_blas(blas);
                    device.destroy_buffer(cam_buffer);
                    device.destroy_buffer(instance_buffer);
                    device.destroy_buffer(primitive_buffer);
                    device.destroy_buffer(material_buffer);
                    device.destroy_buffer(status_buffer);
                    device.destroy_buffer(status_output_buffer);
                    // DEBUGGING
                    // device.destroy_buffer(hit_distance_buffer);
                }
            }

            daxa_f32mat4x4 glm_mat4_to_daxa_f32mat4x4(glm::mat4 const & mat)
            {
                return daxa_f32mat4x4{
                    {mat[0][0], mat[0][1], mat[0][2], mat[0][3]},
                    {mat[1][0], mat[1][1], mat[1][2], mat[1][3]},
                    {mat[2][0], mat[2][1], mat[2][2], mat[2][3]},
                    {mat[3][0], mat[3][1], mat[3][2], mat[3][3]},
                };
            }

            daxa_rowmaj_f32mat3x4 daxa_f32mat4x4_to_daxa_rowmaj_f32mat3x4(daxa_f32mat4x4 const & mat)
            {
                return daxa_rowmaj_f32mat3x4{
                    {mat.x.x, mat.x.y, mat.x.z, mat.x.w},
                    {mat.y.x, mat.y.y, mat.y.z, mat.y.w},
                    {mat.z.x, mat.z.y, mat.z.z, mat.z.w}
                };
            }

            // u32 get_primitive_count_by_level(u32 level_index) {
            //     switch (level_index)
            //     {
            //     case 1:
            //         return min_max_array.size();
            //         break;
            //     default:
            //         return 0;
            //         break;
            //     }
            // }

            // constexpr daxa_f32mat3x2 * get_min_max_by_level(u32 level_index) {
            //     switch (level_index)
            //     {
            //     case 1:
            //         return min_max_array.data();
            //         break;
            //     default:
            //         return nullptr;
            //         break;
            //     }
            // }

            // Generate min max by coord (x, y, z) where x, y, z are 0 to VOXEL_COUNT_BY_AXIS-1 where VOXEL_COUNT_BY_AXIS / 2 is the center at (0, 0, 0)
            constexpr daxa_f32mat3x2 generate_min_max_by_coord(u32 x, u32 y, u32 z) const {
                return daxa_f32mat3x2{
                    {
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + (x * HALF_EXTENT) + AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + (y * HALF_EXTENT) + AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + (z * HALF_EXTENT) + AVOID_VOXEL_COLLAIDE
                    },
                    {
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + ((x + 1) * HALF_EXTENT) - AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + ((y + 1) * HALF_EXTENT) - AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * HALF_EXTENT) + ((z + 1) * HALF_EXTENT) - AVOID_VOXEL_COLLAIDE
                    }
                };
            }

            void change_random_material_primitives() {
                if(primitives.size() == 0) {
                    return;
                }

                // Change every primitive material
                for(u32 i = 0; i < primitives.size(); i++) {
                    primitives[i].material_index = random_uint(0, MATERIAL_COUNT - 1);
                }

                
                // Copy primitives to buffer
                u32 primitive_buffer_size = std::min(max_primitive_buffer_size, static_cast<u32>(current_primitive_count * sizeof(PRIMITIVE)));

                // push primitives to buffer
                auto primitive_staging_buffer = device.create_buffer({
                    .size = primitive_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "primitive staging buffer",
                });
                defer { device.destroy_buffer(primitive_staging_buffer); };

                auto * primitive_buffer_ptr = device.get_host_address_as<PRIMITIVE>(primitive_staging_buffer).value();
                std::memcpy(primitive_buffer_ptr, 
                    primitives.data(),
                    primitive_buffer_size);

                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});

                    recorder.pipeline_barrier({
                        .src_access = daxa::AccessConsts::HOST_WRITE,
                        .dst_access = daxa::AccessConsts::TRANSFER_READ,
                    });
                    
                    recorder.copy_buffer_to_buffer({
                        .src_buffer = primitive_staging_buffer,
                        .dst_buffer = primitive_buffer,
                        .size = max_primitive_buffer_size,
                    });
                    
                    recorder.pipeline_barrier({
                        .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                        .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
                    });

                    return recorder.complete_current_commands();
                }();
                device.submit_commands({.command_lists = std::array{exec_cmds}});

                
            }

            daxa_Bool8 build_tlas(u32 instance_count) {
                daxa_Bool8 some_level_changed = false;

                if(instance_count == 0) {
                    std::cout << "instance_count == 0" << std::endl;
                    return false;
                }

                // daxa_u32 primitive_count = 0;
                // for(u32 i = 0; i < instance_count; i++) {
                //     primitive_count += get_primitive_count_by_level(1);
                // }

                // if(primitive_count == 0) {
                //     std::cout << "primitive count is 0" << std::endl;
                //     return false;
                // }

                this->max_current_primitive_count = CHUNK_VOXEL_COUNT * instance_count / 2;

                if(this->max_current_primitive_count > MAX_PRIMITIVES) {
                    std::cout << "max_current_primitive_count > MAX_PRIMITIVES" << std::endl;
                    return false;
                }

                this->current_instance_count = 0;

                this->primitives.clear();
                this->primitives.reserve(this->max_current_primitive_count);
                
                if(this->tlas != daxa::TlasId{})
                    device.destroy_tlas(tlas);
                for(auto blas : this->proc_blas)
                    device.destroy_blas(blas);

                this->proc_blas.clear();
                this->proc_blas.reserve(instance_count);

                u32 aabb_buffer_size = this->max_current_primitive_count * sizeof(daxa_f32mat3x2);

                // https://registry.khronos.org/vulkan/specs/1.3-extensions/html/vkspec.html#VUID-VkAccelerationStructureBuildGeometryInfoKHR-type-03792
                // GeometryType of each element of pGeometries must be the same
                auto aabb_buffer = device.create_buffer({
                    .size = aabb_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "aabb buffer",
                });
                defer { device.destroy_buffer(aabb_buffer); };

                current_primitive_count = 0;
                    
                std::vector<daxa_f32mat3x2> min_max;
                min_max.reserve(CHUNK_VOXEL_COUNT);

                for(u32 i = 0; i < instance_count; i++) {
                    min_max.clear();
                    
                    for(u32 z = 0; z < VOXEL_COUNT_BY_AXIS; z++) {
                        for(u32 y = 0; y < VOXEL_COUNT_BY_AXIS; y++) {
                            for(u32 x = 0; x < VOXEL_COUNT_BY_AXIS; x++) {
                                
                                if(random_float(0.0, 1.0) > 0.99) {
                                    min_max.push_back(generate_min_max_by_coord(x, y, z));
                                }
                            }
                        }
                    }

                    u32 primitive_count_current_instance = min_max.size();

                    instances[i].transform = {
                        transforms[i],
                    },
                    instances[i].primitive_count = primitive_count_current_instance;
                    instances[i].first_primitive_index = current_primitive_count;

                    if(instances[i].primitive_count == 0) {
                        std::cout << "primitive count is 0 for instance " << i << std::endl;
                        return false;
                    }

                    std::memcpy((device.get_host_address_as<daxa_f32mat3x2>(aabb_buffer).value() + current_primitive_count),
                        min_max.data(), 
                        instances[i].primitive_count * sizeof(daxa_f32mat3x2));
                    current_primitive_count += instances[i].primitive_count;

                    
                    
                    // push primitives
                    for(u32 j = 0; j < instances[i].primitive_count; j++) {
                        
                        primitives.push_back(PRIMITIVE{
                            .center = daxa_f32vec3(
                                (min_max[j].y.x + min_max[j].x.x) / 2.0f,
                                (min_max[j].y.y + min_max[j].x.y) / 2.0f,
                                (min_max[j].y.z + min_max[j].x.z) / 2.0f
                            ),
                            .material_index = random_uint(0, MATERIAL_COUNT - 1),
                        });
                    }

                }

                
                // COMMENT FROM HERE
                std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
                blas_build_infos.reserve(instance_count);

                std::vector<daxa_BlasInstanceData> blas_instance_array = {};
                blas_instance_array.reserve(instance_count);

                // TODO: As much geometry as instances for now
                std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};
                aabb_geometries.resize(instance_count);


                u32 current_instance_index = 0;

                for(u32 i = 0; i < instance_count; i++) {

                    aabb_geometries.at(i).push_back(daxa::BlasAabbGeometryInfo{
                        .data = device.get_device_address(aabb_buffer).value() + (instances[i].first_primitive_index * sizeof(daxa_f32mat3x2)),
                        .stride = sizeof(daxa_f32mat3x2),
                        .count = instances[i].primitive_count,
                        // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
                        .flags = 0x1 | 0x2,
                    });

                    /// Create Procedural Blas:
                    blas_build_infos.push_back(daxa::BlasBuildInfo{
                        .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_TRACE,       // Is also default
                        .dst_blas = {}, // Ignored in get_acceleration_structure_build_sizes.       // Is also default
                        .geometries = aabb_geometries.at(i),
                        .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
                    });

                    daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

                    auto proc_blas_scratch_buffer = device.create_buffer({
                        .size = proc_build_size_info.build_scratch_size,
                        .name = "proc blas build scratch buffer",
                    });
                    defer { device.destroy_buffer(proc_blas_scratch_buffer); };

                    this->proc_blas.push_back(device.create_blas({
                        .size = proc_build_size_info.acceleration_structure_size,
                        .name = "test procedural blas",
                    }));
                    blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = this->proc_blas.at(this->proc_blas.size() - 1);
                    blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = device.get_device_address(proc_blas_scratch_buffer).value();

                    blas_instance_array.push_back(daxa_BlasInstanceData{
                        .transform = 
                            daxa_f32mat4x4_to_daxa_rowmaj_f32mat3x4(instances[i].transform),
                        .instance_custom_index = i, // Is also default
                        .mask = 0xFF,
                        .instance_shader_binding_table_record_offset = {}, // Is also default
                        .flags = {},                                       // Is also default
                        .blas_device_address = device.get_device_address(this->proc_blas.at(this->proc_blas.size() - 1)).value(),
                    });

                    ++current_instance_index;
                }
                // COMMENT TO HERE


                if(current_instance_index != instance_count) {
                    std::cout << "current_instance_index != instance_count" << std::endl;
                    return false;
                }

                this->current_instance_count = instance_count;
                
                // current instance count in this scene is 2 right now
                /// create blas instances for tlas:
                auto blas_instances_buffer = device.create_buffer({
                    .size = sizeof(daxa_BlasInstanceData) * instance_count,
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
                        .count = current_instance_count,
                        .is_data_array_of_pointers = false, // Buffer contains flat array of instances, not an array of pointers to instances.
                        // .flags = daxa::GeometryFlagBits::OPAQUE,
                        .flags = 0x1,
                    }
                };
                auto tlas_build_info = daxa::TlasBuildInfo{
                    .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_TRACE,
                    .dst_tlas = {}, // Ignored in get_acceleration_structure_build_sizes.
                    .instances = blas_instances,
                    .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.
                };
                daxa::AccelerationStructureBuildSizesInfo tlas_build_sizes = device.get_tlas_build_sizes(tlas_build_info);
                /// Create Tlas:
                this->tlas = device.create_tlas({
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
                tlas_build_info.dst_tlas = tlas;
                tlas_build_info.scratch_data = device.get_device_address(tlas_scratch_buffer).value();
                blas_instances[0].data = device.get_device_address(blas_instances_buffer).value();
                /// Record build commands:
                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});
                    recorder.build_acceleration_structures({
                        .blas_build_infos = blas_build_infos,
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
                /// NOTE:
                /// No need to wait idle here.
                /// Daxa will defer all the destructions of the buffers until the submitted as build commands are complete.

                return true;
            }

            void initialize()
            {
                daxa_ctx = daxa::create_instance({});
                device = daxa_ctx.create_device({
                    .selector = [](daxa::DeviceProperties const & prop) -> i32
                    {
                        auto value = daxa::default_device_score(prop);
                        return prop.ray_tracing_properties.has_value() ? value : -1;
                    },
                    .flags = daxa::DeviceFlagBits::RAY_TRACING,
                });
                std::cout << "Choosen Device: " << device.properties().device_name << std::endl;
                swapchain = device.create_swapchain({
                    .native_window = get_native_handle(),
                    .native_window_platform = get_native_platform(),
                    .surface_format_selector = [](daxa::Format format) -> i32
                    {
                        if (format == daxa::Format::B8G8R8A8_UNORM)
                        {
                            return 1000;
                        }
                        return 1;
                    },
                    .image_usage = daxa::ImageUsageFlagBits::SHADER_STORAGE,
                });

                cam_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = cam_buffer_size,
                    .name = ("cam_buffer"),
                });

                status_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = status_buffer_size,
                    .name = ("status_buffer"),
                });

                instance_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_instance_buffer_size,
                    .name = ("instance_buffer"),
                });

                primitive_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_primitive_buffer_size,
                    .name = ("primitive_buffer"),
                });

                material_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_material_buffer_size,
                    .name = ("material_buffer"),
                });

                status_output_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_status_output_buffer_size,
                    .name = ("status_output_buffer"),
                });

                // hit_distance_buffer = device.create_buffer(daxa::BufferInfo{
                //     .size = max_hit_distance_buffer_size,
                //     .name = ("hit_distance_buffer"),
                // });

                // DEBUGGING
                // hit_distances.resize(WIDTH_RES * HEIGHT_RES);
                
                // TODO: This could be load from a file
                {

                    f32 instance_count_x = (INSTANCE_X_AXIS_COUNT * 2);
                    f32 instance_count_z = (INSTANCE_Z_AXIS_COUNT * 2);

                    current_instance_count = instance_count_x * instance_count_z;

                    if(current_instance_count > MAX_INSTANCES) {
                        std::cout << "current_instance_count > MAX_INSTANCES" << std::endl;
                        abort();
                    }

                    if(current_instance_count == 0) {
                        std::cout << "current_instance_count == 0" << std::endl;
                        abort();
                    }
                    
                    transforms.reserve(current_instance_count);

                    // Centered around 0, 0, 0 positioning instances like a mirror
                    f32 x_axis_initial_position = ((INSTANCE_X_AXIS_COUNT) * AXIS_DISPLACEMENT / 2);
                    f32 z_axis_initial_position = ((INSTANCE_Z_AXIS_COUNT) * AXIS_DISPLACEMENT / 2);


                    for(i32 x = -INSTANCE_X_AXIS_COUNT; x < (i32)INSTANCE_X_AXIS_COUNT; x++) {
                        for(i32 z= -INSTANCE_Z_AXIS_COUNT; z < (i32)INSTANCE_Z_AXIS_COUNT; z++) {
                            transforms.push_back(daxa_f32mat4x4{
                                {1, 0, 0, (x * (AXIS_DISPLACEMENT))},
                                {0, 1, 0, 0},
                                {0, 0, 1, (z * (AXIS_DISPLACEMENT))},
                                {0, 0, 0, 1},
                            });
                        }
                    }

                    if(transforms.size() < current_instance_count) {
                        std::cout << "transforms.size() != current_instance_count" << std::endl;
                        abort();
                    }

                    current_material_count = MATERIAL_COUNT;

                    materials.reserve(current_material_count);

                    for(u32 i = 0; i < current_material_count; i++) {
                        materials.push_back(MATERIAL{
                            .type = random_uint(0, 2),
                            .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .diffuse =  {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .transmittance = {0.0f, 0.0f, 0.0f},
                            .emission = {0.0f, 0.0f, 0.0f},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            .dissolve = 1.0f,
                            .illum = random_int(2, 4),
                            .textureId = -1,
                        });
                    }

                    proc_blas.reserve(current_instance_count);
                }



                // call build tlas
                if(!build_tlas(current_instance_count)) {
                    std::cout << "Failed to build tlas" << std::endl;
                    abort();
                }
                

                pipeline_manager = daxa::PipelineManager{daxa::PipelineManagerInfo{
                    .device = device,
                    .shader_compile_options = {
                        .root_paths = {
                            DAXA_SHADER_INCLUDE_DIR,
                            "src/shaders",
                        },
                    },
                }};
                auto const compute_pipe_info = daxa::ComputePipelineCompileInfo{
                    .shader_info = daxa::ShaderCompileInfo{
                        .source = daxa::ShaderFile{"shaders.glsl"},
                    },
                    .push_constant_size = sizeof(PushConstant),
                    .name = "ray query comp shader",
                };
                comp_pipeline = pipeline_manager.add_compute_pipeline(compute_pipe_info).value();
            }

            auto update() -> bool
            {
                auto reload_result = pipeline_manager.reload_all();

                if (auto * reload_err = daxa::get_if<daxa::PipelineReloadError>(&reload_result))
                    std::cout << reload_err->message << std::endl;
                else if (daxa::get_if<daxa::PipelineReloadSuccess>(&reload_result))
                    std::cout << "reload success" << std::endl;
                using namespace std::literals;
                std::this_thread::sleep_for(1ms);
                glfwPollEvents();
                if (glfwWindowShouldClose(glfw_window_ptr) != 0)
                {
                    return true;
                }

                if (!minimized)
                {
                    draw();
                    download_gpu_info();
                    // call build tlas
                    // if(!build_tlas(INSTANCE_COUNT)) {
                    //     std::cout << "Failed to build tlas" << std::endl;
                    //     abort();
                    // }
                }
                else
                {
                    using namespace std::literals;
                    std::this_thread::sleep_for(1ms);
                }

                return false;
            }

            void draw()
            {
                auto swapchain_image = swapchain.acquire_next_image();
                if (swapchain_image.is_empty())
                {
                    return;
                }
                auto recorder = device.create_command_recorder({
                    .name = ("recorder (clearcolor)"),
                });
                
                daxa::u32 width = device.info_image(swapchain_image).value().size.x;
                daxa::u32 height = device.info_image(swapchain_image).value().size.y;

                Camera camera = {
                    .inv_view = glm_mat4_to_daxa_f32mat4x4(glm::inverse(glm::lookAt(camera_pos, camera_center, camera_up))),
                    .inv_proj = glm_mat4_to_daxa_f32mat4x4(glm::inverse(glm::perspective(glm::radians(45.0f), (width/(f32)height), 0.001f, 1000.0f)))
                };

                // NOTE: Vulkan has inverted y axis in NDC
                camera.inv_proj.y.y *= -1;
                
                auto cam_staging_buffer = device.create_buffer({
                    .size = cam_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("cam_staging_buffer"),
                });
                defer { device.destroy_buffer(cam_staging_buffer); };

                auto * buffer_ptr = device.get_host_address_as<daxa_f32mat4x4>(cam_staging_buffer).value();
                std::memcpy(buffer_ptr, 
                    &camera,
                    cam_buffer_size);

                auto status_staging_buffer = device.create_buffer({
                    .size = status_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("status_staging_buffer"),
                });
                defer { device.destroy_buffer(status_staging_buffer); };

                auto * status_buffer_ptr = device.get_host_address_as<Status>(status_staging_buffer).value();
                std::memcpy(status_buffer_ptr, 
                    &status,
                    status_buffer_size);

                // Update/restore status
                status.frame_number++;

                // Copy instances to buffer
                u32 instance_buffer_size = std::min(max_instance_buffer_size, static_cast<u32>(current_instance_count * sizeof(INSTANCE)));


                auto instance_staging_buffer = device.create_buffer({
                    .size = instance_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("instance_staging_buffer"),
                });
                defer { device.destroy_buffer(instance_staging_buffer); };

                auto * instance_buffer_ptr = device.get_host_address_as<INSTANCE>(instance_staging_buffer).value();
                std::memcpy(instance_buffer_ptr, 
                    &instances,
                    instance_buffer_size);

                // Copy primitives to buffer
                u32 primitive_buffer_size = std::min(max_primitive_buffer_size, static_cast<u32>(current_primitive_count * sizeof(PRIMITIVE)));


                auto primitive_staging_buffer = device.create_buffer({
                    .size = primitive_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("primitive_staging_buffer"),
                });
                defer { device.destroy_buffer(primitive_staging_buffer); };

                auto * primitive_buffer_ptr = device.get_host_address_as<PRIMITIVE>(primitive_staging_buffer).value();
                std::memcpy(primitive_buffer_ptr, 
                    primitives.data(),
                    primitive_buffer_size);

                daxa_u32 material_buffer_size = std::min(max_material_buffer_size, static_cast<u32>(current_material_count * sizeof(MATERIAL)));

                auto material_staging_buffer = device.create_buffer({
                    .size = material_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("material_staging_buffer"),
                });
                defer { device.destroy_buffer(material_staging_buffer); };

                auto * material_buffer_ptr = device.get_host_address_as<PRIMITIVE>(material_staging_buffer).value();
                std::memcpy(material_buffer_ptr, 
                    materials.data(),
                    material_buffer_size);

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::HOST_WRITE,
                    .dst_access = daxa::AccessConsts::TRANSFER_READ,
                });

                recorder.copy_buffer_to_buffer({
                    .src_buffer = cam_staging_buffer,
                    .dst_buffer = cam_buffer,
                    .size = cam_buffer_size,
                });

                recorder.copy_buffer_to_buffer(
                    {
                        .src_buffer = status_staging_buffer,
                        .dst_buffer = status_buffer,
                        .size = status_buffer_size,
                    }
                );

                recorder.copy_buffer_to_buffer({
                    .src_buffer = instance_staging_buffer,
                    .dst_buffer = instance_buffer,
                    .size = instance_buffer_size,
                });

                recorder.copy_buffer_to_buffer({
                    .src_buffer = primitive_staging_buffer,
                    .dst_buffer = primitive_buffer,
                    .size = primitive_buffer_size,
                });

                recorder.copy_buffer_to_buffer({
                    .src_buffer = material_staging_buffer,
                    .dst_buffer = material_buffer,
                    .size = material_buffer_size,
                });

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                    .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
                });

                recorder.pipeline_barrier_image_transition({
                    .dst_access = daxa::AccessConsts::COMPUTE_SHADER_WRITE,
                    .src_layout = daxa::ImageLayout::UNDEFINED,
                    .dst_layout = daxa::ImageLayout::GENERAL,
                    .image_id = swapchain_image,
                });

                recorder.set_pipeline(*comp_pipeline);
                recorder.push_constant(PushConstant{
                    .size = {width, height},
                    .tlas = tlas,
                    .swapchain = swapchain_image.default_view(),
                    .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                    .status_buffer = this->device.get_device_address(status_buffer).value(),
                    .instance_buffer = this->device.get_device_address(instance_buffer).value(),
                    .primitives_buffer = this->device.get_device_address(primitive_buffer).value(),
                    .materials_buffer = this->device.get_device_address(material_buffer).value(),
                    .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                    // .hit_distance_buffer = this->device.get_device_address(hit_distance_buffer).value(),
                    // .instance_level_buffer = this->device.get_device_address(instance_level_buffer).value(),
                    // .instance_distance_buffer = this->device.get_device_address(instance_distance_buffer).value(),
                    // .aabb_buffer = this->device.get_device_address(gpu_aabb_buffer).value(),
                });
                daxa::u32 block_count_x = (width + 8 - 1) / 8;
                daxa::u32 block_count_y = (height + 8 - 1) / 8;
                recorder.dispatch({block_count_x, block_count_y, 1});

                recorder.pipeline_barrier_image_transition({
                    .src_access = daxa::AccessConsts::COMPUTE_SHADER_WRITE,
                    .src_layout = daxa::ImageLayout::GENERAL,
                    .dst_layout = daxa::ImageLayout::PRESENT_SRC,
                    .image_id = swapchain_image,
                });

                auto executalbe_commands = recorder.complete_current_commands();
                /// NOTE:
                /// Must destroy the command recorder here as we call collect_garbage later in this scope!
                recorder.~CommandRecorder();

                device.submit_commands({
                    .command_lists = std::array{executalbe_commands},
                    .wait_binary_semaphores = std::array{swapchain.current_acquire_semaphore()},
                    .signal_binary_semaphores = std::array{swapchain.current_present_semaphore()},
                    .signal_timeline_semaphores = std::array{std::pair{swapchain.gpu_timeline_semaphore(), swapchain.current_cpu_timeline_value()}},
                });

                device.present_frame({
                    .wait_binary_semaphores = std::array{swapchain.current_present_semaphore()},
                    .swapchain = swapchain,
                });

                device.collect_garbage();
            }

            void download_gpu_info() {

                if(!status.is_active) {
                    return;
                }

                // if(current_instance_count == 0) {
                //     return;
                // }

                // if(current_instance_count != instance_levels.size()) {
                //     instance_levels.resize(current_instance_count);
                // }

                // if(aabb.size() < current_primitive_count) {
                //     aabb.resize(current_primitive_count);
                // }

                // u32 instance_level_buffer_size = std::min(max_instance_level_buffer_size, static_cast<u32>(current_instance_count * sizeof(INSTANCE_LEVEL)));
                // // Some Device to Host copy here
                // auto instance_level_staging_buffer = device.create_buffer({
                //     .size = instance_level_buffer_size,
                //     .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                //     .name = ("instance_level_staging_buffer"),
                // });
                // defer { device.destroy_buffer(instance_level_staging_buffer); };

                // daxa_u32 width = device.info_image(swapchain.current_image()).value().size.x;
                // daxa_u32 height = device.info_image(swapchain.current_image()).value().size.y;

                // daxa_u32 width = swapchain.get_surface_extent().x;
                // daxa_u32 height = swapchain.get_surface_extent().y;

                // u32 hit_distance_buffer_size = std::min(max_hit_distance_buffer_size, static_cast<u32>(width * height * sizeof(HIT_DISTANCE)));
                // // Some Device to Host copy here
                // auto hit_distance_staging_buffer = device.create_buffer({
                //     .size = hit_distance_buffer_size,
                //     .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                //     .name = ("hit_distance_staging_buffer"),
                // });
                // defer { device.destroy_buffer(hit_distance_staging_buffer); };

                // Some Device to Host copy here
                auto status_output_staging_buffer = device.create_buffer({
                    .size = max_status_output_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("status_output_staging_buffer"),
                });
                defer { device.destroy_buffer(status_output_staging_buffer); };

                /// Record build commands:
                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});
                    recorder.pipeline_barrier({
                        .src_access = daxa::AccessConsts::HOST_WRITE,
                        .dst_access = daxa::AccessConsts::TRANSFER_READ,
                    });

                    // recorder.copy_buffer_to_buffer({
                    //     .src_buffer = instance_level_buffer,
                    //     .dst_buffer = instance_level_staging_buffer,
                    //     .size = instance_level_buffer_size,
                    // });
                    
                    // recorder.copy_buffer_to_buffer({
                    //     .src_buffer = hit_distance_buffer,
                    //     .dst_buffer = hit_distance_staging_buffer,
                    //     .size = hit_distance_buffer_size,
                    // });

                    // recorder.copy_buffer_to_buffer({
                    //     .src_buffer = instance_distance_buffer,
                    //     .dst_buffer = instance_distance_staging_buffer,
                    //     .size = instance_distance_buffer_size,
                    // });

                    // recorder.copy_buffer_to_buffer({
                    //     .src_buffer = gpu_aabb_buffer,
                    //     .dst_buffer = aabb_staging_buffer,
                    //     .size = aabb_buffer_size,
                    // });
                    
                    recorder.copy_buffer_to_buffer({
                        .src_buffer = status_output_buffer,
                        .dst_buffer = status_output_staging_buffer,
                        .size = max_status_output_buffer_size,
                    });

                    recorder.pipeline_barrier({
                        .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                        .dst_access = daxa::AccessConsts::HOST_READ,
                    });
                    return recorder.complete_current_commands();
                }();

                // WAIT FOR COMMANDS TO FINISH
                {
                    device.submit_commands({
                        .command_lists = std::array{exec_cmds},
                        // .signal_binary_semaphores = std::array{swapchain.current_present_semaphore()},
                        // .signal_timeline_semaphores = std::array{std::pair{swapchain.gpu_timeline_semaphore(), swapchain.current_cpu_timeline_value()}},
                    });

                    device.wait_idle();
                    // daxa::TimelineSemaphore gpu_timeline = device.create_timeline_semaphore({
                    //     .name = "timeline semaphpore",
                    // });

                    // usize cpu_timeline = 0;

                    // device.submit_commands({
                    //     .command_lists = std::array{exec_cmds},
                    //     .signal_timeline_semaphores = std::array{std::pair{gpu_timeline, cpu_timeline}}
                    // });

                    // gpu_timeline.wait_for_value(cpu_timeline);
                }

                STATUS_OUTPUT status_output;


                auto * status_buffer_ptr = device.get_host_address_as<Status>(status_output_staging_buffer).value();
                std::memcpy(&status_output,
                    status_buffer_ptr,
                    max_status_output_buffer_size);


                std::cout << "status pixel [" << status.pixel.x << ", " << status.pixel.y << "]" << std::endl;
                std::cout << "status out instance index " << status_output.instance_id << " primitive index " << status_output.primitive_id 
                    << " distance " << status_output.hit_distance << " position [" << status_output.hit_position.x << ", " << status_output.hit_position.y << ", " << status_output.hit_position.z << "]" << std::endl;
                
                
                status.is_active = false;
                status.pixel = {0, 0};

                // /// NOTE: this must wait for the commands to finish
                // auto * hit_distance_buffer_ptr = device.get_host_address_as<HIT_DISTANCE>(hit_distance_staging_buffer).value();
                // std::memcpy(hit_distances.data(), 
                //     hit_distance_buffer_ptr,
                //     hit_distance_buffer_size);
                // for(u32 i = 0; i < hit_distances.size(); i++) {
                //     if(hit_distances[i].distance > 0.0f) {
                //         // translate i to x, y, print distance, instance index, primitive index
                //         std::cout << " coord ["<< i % width << ", " << i / width << "]" << " hit distance " << hit_distances[i].distance 
                //             << " position [" << hit_distances[i].position.x << ", " << hit_distances[i].position.y << ", " << hit_distances[i].position.z << "]"
                //             << " normal [" << hit_distances[i].normal.x << ", " << hit_distances[i].normal.y << ", " << hit_distances[i].normal.z << "]"
                //             << " instance index " << hit_distances[i].instance_index << " primitive index " << hit_distances[i].primitive_index << std::endl;
                //         if(hit_distances[i].instance_index < current_instance_count) {
                //             daxa_u32 first_primitive_index = instances[hit_distances[i].instance_index].first_primitive_index;
                //             daxa_f32mat4x4 transform = instances[hit_distances[i].instance_index].transform;
                //             daxa_f32vec3 translation = daxa_f32vec3{transform.x.w, transform.y.w, transform.z.w};
                //             std::cout << " instance translation [" << translation.x << ", " << translation.y << ", " << translation.z << "]" << std::endl;
                //             if(first_primitive_index + hit_distances[i].primitive_index < current_primitive_count) {
                //                 daxa_f32vec3 center = primitives[first_primitive_index + hit_distances[i].primitive_index].center;
                //                 std::cout << "  primitive center [" << translation.x + center.x << ", " <<  translation.y + center.y << ", " << translation.z + center.z << "]" << std::endl;
                //                 daxa_f32mat3x2 min_max = daxa_f32mat3x2({center.x - HALF_EXTENT, center.y - HALF_EXTENT, center.z - HALF_EXTENT}, {center.x + HALF_EXTENT, center.y + HALF_EXTENT, center.z + HALF_EXTENT});
                //                 // std::cout << "primitive min [" << min_max.x.x << ", " << min_max.x.y << ", " << min_max.x.z << "]" << std::endl;
                //                 // std::cout << "primitive max [" << min_max.y.x << ", " << min_max.y.y << ", " << min_max.y.z << "]" << std::endl;
                //                 // print instance translation + primitive min + max
                //                 std::cout << "  primitive min [" << translation.x + min_max.x.x << ", " << translation.y + min_max.x.y << ", " << translation.z + min_max.x.z << "]" << std::endl;
                //                 std::cout << "  primitive max [" << translation.x + min_max.y.x << ", " << translation.y + min_max.y.y << ", " << translation.z + min_max.y.z << "]" << std::endl;
                //             }
                //         }
                //     }
                // }

                // /// NOTE: this must wait for the commands to finish
                // auto * instance_level_buffer_ptr = device.get_host_address_as<INSTANCE_LEVEL>(instance_level_staging_buffer).value();
                // std::memcpy(instance_levels.data(), 
                //     instance_level_buffer_ptr,
                //     instance_level_buffer_size);

                // auto * instance_distance_buffer_ptr = device.get_host_address_as<INSTANCE_DISTANCE>(instance_distance_staging_buffer).value();
                // std::memcpy(instance_distances.data(), 
                //     instance_distance_buffer_ptr,
                //     instance_distance_buffer_size);
                    
                // auto * aabb_buffer_ptr = device.get_host_address_as<INSTANCE_DISTANCE>(aabb_staging_buffer).value();
                // std::memcpy(aabb.data(), 
                //     aabb_buffer_ptr,
                //     aabb_buffer_size);


                // print out the levels & distances
                // for(u32 i = 0; i < current_instance_count; i++) {
                //     if(instance_levels[i].level_index != instances[i].level_index) {
                //         std::cout << "instance " << i << " level changed from " << instances[i].level_index << " to " << instance_levels[i].level_index << std::endl;
                //     }
                //     if(instance_distances[i].distance >= 0.0f) {
                //         std::cout << "instance " << i << " distance " << instance_distances[i].distance << std::endl;
                //     }
                // }

                // for(u32 i = 0; i < current_primitive_count; i++) {
                //     std::cout << "primitive " << i << " minimum " << aabb[i].aabb.minimum.x << " " << aabb[i].aabb.minimum.y << " " << aabb[i].aabb.minimum.z 
                //         << " maximum " << aabb[i].aabb.maximum.x << " " << aabb[i].aabb.maximum.y << " " << aabb[i].aabb.maximum.z << std::endl;
                // }

            }

            void on_mouse_move(f32 /*unused*/, f32 /*unused*/) {}
            void on_mouse_button(i32 button, i32 action) {
                // Click right button store the current mouse position
                if (action == GLFW_PRESS && button == GLFW_MOUSE_BUTTON_1)
                {
                    double mouse_x, mouse_y;
                    glfwGetCursorPos(glfw_window_ptr, &mouse_x, &mouse_y);

                    status.pixel = {static_cast<daxa_u32>(mouse_x), static_cast<daxa_u32>(mouse_y)};
                    status.is_active = true;

                    // std::cout << "mouse_x: " << status.pixel.x << " mouse_y: " << status.pixel.y << std::endl;
                }

            }
            void on_key(i32 key, i32 action) {
                
                switch(key) {
                    case GLFW_KEY_W:
                    case GLFW_KEY_UP:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.z -= SPEED;
                            camera_center.z -= SPEED;
                        }
                        break;
                    case GLFW_KEY_S:
                    case GLFW_KEY_DOWN:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.z += SPEED;
                            camera_center.z += SPEED;
                        }
                        break;
                    case GLFW_KEY_A:
                    case GLFW_KEY_LEFT:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.x -= SPEED;
                            camera_center.x -= SPEED;
                        }
                        break;
                    case GLFW_KEY_D:
                    case GLFW_KEY_RIGHT:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.x += SPEED;
                            camera_center.x += SPEED;
                        }
                        break;
                    case GLFW_KEY_X:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.y -= SPEED;
                            camera_center.y -= SPEED;
                        }
                        break;
                    case GLFW_KEY_SPACE:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_pos.y += SPEED;
                            camera_center.y += SPEED;
                        }
                        break;
                    case GLFW_KEY_PAGE_UP:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_center.y -= SPEED;
                        }
                        break;
                    case GLFW_KEY_PAGE_DOWN:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_center.y += SPEED;
                        }
                        break;
                    case GLFW_KEY_Q:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_center.x -= SPEED;
                        }
                        break;
                    case GLFW_KEY_E:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            camera_center.x += SPEED;
                        }
                        break;
                    case GLFW_KEY_R:
                        if(action == GLFW_PRESS) {
                            camera_pos = {0, 0, 2.5};
                            camera_center = {0, 0, 0};
                            camera_up = {0, 1, 0};
                        }
                        break;
                    case GLFW_KEY_ESCAPE:
                        if(action == GLFW_PRESS) {
                            glfwSetWindowShouldClose(glfw_window_ptr, GLFW_TRUE);
                        }
                        break;
                    case GLFW_KEY_M:
                        if(action == GLFW_PRESS) {
                            change_random_material_primitives();
                        }
                        break;
                    default:
                        break;
                };

            }

            void on_resize(u32 sx, u32 sy)
            {
                minimized = sx == 0 || sy == 0;
                if (!minimized)
                {
                    swapchain.resize();
                    size_x = swapchain.get_surface_extent().x;
                    size_y = swapchain.get_surface_extent().y;
                    draw();
                }
            }
        };

        App app;
        try
        {
            app.initialize();
        }
        catch (std::runtime_error err)
        {
            std::cout << "Failed initialization: \"" << err.what() << "\"" << std::endl;
            return;
        }
        while (true)
        {
            if (app.update())
            {
                break;
            }
        }
    }
} // namespace tests

auto main() -> int
{
    tests::ray_querry_triangle();
    return 0;
}
