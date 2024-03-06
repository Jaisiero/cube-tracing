#include <algorithm>
#include <thread>

#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>

#include <window.hpp>
#include <shared.hpp>

#include <map_loader.hpp>

#include "defines.h"
#include "rng.h"
#include "camera.h"
#include "texture.hpp"


namespace tests
{
    void cubeland_app()
    {
        struct App : AppWindow<App>
        {
            const char *RED_BRICK_WALL_IMAGE = "red_brick_wall.jpg";
            const char *MODEL_PATH = "assets/models/";
            const char *MAP_NAME = "monu5.vox";

            Status status = {};
            camera camera = {};
            LIGHT_CONFIG light_config = {};

            daxa_u32 invocation_reorder_mode;

            daxa::Instance daxa_ctx = {};
            daxa::Device device = {};
            daxa::Swapchain swapchain = {};
            daxa::PipelineManager pipeline_manager = {};
            std::shared_ptr<daxa::RayTracingPipeline> rt_pipeline = {};
            std::shared_ptr<daxa::ComputePipeline> compute_motion_vectors_pipeline = {};
            daxa::TlasId tlas = {};
            std::vector<daxa::BlasId> proc_blas = {};
            daxa::BufferId proc_blas_scratch_buffer = {};
            daxa_u64 proc_blas_scratch_buffer_size = MAX_INSTANCES * 1024ULL * 2ULL; // TODO: is this a good estimation?
            daxa_u64 proc_blas_scratch_buffer_offset = 0;
            daxa_u32 acceleration_structure_scratch_offset_alignment = 0;
            daxa::BufferId proc_blas_buffer = {};
            daxa_u64 proc_blas_buffer_size = MAX_INSTANCES * 1024ULL * 2ULL; // TODO: is this a good estimation?
            daxa_u64 proc_blas_buffer_offset = 0;
            const daxa_u32 ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT = 256;

            // BUFFERS
            daxa::BufferId light_config_buffer = {};
            size_t light_config_buffer_size = sizeof(LIGHT_CONFIG);


            daxa::BufferId cam_buffer = {};
            size_t cam_buffer_size = sizeof(camera_view);
            size_t previous_matrices = sizeof(daxa_f32mat4x4) * 2;
            size_t cam_update_size = cam_buffer_size - previous_matrices;

            daxa::BufferId status_buffer = {};
            size_t status_buffer_size = sizeof(Status);

            daxa::BufferId world_buffer = {};
            size_t world_buffer_size = sizeof(WORLD);
            WORLD world = {};

            daxa::BufferId instance_buffer = {};
            size_t max_instance_buffer_size = sizeof(INSTANCE) * MAX_INSTANCES;

            daxa::BufferId primitive_buffer = {};
            size_t max_primitive_buffer_size = sizeof(PRIMITIVE) * MAX_PRIMITIVES;

            daxa::BufferId aabb_buffer = {};
            size_t max_aabb_buffer_size = sizeof(AABB) * MAX_PRIMITIVES;
            daxa::BufferId aabb_host_buffer = {};
            size_t max_aabb_host_buffer_size = sizeof(AABB) * MAX_PRIMITIVES * 0.1;
            daxa_u32 current_aabb_host_count = 0;
            size_t aabb_buffer_offset = 0;

            u32 current_texture_count = 0;
            std::vector<daxa::ImageId> images = {};
            std::vector<daxa::SamplerId> samplers = {};

            daxa::BufferId material_buffer = {};
            size_t max_material_buffer_size = sizeof(MATERIAL) * MAX_MATERIALS;

            daxa::BufferId light_buffer = {};
            size_t max_light_buffer_size = sizeof(LIGHT) * MAX_LIGHTS;

            // daxa::BufferId status_output_buffer = {};
            // size_t max_status_output_buffer_size = sizeof(STATUS_OUTPUT);

            daxa::BufferId restir_buffer = {};
            RESTIR restir = {};
            size_t restir_buffer_size = sizeof(RESTIR);

            daxa::BufferId previous_reservoir_buffer = {};
            daxa::BufferId intermediate_reservoir_buffer = {};
            daxa::BufferId reservoir_buffer = {};
            size_t max_reservoir_buffer_size = sizeof(RESERVOIR) * MAX_RESERVOIRS;

            daxa::BufferId velocity_buffer = {};
            size_t max_velocity_buffer_size = sizeof(VELOCITY) * MAX_RESERVOIRS;

            daxa::BufferId previous_direct_illum_buffer = {};
            daxa::BufferId direct_illum_buffer = {};
            size_t max_direct_illum_buffer_size = sizeof(DIRECT_ILLUMINATION_INFO) * MAX_RESERVOIRS;

            daxa::BufferId pixel_reconnection_data_buffer = {};
            size_t max_pixel_reconnection_data_buffer_size = sizeof(PIXEL_RECONNECTION_DATA) * MAX_RESERVOIRS;

            daxa::BufferId output_path_reservoir_buffer = {};
            daxa::BufferId temporal_path_reservoir_buffer = {};
            size_t max_output_path_reservoir_buffer_size = sizeof(PATH_RESERVOIR) * MAX_RESERVOIRS;

            daxa::BufferId indirect_color_buffer = {};
            size_t max_indirect_color_buffer_size = sizeof(daxa_f32vec3) * MAX_RESERVOIRS;

            // DEBUGGING
            // daxa::BufferId hit_distance_buffer = {};
            // size_t max_hit_distance_buffer_size = sizeof(HIT_DISTANCE) * WIDTH_RES * HEIGHT_RES;
            // std::vector<HIT_DISTANCE> hit_distances = {};
            // DEBUGGING

            // CPU DATA
            std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
            std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};

            u32 current_instance_count = 0;
            std::vector<INSTANCE> instances = {};

            u32 current_primitive_count = 0;
            u32 max_current_primitive_count = 0;
            std::vector<PRIMITIVE> primitives = {};

            u32 current_material_count = 0;
            std::vector<MATERIAL> materials = {};

            std::vector<LIGHT> lights = {};

            std::vector<daxa_f32mat4x4> transforms = {};

            MapLoader map_loader = {};


            App() : AppWindow<App>("Cubeland") {}

            ~App()
            {
                map_loader.destroy_gvox_context();
                device.wait_idle();
                device.collect_garbage();
                if (device.is_valid())
                {
                    device.destroy_tlas(tlas);
                    for(auto blas : proc_blas)
                        device.destroy_blas(blas);
                    device.destroy_buffer(light_config_buffer);
                    device.destroy_buffer(cam_buffer);
                    device.destroy_buffer(instance_buffer);
                    device.destroy_buffer(primitive_buffer);
                    device.destroy_buffer(aabb_buffer);
                    device.destroy_buffer(aabb_host_buffer);
                    device.destroy_buffer(material_buffer);
                    for(auto image : images)
                        device.destroy_image(image);
                    for(auto sampler : samplers)
                        device.destroy_sampler(sampler);
                    device.destroy_buffer(light_buffer);
                    device.destroy_buffer(status_buffer);
                    // device.destroy_buffer(status_output_buffer);
                    device.destroy_buffer(previous_reservoir_buffer);
                    device.destroy_buffer(intermediate_reservoir_buffer);
                    device.destroy_buffer(reservoir_buffer);
                    device.destroy_buffer(velocity_buffer);
                    device.destroy_buffer(previous_direct_illum_buffer);
                    device.destroy_buffer(direct_illum_buffer);
                    device.destroy_buffer(pixel_reconnection_data_buffer);
                    device.destroy_buffer(output_path_reservoir_buffer);
                    device.destroy_buffer(temporal_path_reservoir_buffer);
                    device.destroy_buffer(indirect_color_buffer);
                    device.destroy_buffer(restir_buffer);
                    device.destroy_buffer(world_buffer);
                    device.destroy_buffer(proc_blas_scratch_buffer);
                    device.destroy_buffer(proc_blas_buffer);
                    // DEBUGGING
                    // device.destroy_buffer(hit_distance_buffer);
                }
            }

            void change_random_material_primitives() {
                if(primitives.size() == 0) {
                    return;
                }

                // Change every primitive material
                for(u32 i = 0; i < primitives.size(); i++) {
                    primitives[i].material_index = random_uint(0, current_material_count - CONSTANT_MEDIUM_MATERIAL_COUNT - 1);
                    // primitives[i].material_index = random_uint(0, current_material_count - 1);
                }


                // Copy primitives to buffer
                u32 current_primitive_buffer_size = static_cast<u32>(current_primitive_count * sizeof(PRIMITIVE));
                if(current_primitive_buffer_size > max_primitive_buffer_size) {
                    std::cout << "current_primitive_buffer_size > max_primitive_buffer_size" << std::endl;
                    abort();
                }

                // push primitives to buffer
                auto primitive_staging_buffer = device.create_buffer({
                    .size = current_primitive_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "primitive staging buffer",
                });
                defer { device.destroy_buffer(primitive_staging_buffer); };

                auto * primitive_buffer_ptr = device.get_host_address_as<PRIMITIVE>(primitive_staging_buffer).value();
                std::memcpy(primitive_buffer_ptr,
                    primitives.data(),
                    current_primitive_buffer_size);

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

            daxa_f32vec3 interpolate_sun_light(float t, bool is_afternoon) {
                // Definir las posiciones clave para el medio día y el atardecer
                glm::vec3 middayPosition = glm::vec3(0.0, SUN_TOP_POSITION, 0.0);
                glm::vec3 sunsetPosition = glm::vec3(50.0, 0.0, 0.0);  // Modificar la posición del atardecer

                // Calcular las coordenadas elípticas basadas en el tiempo
                float angle = t * 2.0 * 3.14159; // Ángulo en radianes
                float ellipseRadiusX = 100.0;    // Radio en el eje X
                float ellipseRadiusY = 50.0;     // Radio en el eje Y

                float x = ellipseRadiusX * cos(angle);
                float y = ellipseRadiusY * sin(angle);

                // Interpolación elíptica desde mediodía hasta atardecer
                glm::vec3 interpolatedPosition;
                if (is_afternoon) {
                    // Atardecer: t=0.0 -> posición = sunsetPosition
                    // Mediodía: t=1.0 -> posición = middayPosition
                    interpolatedPosition = glm::mix(sunsetPosition, middayPosition, t);
                } else {
                    // Atardecer: t=1.0 -> posición = middayPosition
                    // Mediodía: t=0.0 -> posición = -sunsetPosition
                    interpolatedPosition = glm::mix(-sunsetPosition, middayPosition, t);
                }

                daxa_f32vec3 position = daxa_f32vec3(interpolatedPosition.x, interpolatedPosition.y, interpolatedPosition.z);

                // Ajustar la posición según la hora del día
                return position;
            }

            daxa_f32 interpolate_sun_intensity(float time, bool is_afternoon, float max_intensity, float min_intensity) {
                const daxa_f32 maxIntensityStartTime = 0.5;
                const daxa_f32 minIntensityEndTime = 0.5;

                float i = 0;

                if (time >= maxIntensityStartTime) {
                    i = glm::mix(0.0f, max_intensity, time);  // Adjust the range as needed
                } else {
                    i = 0;
                }

                return i;
            }


            void load_reservoirs() {

                const daxa_u32 reservoir_buffer_size = 
                    static_cast<u32>(std::max(std::max(std::max(std::max(sizeof(RESERVOIR), sizeof(DIRECT_ILLUMINATION_INFO)), sizeof(VELOCITY)), sizeof(PIXEL_RECONNECTION_DATA)), sizeof(PATH_RESERVOIR)) * MAX_RESERVOIRS);

                auto reservoir_staging_buffer = device.create_buffer({
                    .size = reservoir_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "reservoir staging buffer",
                });
                defer { device.destroy_buffer(reservoir_staging_buffer); };

                std::memset(device.get_host_address(reservoir_staging_buffer).value(),
                    0,
                    reservoir_buffer_size);

                const daxa_u32 reservoir_size = static_cast<u32>(sizeof(RESERVOIR) * MAX_RESERVOIRS);

                const daxa_u32 velocity_buffer_size = static_cast<u32>(sizeof(VELOCITY) * MAX_RESERVOIRS);

                const daxa_u32 direct_illum_buffer_size = static_cast<u32>(sizeof(DIRECT_ILLUMINATION_INFO) * MAX_RESERVOIRS);

                const daxa_u32 pixel_reconnection_data_buffer_size = static_cast<u32>(sizeof(PIXEL_RECONNECTION_DATA) * MAX_RESERVOIRS);

                const daxa_u32 path_reservoir_buffer_size = static_cast<u32>(sizeof(PATH_RESERVOIR) * MAX_RESERVOIRS);

                /// Record build commands:
                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});

                     recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = previous_reservoir_buffer,
                        .size = reservoir_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = intermediate_reservoir_buffer,
                        .size = reservoir_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = reservoir_buffer,
                        .size = reservoir_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = velocity_buffer,
                        .size = velocity_buffer_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = previous_direct_illum_buffer,
                        .size = direct_illum_buffer_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = pixel_reconnection_data_buffer,
                        .size = pixel_reconnection_data_buffer_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = output_path_reservoir_buffer,
                        .size = path_reservoir_buffer_size,
                    });

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = reservoir_staging_buffer,
                        .dst_buffer = temporal_path_reservoir_buffer,
                        .size = path_reservoir_buffer_size,
                    });

                    return recorder.complete_current_commands();
                }();
                device.submit_commands({.command_lists = std::array{exec_cmds}});
                device.wait_idle();
            }


            void create_point_lights() {
                // TODO: add more lights (random values?)
                status.is_afternoon = true;

                LIGHT light = {}; // 0: point light, 1: directional light
                light.position = daxa_f32vec3(0.0, SUN_TOP_POSITION, 0.0);
#if DYNAMIC_SUN_LIGHT == 1
                light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2);
#else
#if SUN_MIDDAY == 1
                light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY, SUN_MAX_INTENSITY, SUN_MAX_INTENSITY);
                status.time = 1.0;
                status.is_afternoon = true;
#else
                light.emissive = daxa_f32vec3(0.0, 0.0, 0.0);
                status.time = 0.0;
                status.is_afternoon = false;
#endif

#endif // DYNAMIC_SUN_LIGHT
                light.type = GEOMETRY_LIGHT_POINT;
                light.instance_info = OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES);
                lights.push_back(light);
                ++light_config.point_light_count;

                // LIGHT light2 = {};
                // light2.position = daxa_f32vec3( -AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.5f, 1.0, 0.0001);
                // light2.emissive = daxa_f32vec3(3.0, 3.0, 3.0);
                // light2.type = GEOMETRY_LIGHT_POINT;
                // lights.push_back(light2);
                // ++light_config.point_light_count;

                // LIGHT light3 = {};
                // light3.position = daxa_f32vec3(AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.0f, 1.0, 0.0001);
                // light3.emissive = daxa_f32vec3(4.0, 4.0, 4.0);
                // light3.type = GEOMETRY_LIGHT_POINT;
                // lights.push_back(light3);
                // ++light_config.point_light_count;
            }


            void create_environment_light() {
                LIGHT light = {};
                light.type = GEOMETRY_LIGHT_ENV_MAP;
                light.instance_info = OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES);
                light.position = daxa_f32vec3(0.0, 0.0, 0.0);
                light.emissive = daxa_f32vec3(5.0, 5.0, 5.0);
                light.size = 0.f;
                lights.push_back(light);
                ++light_config.env_map_count;
            }

            void load_lights() {
                
                light_config.light_count = light_config.point_light_count + light_config.cube_light_count + light_config.sphere_light_count + light_config.analytic_light_count + light_config.env_map_count;

                light_config.point_light_pdf =  light_config.point_light_count == 0 ? 0.f : 1.0f / (light_config.point_light_count / light_config.light_count);
                light_config.cube_light_pdf = light_config.cube_light_count == 0 ? 0.f : 1.0f / (light_config.cube_light_count / light_config.light_count);
                light_config.sphere_light_pdf = light_config.sphere_light_count == 0 ? 0.f : 1.0f / (light_config.sphere_light_count / light_config.light_count);
                light_config.analytic_light_pdf = light_config.analytic_light_count == 0 ? 0.f : 1.0f / (light_config.analytic_light_count / light_config.light_count);
                light_config.env_map_pdf = light_config.env_map_count == 0 ? 0.f : 1.0f / (light_config.env_map_count / light_config.light_count);

                if(light_config.light_count > MAX_LIGHTS) {
                    std::cout << "light_config.light_count > MAX_LIGHTS" << std::endl;
                    abort();
                }
                
                std::cout << "Num of lights: " << light_config.light_count << std::endl;
                std::cout << "  Num of point lights: " << light_config.point_light_count << std::endl;
                std::cout << "  Num of cube lights: " << light_config.cube_light_count << std::endl;
                std::cout << "  Num of environment map lights: " << light_config.env_map_count << std::endl;

                // Calculate light buffer size
                auto light_buffer_size = static_cast<u32>(sizeof(LIGHT) * light_config.light_count);
                if(light_buffer_size > max_light_buffer_size) {
                    std::cout << "light_buffer_size > max_light_buffer_size" << std::endl;
                    abort();
                }

                // get light buffer host mapped pointer
                auto * light_staging_buffer_ptr = device.get_host_address(light_buffer).value();

                // copy lights to buffer
                std::memcpy(light_staging_buffer_ptr,
                    lights.data(),
                    light_buffer_size);

                auto light_config_staging_buffer = device.create_buffer({
                    .size = light_config_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("light_config_staging_buffer"),
                });
                defer { device.destroy_buffer(light_config_staging_buffer); };

                auto * light_config_buffer_ptr = device.get_host_address_as<LIGHT_CONFIG>(light_config_staging_buffer).value();
                std::memcpy(light_config_buffer_ptr,
                    &light_config,
                    light_config_buffer_size);

                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});

                    recorder.copy_buffer_to_buffer({
                        .src_buffer = light_config_staging_buffer,
                        .dst_buffer = light_config_buffer,
                        .size = max_light_buffer_size,
                    });

                    return recorder.complete_current_commands();
                }();
                device.submit_commands({.command_lists = std::array{exec_cmds}});
                device.wait_idle();


                status.light_config_address = device.get_device_address(light_config_buffer).value();
            }

            void update_lights()
            {

                if (lights.size() == 0)
                {
                    return;
                }

                if (light_config.cube_light_count == 0)
                {
                    return;
                }

                if (light_config.cube_light_count > MAX_LIGHTS)
                {
                    std::cout << "current_light_count > MAX_LIGHTS" << std::endl;
                    abort();
                }

                // if(light_config.light_count != lights.size()) {
                //     std::cout << "current_light_count != lights.size()" << std::endl;
                //     abort();
                // }

                // Speed of time progression
                float timeSpeed = 0.001;

                // Increment or decrement time
                status.time += timeSpeed * (status.is_afternoon ? 1.0 : -1.0);

                // Check for boundaries and reverse direction if needed
                if (status.time < 0.0 || status.time > 1.0)
                {
                    status.is_afternoon = !status.is_afternoon;
                    status.time = std::clamp(status.time, 0.0f, 1.0f);
                }

                lights[0].position = interpolate_sun_light(status.time, status.is_afternoon);
                daxa_f32 intensity = interpolate_sun_intensity(status.time, status.is_afternoon, SUN_MAX_INTENSITY /*max_intensity*/, 0.0f /*min_intensity*/);
                lights[0].emissive = daxa_f32vec3(intensity, intensity, intensity);

                // Calculate light buffer size
                auto light_buffer_size = static_cast<u32>(sizeof(LIGHT) * light_config.cube_light_count);
                if (light_buffer_size > max_light_buffer_size)
                {
                    std::cout << "light_buffer_size > max_light_buffer_size" << std::endl;
                    abort();
                }

                // get light buffer host mapped pointer
                auto *light_staging_buffer_ptr = device.get_host_address(light_buffer).value();

                // copy lights to buffer
                std::memcpy(light_staging_buffer_ptr,
                    lights.data(),
                    light_buffer_size);

             }

            void upload_aabb_primitives(daxa::BufferId aabb_staging_buffer, daxa::BufferId aabb_buffer, size_t aabb_buffer_offset, size_t aabb_copy_size) {
                 /// Record build commands:
                auto exec_cmds = [&]()
                {
                    auto recorder = device.create_command_recorder({});

                     recorder.copy_buffer_to_buffer({
                        .src_buffer = aabb_staging_buffer,
                        .dst_buffer = aabb_buffer,
                        .dst_offset = aabb_buffer_offset,
                        .size = aabb_copy_size,
                    });

                    return recorder.complete_current_commands();
                }();
                device.submit_commands({.command_lists = std::array{exec_cmds}});
                device.wait_idle();
            }

            daxa_Bool8 load_blas_info(u32 instance_count) {
                daxa_Bool8 some_level_changed = false;

                if(instance_count == 0) {
                    std::cout << "instance_count == 0" << std::endl;
                    return false;
                }

                this->max_current_primitive_count = instance_count * CHUNK_VOXEL_COUNT;

                if(this->max_current_primitive_count > MAX_PRIMITIVES) {
                    std::cout << "max_current_primitive_count: " << max_current_primitive_count <<  " MAX_PRIMITIVES: " << MAX_PRIMITIVES << std::endl;
                    return false;
                }

                this->current_instance_count = 0;

                this->primitives.clear();
                this->primitives.reserve(this->max_current_primitive_count);


                current_primitive_count = 0;

                std::vector<daxa_f32mat2x3> min_max;
                min_max.reserve(CHUNK_VOXEL_COUNT);

                instances.reserve(instance_count);

                for(u32 i = 0; i < instance_count; i++) {
                    min_max.clear();

                    for(u32 z = 0; z < VOXEL_COUNT_BY_AXIS; z++) {
                        for(u32 y = 0; y < VOXEL_COUNT_BY_AXIS; y++) {
                            for(u32 x = 0; x < VOXEL_COUNT_BY_AXIS; x++) {
                                if(random_float(0.0, 1.0) > 0.75) {
                                    min_max.push_back(generate_min_max_by_coord(x, y, z, VOXEL_EXTENT));
                                }
                            }
                        }
                    }
                    // min_max.push_back(generate_min_max_by_coord(VOXEL_COUNT_BY_AXIS*0.5, VOXEL_COUNT_BY_AXIS*0.5, VOXEL_COUNT_BY_AXIS*0.5));
                    // min_max.push_back(generate_min_max_at_origin(VOXEL_EXTENT));

                    u32 primitive_count_current_instance = min_max.size();

                    daxa_f32mat4x4 transpose_mat = get_daxa_f32mat4x4_transpose(transforms[i]);

                    INSTANCE instance = {};

                    instance.transform = {
                        transpose_mat,
                    },
                    // TODO: get previous transform from previous build
                    instance.prev_transform = {
                        transpose_mat,
                    },
                    instance.primitive_count = primitive_count_current_instance;
                    instance.first_primitive_index = current_primitive_count;

                    if(instance.primitive_count == 0) {
                        std::cout << "primitive count is 0 for instance " << i << std::endl;
                        return false;
                    }

                    // push primitives
                    for(u32 j = 0; j < instance.primitive_count; j++) {

                        daxa_u32 material_index = (i < instance_count - CLOUD_INSTANCE_COUNT_X) ? random_uint(0, current_material_count - CONSTANT_MEDIUM_MATERIAL_COUNT - 1) : random_uint(current_material_count - CONSTANT_MEDIUM_MATERIAL_COUNT, current_material_count - 1);
                        if(material_index >= MATERIAL_COUNT_UP_TO_DIALECTRIC && material_index < MATERIAL_COUNT_UP_TO_EMISSIVE) {
                            daxa_f32mat2x3 aabb = min_max.at(j);
                            LIGHT surface_light = {};
                            daxa_f32vec3 center = daxa_f32vec3_multiply_by_scalar(daxa_f32vec3_add_daxa_f32vec3(aabb.x, aabb.y), 0.5);
                            surface_light.position = daxa_f32mat4x4_multiply_by_daxa_f32vec4(instance.transform, 
                                daxa_f32vec4(center.x, center.y, center.z, 1.0));
                            surface_light.emissive = materials[material_index].emission;
                            surface_light.instance_info = OBJECT_INFO(i, j);
                            surface_light.type = GEOMETRY_LIGHT_CUBE;
                            // TODO: this will be based on voxel size
                            surface_light.size = VOXEL_EXTENT;
                            lights.push_back(surface_light);
                            light_config.cube_light_count++;
                        }

                        primitives.push_back(PRIMITIVE{
                            .material_index = material_index,
                        });
                    }

                    
                    // push AABB primitives
                    u64 current_primitive_size = (current_aabb_host_count + instance.primitive_count) * sizeof(AABB);

                    if(current_primitive_size > max_aabb_host_buffer_size) {
                        size_t aabb_copy_size = current_aabb_host_count * sizeof(AABB);
                        upload_aabb_primitives(aabb_host_buffer, aabb_buffer, aabb_buffer_offset, aabb_copy_size);
                        aabb_buffer_offset += aabb_copy_size;
                        current_aabb_host_count = 0;
                    }

                    std::memcpy((device.get_host_address_as<AABB>(aabb_host_buffer).value() + current_aabb_host_count),
                        min_max.data(),
                        instance.primitive_count * sizeof(AABB));
                    current_primitive_count += instance.primitive_count;
                    current_aabb_host_count += instance.primitive_count;

                    instances.push_back(instance);
                }

                if(current_aabb_host_count > 0) {
                    size_t aabb_copy_size = current_aabb_host_count * sizeof(AABB);
                    upload_aabb_primitives(aabb_host_buffer, aabb_buffer, aabb_buffer_offset, aabb_copy_size);
                    aabb_buffer_offset += aabb_copy_size;
                    current_aabb_host_count = 0;
                }

                // Update status for shaders
                status.obj_count = current_primitive_count;
                
                // Update instance count
                this->current_instance_count = instance_count;

                std::cout << "Num of instances: " << current_instance_count << std::endl;
                std::cout << "Num of cubes: " << current_primitive_count << std::endl;
                std::cout << "Num of materials: " << current_material_count << std::endl;


                return true;
            }


            daxa_Bool8 build_tlas() {
                
                // Blas buffer offset to zero
                proc_blas_buffer_offset = 0;

                // Clear previous blas build infos
                if(this->tlas != daxa::TlasId{})
                    device.destroy_tlas(tlas);
                for(auto blas : this->proc_blas)
                    device.destroy_blas(blas);


                // Clear previous procedural blas
                this->proc_blas.clear();
                this->proc_blas.reserve(current_instance_count);

                // reserve blas build infos
                blas_build_infos.reserve(current_instance_count);

                std::vector<daxa_BlasInstanceData> blas_instance_array = {};
                blas_instance_array.reserve(current_instance_count);

                // TODO: As much geometry as instances for now
                aabb_geometries.resize(current_instance_count);


                u32 current_instance_index = 0;

                // build procedural blas
                for(u32 i = 0; i < current_instance_count; i++) {
                    aabb_geometries.at(i).push_back(daxa::BlasAabbGeometryInfo{
                        .data = device.get_device_address(aabb_buffer).value() + (instances.at(i).first_primitive_index * sizeof(AABB)),
                        .stride = sizeof(AABB),
                        .count = instances.at(i).primitive_count,
                        // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
                        .flags = i < current_instance_count - CLOUD_INSTANCE_COUNT_X ? (u32)0x1 : (u32)0x2, // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
                    });

                    // Crear un daxa::Span a partir del vector
                    daxa::Span<const daxa::BlasAabbGeometryInfo> geometry_span(aabb_geometries.at(i).data(), aabb_geometries.at(i).size());

                    /// Create Procedural Blas:
                    blas_build_infos.push_back(daxa::BlasBuildInfo{
                        .flags = daxa::AccelerationStructureBuildFlagBits::PREFER_FAST_TRACE,       // Is also default
                        .dst_blas = {}, // Ignored in get_acceleration_structure_build_sizes.       // Is also default
                        .geometries = geometry_span,
                        .scratch_data = {}, // Ignored in get_acceleration_structure_build_sizes.   // Is also default
                    });

                    daxa::AccelerationStructureBuildSizesInfo proc_build_size_info = device.get_blas_build_sizes(blas_build_infos.at(blas_build_infos.size() - 1));

                    auto get_aligned = [&](u64 operand, u64 granularity) -> u64
                    {
                        return ((operand + (granularity - 1)) & ~(granularity - 1));
                    };

                    daxa_u32 scratch_alignment_size = get_aligned(proc_build_size_info.build_scratch_size, acceleration_structure_scratch_offset_alignment);


                    if((proc_blas_scratch_buffer_offset + scratch_alignment_size) > proc_blas_scratch_buffer_size) {
                        // TODO: Try to resize buffer
                        std::cout << "proc_blas_scratch_buffer_offset > proc_blas_scratch_buffer_size" << std::endl;
                        abort();
                    }
                    blas_build_infos.at(blas_build_infos.size() - 1).scratch_data = (device.get_device_address(proc_blas_scratch_buffer).value() + proc_blas_scratch_buffer_offset);
                    proc_blas_scratch_buffer_offset += scratch_alignment_size;


                    daxa_u32 build_aligment_size = get_aligned(proc_build_size_info.acceleration_structure_size, ACCELERATION_STRUCTURE_BUILD_OFFSET_ALIGMENT);

                    if((proc_blas_buffer_offset + build_aligment_size) > proc_blas_buffer_size) {
                        // TODO: Try to resize buffer
                        std::cout << "proc_blas_buffer_offset > proc_blas_buffer_size" << std::endl;
                        abort();
                    }
                    this->proc_blas.push_back(device.create_blas_from_buffer({
                        .blas_info = {.size = proc_build_size_info.acceleration_structure_size,
                            .name = "test procedural blas",
                        },
                        .buffer_id = proc_blas_buffer,
                        .offset = proc_blas_buffer_offset,
                    }));

                    proc_blas_buffer_offset +=  build_aligment_size;

                    blas_build_infos.at(blas_build_infos.size() - 1).dst_blas = this->proc_blas.at(this->proc_blas.size() - 1);

                    blas_instance_array.push_back(daxa_BlasInstanceData{
                        .transform =
                            daxa_f32mat4x4_to_daxa_f32mat3x4(instances.at(i).transform),
                        .instance_custom_index = i, // Is also default
                        .mask = 0xFF,
                        .instance_shader_binding_table_record_offset = {}, // Is also default
                        .flags = {},                                       // Is also default
                        .blas_device_address = device.get_device_address(this->proc_blas.at(this->proc_blas.size() - 1)).value(),
                    });

                    ++current_instance_index;
                }

                proc_blas_scratch_buffer_offset = 0;

                // Check if all instances were processed
                if(current_instance_index != current_instance_count) {
                    std::cout << "current_instance_index != current_instance_count" << std::endl;
                    return false;
                }

                /// create blas instances for tlas:
                auto blas_instances_buffer = device.create_buffer({
                    .size = sizeof(daxa_BlasInstanceData) * current_instance_count,
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



                // Copy instances to buffer
                u32 instance_buffer_size = static_cast<u32>(current_instance_count * sizeof(INSTANCE));
                if(instance_buffer_size > max_instance_buffer_size) {
                    std::cout << "instance_buffer_size > max_instance_buffer_size" << std::endl;
                    abort();
                }


                auto instance_staging_buffer = device.create_buffer({
                    .size = instance_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("instance_staging_buffer"),
                });
                defer { device.destroy_buffer(instance_staging_buffer); };

                auto * instance_buffer_ptr = device.get_host_address_as<INSTANCE>(instance_staging_buffer).value();
                std::memcpy(instance_buffer_ptr,
                    instances.data(),
                    instance_buffer_size);

                // Copy primitives to buffer
                u32 primitive_buffer_size = static_cast<u32>(current_primitive_count * sizeof(PRIMITIVE));
                if(primitive_buffer_size > max_primitive_buffer_size) {
                    std::cout << "primitive_buffer_size > max_primitive_buffer_size" << std::endl;
                    abort();
                }


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


                // TODO: Refactor materials copies
                daxa_u32 material_buffer_size = static_cast<u32>(current_material_count * sizeof(MATERIAL));
                if(material_buffer_size > max_material_buffer_size) {
                    std::cout << "material_buffer_size > max_material_buffer_size" << std::endl;
                    abort();
                }

                auto material_staging_buffer = device.create_buffer({
                    .size = material_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("material_staging_buffer"),
                });
                defer { device.destroy_buffer(material_staging_buffer); };

                auto * material_buffer_ptr = device.get_host_address_as<MATERIAL>(material_staging_buffer).value();
                std::memcpy(material_buffer_ptr,
                    materials.data(),
                    material_buffer_size);


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

                    return recorder.complete_current_commands();
                }();
                device.submit_commands({.command_lists = std::array{exec_cmds}});
                device.wait_idle();
                /// NOTE:
                /// No need to wait idle here.
                /// Daxa will defer all the destructions of the buffers until the submitted as build commands are complete.

                return true;
            }


            void upload_world() {

                // get world buffer host mapped pointer
                auto * world_buffer_ptr = device.get_host_address(world_buffer).value();

                world.instance_address = device.get_device_address(instance_buffer).value();
                world.primitive_address = device.get_device_address(primitive_buffer).value();
                world.aabb_address = device.get_device_address(aabb_buffer).value();
                world.material_address = device.get_device_address(material_buffer).value();
                world.light_address = device.get_device_address(light_buffer).value();

                // copy world to buffer
                std::memcpy(world_buffer_ptr,
                    &world,
                    world_buffer_size);
            }


            void upload_restir() {

                // get restir buffer host mapped pointer
                auto * restir_buffer_ptr = device.get_host_address(restir_buffer).value();

                restir.previous_reservoir_address = device.get_device_address(previous_reservoir_buffer).value();
                restir.intermediate_reservoir_address = device.get_device_address(intermediate_reservoir_buffer).value();
                restir.reservoir_address = device.get_device_address(reservoir_buffer).value();
                restir.previous_di_address = device.get_device_address(previous_direct_illum_buffer).value();
                restir.di_address = device.get_device_address(direct_illum_buffer).value();
                restir.velocity_address = device.get_device_address(velocity_buffer).value();
                restir.pixel_reconnection_data_address = device.get_device_address(pixel_reconnection_data_buffer).value();
                restir.output_path_reservoir_address = device.get_device_address(output_path_reservoir_buffer).value();
                restir.temporal_path_reservoir_address = device.get_device_address(temporal_path_reservoir_buffer).value();
                restir.indirect_color_address = device.get_device_address(indirect_color_buffer).value();

                // copy restir to buffer
                std::memcpy(restir_buffer_ptr,
                    &restir,
                    restir_buffer_size);

            }


            void upload_textures() {
                // CHESSBOARD PATTERN TEXTURE
                {
                    daxa_u32 SIZE_X = 256;
                    daxa_u32 SIZE_Y = 256;
                    daxa_u32 SIZE_Z = 1;

                    daxa_u32 image_stage_buffer_size = SIZE_X * SIZE_Y * SIZE_Z * 4;

                    images.push_back(device.create_image({
                        .dimensions = 2,
                        .format = daxa::Format::R8G8B8A8_UNORM,
                        .size = {SIZE_X, SIZE_Y, SIZE_Z},
                        .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE | daxa::ImageUsageFlagBits::TRANSFER_DST | daxa::ImageUsageFlagBits::SHADER_SAMPLED,
                        .name = "image_1",
                    }));

                    samplers.push_back(device.create_sampler({
                        .magnification_filter = daxa::Filter::NEAREST,
                        .minification_filter = daxa::Filter::NEAREST,
                        .max_lod = 0.0f,
                    }));

                    auto image_staging_buffer = device.create_buffer({
                        .size = image_stage_buffer_size,
                        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                        .name = ("image_staging_buffer"),
                    });
                    defer { device.destroy_buffer(image_staging_buffer); };

                    auto *image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                    // for(u32 i = 0; i < SIZE_X * SIZE_Y * SIZE_Z; i++) {
                    //     image_staging_buffer_ptr[i * 4 + 0] = 255;
                    //     image_staging_buffer_ptr[i * 4 + 1] = 255;
                    //     image_staging_buffer_ptr[i * 4 + 2] = 255;
                    //     image_staging_buffer_ptr[i * 4 + 3] = 255;
                    // }

                    // chessboard pattern for testing (black and white) 8x8 squares based on SIZE_X length
                    for (u32 x = 0; x < SIZE_X; x++)
                    {
                        for (u32 y = 0; y < SIZE_Y; y++)
                        {
                            for (u32 z = 0; z < SIZE_Z; z++)
                            {
                                if ((x / 32) % 2 == 0)
                                {
                                    if ((y / 32) % 2 == 0)
                                    {
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                    }
                                    else
                                    {
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                    }
                                }
                                else
                                {
                                    if ((y / 32) % 2 == 0)
                                    {
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 0;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                    }
                                    else
                                    {
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 255;
                                        image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                    }
                                }
                            }
                        }
                    }

                    auto exec_cmds = [&]()
                    {
                        auto recorder = device.create_command_recorder({});

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::HOST_WRITE,
                            .dst_access = daxa::AccessConsts::TRANSFER_READ,
                        });

                        recorder.copy_buffer_to_image({
                            .buffer = image_staging_buffer,
                            .image = images.at(images.size() - 1),
                            .image_extent = {SIZE_X, SIZE_Y, SIZE_Z},
                        });

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                            .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
                        });

                        return recorder.complete_current_commands();
                    }();
                    device.submit_commands({.command_lists = std::array{exec_cmds}});
                    ++current_texture_count;
                }

                // LOAD TEXTURE
                {

                    ImageTexture red_brick_wall = ImageTexture(RED_BRICK_WALL_IMAGE);
                    daxa_u32 SIZE_X = red_brick_wall.get_width();
                    daxa_u32 SIZE_Y = red_brick_wall.get_height();
                    daxa_u32 SIZE_Z = 1;

                    daxa_u32 image_stage_buffer_size = red_brick_wall.get_size();

                    images.push_back(device.create_image({
                        .dimensions = 2,
                        .format = daxa::Format::R8G8B8A8_UNORM, // change to R8G8B8A8_UNORM and doesn't crash
                        .size = {SIZE_X, SIZE_Y, SIZE_Z},
                        .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE | daxa::ImageUsageFlagBits::TRANSFER_DST | daxa::ImageUsageFlagBits::SHADER_SAMPLED,
                        .name = "image_2",
                    }));

                    // samplers.push_back(device.create_sampler({
                    //     .magnification_filter = daxa::Filter::NEAREST,
                    //     .minification_filter = daxa::Filter::NEAREST,
                    //     .max_lod = 0.0f,
                    // }));

                    auto image_staging_buffer = device.create_buffer({
                        .size = image_stage_buffer_size,
                        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                        .name = ("image_staging_buffer"),
                    });
                    defer { device.destroy_buffer(image_staging_buffer); };

                    auto *image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                    memcpy(
                        image_staging_buffer_ptr,
                        red_brick_wall.get_data(),
                        image_stage_buffer_size);

                    auto exec_cmds = [&]()
                    {
                        auto recorder = device.create_command_recorder({});

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::HOST_WRITE,
                            .dst_access = daxa::AccessConsts::TRANSFER_READ,
                        });

                        recorder.copy_buffer_to_image({
                            .buffer = image_staging_buffer,
                            .image = images.at(images.size() - 1),
                            .image_extent = {SIZE_X, SIZE_Y, SIZE_Z},
                        });

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                            .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
                        });

                        return recorder.complete_current_commands();
                    }();
                    device.submit_commands({.command_lists = std::array{exec_cmds}});

                    ++current_texture_count;
                }

                // LOAD TEXTURE
                {
                    // NoiseTexture perlin_texture = NoiseTexture();
                    // daxa_u32 SIZE_X = perlin_texture.get_pixel_count();

                    // daxa_u32 image_stage_buffer_size = perlin_texture.get_pixel_count_in_bytes();

                    auto perlin_data = get_perm_noise_texture();

                    daxa_u32 SIZE_X = 256;
                    daxa_u32 SIZE_Y = 256;
                    daxa_u32 SIZE_Z = 1;

                    daxa_u32 image_stage_buffer_size = 256 * 256 * 4;

                    images.push_back(device.create_image({
                        .dimensions = 2,
                        .format = daxa::Format::R8G8B8A8_UNORM, // change to R8G8B8A8_UNORM and doesn't crash
                        .size = {SIZE_X, SIZE_Y, SIZE_Z},
                        .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE | daxa::ImageUsageFlagBits::TRANSFER_DST | daxa::ImageUsageFlagBits::SHADER_SAMPLED,
                        .name = "image_3",
                    }));

                    // samplers.push_back(device.create_sampler({
                    //     .magnification_filter = daxa::Filter::NEAREST,
                    //     .minification_filter = daxa::Filter::NEAREST,
                    //     .max_lod = 0.0f,
                    // }));

                    auto image_staging_buffer = device.create_buffer({
                        .size = image_stage_buffer_size,
                        .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                        .name = ("image_staging_buffer"),
                    });
                    defer { device.destroy_buffer(image_staging_buffer); };

                    auto *image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                    memcpy(
                        image_staging_buffer_ptr,
                        perlin_data.get(),
                        image_stage_buffer_size);

                    auto exec_cmds = [&]()
                    {
                        auto recorder = device.create_command_recorder({});

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::HOST_WRITE,
                            .dst_access = daxa::AccessConsts::TRANSFER_READ,
                        });

                        recorder.copy_buffer_to_image({
                            .buffer = image_staging_buffer,
                            .image = images.at(images.size() - 1),
                            .image_extent = {SIZE_X, SIZE_Y, SIZE_Z},
                        });

                        recorder.pipeline_barrier({
                            .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                            .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
                        });

                        return recorder.complete_current_commands();
                    }();
                    device.submit_commands({.command_lists = std::array{exec_cmds}});

                    ++current_texture_count;
                }
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

                bool ray_tracing_supported = device.properties().ray_tracing_properties.has_value();
                invocation_reorder_mode = device.properties().invocation_reorder_properties.has_value() ? device.properties().invocation_reorder_properties.value().invocation_reorder_mode : 0;
                std::string ray_tracing_supported_str = ray_tracing_supported ? "available" : "not available";

                std::cout << "Choosen Device: " << device.properties().device_name <<
                            ", Ray Tracing: " <<  ray_tracing_supported_str <<
                            ", Invocation Reordering mode: " << invocation_reorder_mode  << std::endl;

                if(ray_tracing_supported == false) {
                    std::cout << "Ray tracing is not supported" << std::endl;
                    abort();
                }


                acceleration_structure_scratch_offset_alignment = device.properties().acceleration_structure_properties.value().min_acceleration_structure_scratch_offset_alignment;


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

                light_config_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = light_config_buffer_size,
                    .name = ("light_config_buffer"),
                });

                cam_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = cam_buffer_size,
                    .name = ("cam_buffer"),
                });

                status_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = status_buffer_size,
                    .name = ("status_buffer"),
                });

                world_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = world_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("world_buffer"),
                });

                instance_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_instance_buffer_size,
                    .name = ("instance_buffer"),
                });

                primitive_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_primitive_buffer_size,
                    .name = ("primitive_buffer"),
                });

                // https://registry.khronos.org/vulkan/specs/1.3-extensions/html/vkspec.html#VUID-VkAccelerationStructureBuildGeometryInfoKHR-type-03792
                // GeometryType of each element of pGeometries must be the same
                aabb_buffer = device.create_buffer({
                    .size = max_aabb_buffer_size,
                    .name = "aabb buffer",
                });

                aabb_host_buffer = device.create_buffer({
                    .size = max_aabb_host_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "aabb host buffer",
                });

                material_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_material_buffer_size,
                    .name = ("material_buffer"),
                });

                light_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_light_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("light_buffer"),
                });

                // status_output_buffer = device.create_buffer(daxa::BufferInfo{
                //     .size = max_status_output_buffer_size,
                //     .name = ("status_output_buffer"),
                // });

                restir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = restir_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("restir_bufffer"),
                });

                previous_reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_reservoir_buffer_size,
                    .name = ("previous_reservoir_buffer"),
                });

                intermediate_reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_reservoir_buffer_size,
                    .name = ("intermediate_reservoir_buffer"),
                });

                reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_reservoir_buffer_size,
                    .name = ("reservoir_buffer"),
                });

                velocity_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_velocity_buffer_size,
                    .name = ("velocity_buffer"),
                });

                previous_direct_illum_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_direct_illum_buffer_size,
                    .name = ("previous_direct_illum_buffer"),
                });

                direct_illum_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_direct_illum_buffer_size,
                    .name = ("direct_illum_buffer"),
                });

                pixel_reconnection_data_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_pixel_reconnection_data_buffer_size,
                    .name = ("pixel_reconnection_data_buffer"),
                });

                output_path_reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_output_path_reservoir_buffer_size,
                    .name = ("output_path_reservoir_buffer"),
                });

                temporal_path_reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_output_path_reservoir_buffer_size,
                    .name = ("temporal_path_reservoir_buffer"),
                });

                indirect_color_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_indirect_color_buffer_size,
                    .name = ("indirect_color_buffer"),
                });

                proc_blas_scratch_buffer = device.create_buffer({
                    .size = proc_blas_scratch_buffer_size,
                    .name = "proc blas build scratch buffer",
                });

                proc_blas_buffer = device.create_buffer({
                    .size = proc_blas_buffer_size,
                    .name = "proc blas buffer",
                });

                upload_world();
                upload_restir();

                // Create a new context for the gvox library
                map_loader.create_gvox_context();

                // load map
                GvoxModelData gvox_map = map_loader.load_gvox_data(std::string(MODEL_PATH) + "/" + MAP_NAME);

                std::cout << "gvox_map size: " << gvox_map.size << std::endl;

                size_t map_size = gvox_map.size;
                delete gvox_map.ptr;

                // hit_distance_buffer = device.create_buffer(daxa::BufferInfo{
                //     .size = max_hit_distance_buffer_size,
                //     .name = ("hit_distance_buffer"),
                // });

                // DEBUGGING
                // hit_distances.resize(WIDTH_RES * HEIGHT_RES);

                // TODO: This could be load from a file
                {

                    u32 instance_count_x = (INSTANCE_X_AXIS_COUNT * 2);
                    u32 instance_count_z = (INSTANCE_Z_AXIS_COUNT * 2);

                    daxa_u32 estimated_instance_count = (instance_count_x * instance_count_z + CLOUD_INSTANCE_COUNT_X) * CHUNK_VOXEL_COUNT;

                    if(estimated_instance_count > MAX_INSTANCES) {
                        std::cout << "estimated_instance_count (" << estimated_instance_count << ") > MAX_INSTANCES (" << MAX_INSTANCES << ")." << std::endl;
                        abort();
                    }

                    if(estimated_instance_count == 0) {
                        std::cout << "estimated_instance_count == 0" << std::endl;
                        abort();
                    }

                    transforms.reserve(estimated_instance_count);

                    // Centered around 0, 0, 0 positioning instances like a mirror
                    f32 x_axis_initial_position = ((INSTANCE_X_AXIS_COUNT) * AXIS_DISPLACEMENT / 2);
                    f32 z_axis_initial_position = ((INSTANCE_Z_AXIS_COUNT) * AXIS_DISPLACEMENT / 2);


                    for(i32 x_instance = -INSTANCE_X_AXIS_COUNT; x_instance < (i32)INSTANCE_X_AXIS_COUNT; x_instance++) {
                        auto x_instance_displacement = (x_instance * (AXIS_DISPLACEMENT));
                        for(i32 z_instance = -INSTANCE_Z_AXIS_COUNT; z_instance < (i32)INSTANCE_Z_AXIS_COUNT; z_instance++) {
                            auto z_instance_displacement = (z_instance * (AXIS_DISPLACEMENT));
                            for(u32 z = 0; z < VOXEL_COUNT_BY_AXIS; z++) {
                                for(u32 y = 0; y < VOXEL_COUNT_BY_AXIS; y++) {
                                    for(u32 x = 0; x < VOXEL_COUNT_BY_AXIS; x++) {
                                        // if(random_float(0.0, 1.0) > 0.95) {
                                        if(random_float(0.0, 1.0) > 0.75) {
                                            auto position_instance = generate_center_by_coord(x, y, z, CHUNK_EXTENT);
                                            transforms.push_back(daxa_f32mat4x4{
                                                {1, 0, 0, x_instance_displacement + position_instance.x},
                                                {0, 1, 0, position_instance.y},
                                                {0, 0, 1, z_instance_displacement + position_instance.z},
                                                {0, 0, 0, 1},
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // transforms.push_back(daxa_f32mat4x4{
                    //     {1, 0, 0, -AXIS_DISPLACEMENT},
                    //     {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_Z_AXIS_COUNT},
                    //     {0, 0, 1, 0},
                    //     {0, 0, 0, 1},
                    // });

                    // transforms.push_back(daxa_f32mat4x4{
                    //     {1, 0, 0, 0},
                    //     {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_X_AXIS_COUNT},
                    //     {0, 0, 1, 0},
                    //     {0, 0, 0, 1},
                    // });

                    current_instance_count = transforms.size();

                    upload_textures();


                    current_material_count = MATERIAL_COUNT;

                    materials.reserve(current_material_count);

                    for(u32 i = 0; i < LAMBERTIAN_MATERIAL_COUNT; i++) {

                        daxa_u32 texture_id = MAX_TEXTURES;
                        daxa_f32 random_float_value = random_float(0.0, 1.0);
                        if(random_float_value > 0.80) {
                            texture_id = random_uint(0, current_texture_count - 1);
                        }

                        materials.push_back(MATERIAL{
                            .type = MATERIAL_TYPE_LAMBERTIAN + ((texture_id == MAX_TEXTURES) ? 0 : ((texture_id == current_texture_count -1) ? MATERIAL_PERLIN_ON : MATERIAL_TEXTURE_ON)),
                            .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .diffuse =  {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .transmittance = {0.0f, 0.0f, 0.0f},
                            .emission = {0.0, 0.0, 0.0},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            // .dissolve = (-1/random_float(0.1, 1.0)),
                            // .dissolve = (random_float(0.1, 1.0)),
                            .dissolve = 1.0,
                            .illum = 3,
                            .texture_id = (texture_id != MAX_TEXTURES) ? images.at(texture_id).default_view()  : daxa::ImageViewId{},
                            .sampler_id = samplers.at(0),
                        });
                    }

                    for(u32 i = 0; i < METAL_MATERIAL_COUNT; i++) {
                        materials.push_back(MATERIAL{
                            .type = MATERIAL_TYPE_METAL,
                            .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .diffuse =  {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .transmittance = {0.0f, 0.0f, 0.0f},
                            .emission = {0.0, 0.0, 0.0},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            // .dissolve = (-1/random_float(0.1, 1.0)),
                            // .dissolve = (random_float(0.1, 1.0)),
                            .dissolve = 1.0,
                            .illum = 3,
                            .texture_id = MAX_TEXTURES,
                            .sampler_id = MAX_TEXTURES,
                        });
                    }



                    for(u32 i = 0; i < DIALECTRIC_MATERIAL_COUNT; i++) {
                        materials.push_back(MATERIAL{
                            .type = MATERIAL_TYPE_DIELECTRIC,
                            .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .diffuse =  {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .transmittance = {0.0f, 0.0f, 0.0f},
                            .emission = {0.0, 0.0, 0.0},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            .dissolve = 1.0,
                            .illum = 3,
                            .texture_id = MAX_TEXTURES,
                            .sampler_id = MAX_TEXTURES,
                        });
                    }

                    for(u32 i = 0; i < EMISSIVE_MATERIAL_COUNT; i++) {
                        materials.push_back(MATERIAL{
                            .type = MATERIAL_TYPE_LAMBERTIAN,
                            .ambient = {1.0, 1.0, 1.0},
                            .diffuse =  {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
                            .specular = {1.0, 1.0, 1.0},
                            .transmittance = {0.0, 0.0, 0.0},
                            .emission = {random_float(10.0, 20.0), random_float(10.0, 20.0), random_float(10.0, 20.0)},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            .dissolve = 1.0,
                            .illum = 3,
                            .texture_id = MAX_TEXTURES,
                            .sampler_id = MAX_TEXTURES,
                        });
                    }

                    for(u32 i = 0; i < CONSTANT_MEDIUM_MATERIAL_COUNT; i++) {
                        materials.push_back(MATERIAL{
                            .type = MATERIAL_TYPE_CONSTANT_MEDIUM,
                            .ambient = {0.999, 0.999, 0.999},
                            .diffuse =  {0.999, 0.999, 0.999},
                            .specular = {0.999, 0.999, 0.999},
                            .transmittance =  {random_float(0.9, 0.999), random_float(0.9, 0.999), random_float(0.9, 0.999)},
                            .emission = {0.0, 0.0, 0.0},
                            .shininess = random_float(0.0, 4.0),
                            .roughness = random_float(0.0, 1.0),
                            .ior = random_float(1.0, 2.65),
                            // .dissolve = (-1.0f/random_float(0.1, 0.5)),
                            .dissolve = random_float(0.1, 0.3),
                            .illum = 4,
                            .texture_id = MAX_TEXTURES,
                            .sampler_id = MAX_TEXTURES,
                        });
                    }
                }

                light_config.light_count = 0;
                lights.reserve(MAX_LIGHTS);
#if POINT_LIGHT_ON == 1                
                create_point_lights();
#endif
                create_environment_light();

                // call build tlas
                if(!load_blas_info(current_instance_count)) {
                    std::cout << "Failed to load blas info" << std::endl;
                    abort();
                }
                if(!build_tlas()) {
                    std::cout << "Failed to build tlas" << std::endl;
                    abort();
                }

                load_lights();


                reset_camera(camera);
                // camera_set_defocus_angle(camera, 0.5f);
                // camera_set_focus_dist(camera, 1.0f);

                status.max_depth = MAX_DEPTH;
                load_reservoirs();

                daxa::ShaderCompileOptions shader_compile_options = {
                    .root_paths = {
                        DAXA_SHADER_INCLUDE_DIR,
                        "src/shaders",
                    },
                    .write_out_preprocessed_code = "build/Debug",
                    .write_out_shader_binary = "build/Debug",
                    .enable_debug_info = false,
                };

                pipeline_manager = daxa::PipelineManager{daxa::PipelineManagerInfo{
                    .device = device,
                    .shader_compile_options = shader_compile_options,
                }};


                daxa::ShaderCompileOptions rt_shader_compile_options = {
                    .root_paths = {
                        DAXA_SHADER_INCLUDE_DIR,
                        "src/shaders/raytracing",
                        "src/shaders/restir_pt",
                    },
                    .write_out_preprocessed_code = "build/Debug",
                    .write_out_shader_binary = "build/Debug",
                    .enable_debug_info = false,
                };

                auto rgen_restir_prepass_selection_compile_options = rt_shader_compile_options;
                rgen_restir_prepass_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"RESTIR_PREPASS_AND_FIRST_VISIBILITY_TEST", "1"}};
                if(invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER)) {
                    rgen_restir_prepass_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
                }

                // NOTE: splitting the restir prepass and the first visibility impacts performance
                // auto rgen_restir_first_vis_test_selection_compile_options = rt_shader_compile_options;
                // rgen_restir_first_vis_test_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"FIRST_VISIBILITY_TEST", "1"}};

                auto rgen_restir_temp_reuse_selection_compile_options = rt_shader_compile_options;
                rgen_restir_temp_reuse_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"TEMPORAL_REUSE_PASS", "1"}};
                if(invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER)) {
                    rgen_restir_temp_reuse_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
                }

                // It doesn't improve visual quality too much
                // auto rgen_restir_second_vis_test_selection_compile_options = rt_shader_compile_options;
                // rgen_restir_second_vis_test_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"SECOND_VISIBILITY_TEST", "1"}};

                auto rgen_restir_spatial_reuse_selection_compile_options = rt_shader_compile_options;
                rgen_restir_spatial_reuse_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"SPATIAL_REUSE_PASS", "1"}};
                if(invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER)) {
                    rgen_restir_spatial_reuse_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
                }

                auto rgen_restir_shading_selection_compile_options = rt_shader_compile_options;
                rgen_restir_shading_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"THIRD_VISIBILITY_TEST_AND_SHADING_PASS", "1"}};
                if(invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER)) {
                    rgen_restir_shading_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
                }

                auto shadow_miss_compile_options = rt_shader_compile_options;
                shadow_miss_compile_options.defines = std::vector{daxa::ShaderDefine{"MISS_SHADOW", "1"}};

                auto tex_call_compile_options = rt_shader_compile_options;
                tex_call_compile_options.defines = std::vector{daxa::ShaderDefine{"MATERIAL_TEXTURE", "1"}};

                auto perlin_call_compile_options = rt_shader_compile_options;
                perlin_call_compile_options.defines = std::vector{daxa::ShaderDefine{"PERLIN_TEXTURE", "1"}};

                auto metallic_call_compile_options = rt_shader_compile_options;
                metallic_call_compile_options.defines = std::vector{daxa::ShaderDefine{"METAL", "1"}};

                auto dielectric_call_compile_options = rt_shader_compile_options;
                dielectric_call_compile_options.defines = std::vector{daxa::ShaderDefine{"DIELECTRIC", "1"}};

                auto emissive_call_compile_options = rt_shader_compile_options;
                emissive_call_compile_options.defines = std::vector{daxa::ShaderDefine{"EMISSIVE", "1"}};

                auto constant_medium_call_compile_options = rt_shader_compile_options;
                constant_medium_call_compile_options.defines = std::vector{daxa::ShaderDefine{"CONSTANT_MEDIUM", "1"}};

                auto ris_selection_compile_options = rt_shader_compile_options;
                ris_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"RIS_SELECTION", "1"}};

                auto indirect_illumination_compile_options = rt_shader_compile_options;
                indirect_illumination_compile_options.defines = std::vector{daxa::ShaderDefine{"INDIRECT_ILLUMINATION", "1"}};

                auto const ray_trace_pipe_info = daxa::RayTracingPipelineCompileInfo{
                    .ray_gen_infos = {daxa::ShaderCompileInfo{
                                          .source = daxa::ShaderFile{"rgen.glsl"},
                                          .compile_options = rgen_restir_prepass_selection_compile_options,
                                      },
                                      daxa::ShaderCompileInfo{
                                          .source = daxa::ShaderFile{"rgen.glsl"},
                                          .compile_options = rgen_restir_temp_reuse_selection_compile_options,
                                      },
                                        daxa::ShaderCompileInfo{
                                            .source = daxa::ShaderFile{"rgen.glsl"},
                                            .compile_options = rgen_restir_spatial_reuse_selection_compile_options,
                                        },
                                      daxa::ShaderCompileInfo{
                                          .source = daxa::ShaderFile{"rgen.glsl"},
                                          .compile_options = rgen_restir_shading_selection_compile_options,
                                      }},
                    .intersection_infos = {
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rint.glsl"},
                            .compile_options = rt_shader_compile_options,
                        },
                    },
                    .any_hit_infos = {
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rahit.glsl"},
                            .compile_options = rt_shader_compile_options,
                        },
                    },
                    .callable_infos = {
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_mat.glsl"},
                            .compile_options = tex_call_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_mat.glsl"},
                            .compile_options = perlin_call_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_scatter.glsl"},
                            .compile_options = rt_shader_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_scatter.glsl"},
                            .compile_options = metallic_call_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_scatter.glsl"},
                            .compile_options = dielectric_call_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rcall_scatter.glsl"},
                            .compile_options = constant_medium_call_compile_options,
                        },
                    },
                    .closest_hit_infos = {
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rchit.glsl"},
                            .compile_options = ris_selection_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rchit.glsl"},
                            .compile_options = indirect_illumination_compile_options,
                        },
                    },
                    .miss_hit_infos = {
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rmiss.glsl"},
                            .compile_options = rt_shader_compile_options,
                        },
                        daxa::ShaderCompileInfo{
                            .source = daxa::ShaderFile{"rmiss.glsl"},
                            .compile_options = shadow_miss_compile_options,
                        },
                    },
                    .shader_groups_infos = {
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 0,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 1,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 2,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 3,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 14,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 15,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::PROCEDURAL_HIT_GROUP,
                            .closest_hit_shader_index = 12,
                            .any_hit_shader_index = 5,
                            .intersection_shader_index = 4,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::PROCEDURAL_HIT_GROUP,
                            .closest_hit_shader_index = 13,
                            .any_hit_shader_index = 5,
                            .intersection_shader_index = 4,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 6,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 7,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 8,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 9,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 10,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 11,
                        },
                    },
                    .max_ray_recursion_depth = status.max_depth,
                    .push_constant_size = sizeof(PushConstant),
                    .name = "ray trace shader",
                };
                rt_pipeline = pipeline_manager.add_ray_tracing_pipeline(ray_trace_pipe_info).value();


                compute_motion_vectors_pipeline = pipeline_manager.add_compute_pipeline(daxa::ComputePipelineCompileInfo{
                    .shader_info = daxa::ShaderCompileInfo{
                        .source = daxa::ShaderFile{"motion_vec.glsl"},
                        .compile_options = shader_compile_options,
                    },
                    .push_constant_size = sizeof(PushConstant),
                    .name = "motion vector shader",
                }).value();
            }

            auto update() -> bool
            {
                auto reload_result = pipeline_manager.reload_all();

                if (auto * reload_err = daxa::get_if<daxa::PipelineReloadError>(&reload_result))
                    std::cout << reload_err->message << std::endl;
                else if (daxa::get_if<daxa::PipelineReloadSuccess>(&reload_result))
                    std::cout << "reload success" << std::endl;
                glfwPollEvents();
                if (glfwWindowShouldClose(glfw_window_ptr) != 0)
                {
                    return true;
                }

                if (!minimized)
                {
#if DYNAMIC_SUN_LIGHT == 1 && POINT_LIGHT_ON == 1
                    update_lights();
#endif // DYNAMIC_SUN_LIGHT == 1
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

                camera_set_aspect(camera, width, height);

                camera_view camera_view = {
                    .inv_view = glm_mat4_to_daxa_f32mat4x4(get_inverse_view_matrix(camera)),
                    .inv_proj = glm_mat4_to_daxa_f32mat4x4(get_inverse_projection_matrix(camera)),
                    .defocus_angle = camera.defocus_angle,
                    .focus_dist = camera.focus_dist,
                };

                // NOTE: Vulkan has inverted y axis in NDC
                camera_view.inv_proj.y.y *= -1;

                auto cam_staging_buffer = device.create_buffer({
                    .size = cam_update_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("cam_staging_buffer"),
                });
                defer { device.destroy_buffer(cam_staging_buffer); };

                auto * buffer_ptr = device.get_host_address_as<daxa_f32mat4x4>(cam_staging_buffer).value();
                std::memcpy(buffer_ptr,
                    &camera_view,
                    cam_update_size);

                // Update/restore status

                if(camera_get_moved(camera)) {
                    camera_reset_moved(camera);
                    status.num_accumulated_frames = 0;
                }

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

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::HOST_WRITE,
                    .dst_access = daxa::AccessConsts::TRANSFER_READ,
                });

                recorder.copy_buffer_to_buffer({
                    .src_buffer = cam_staging_buffer,
                    .dst_buffer = cam_buffer,
                    .size = cam_buffer_size - previous_matrices,
                });

                recorder.copy_buffer_to_buffer(
                    {
                        .src_buffer = status_staging_buffer,
                        .dst_buffer = status_buffer,
                        .size = status_buffer_size,
                    }
                );


                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_READ,
                });

                recorder.pipeline_barrier_image_transition({
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                    .src_layout = daxa::ImageLayout::UNDEFINED,
                    .dst_layout = daxa::ImageLayout::GENERAL,
                    .image_id = swapchain_image,
                });

                auto swapchain_image_view = swapchain_image.default_view();

                recorder.set_pipeline(*rt_pipeline);
                recorder.push_constant(PushConstant{
                    .size = {width, height},
                    .tlas = tlas,
                    .swapchain = swapchain_image_view,
                    .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                    .status_buffer = this->device.get_device_address(status_buffer).value(),
                    .world_buffer = this->device.get_device_address(world_buffer).value(),
                    // .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                    .restir_buffer = this->device.get_device_address(restir_buffer).value(),
                    // .hit_distance_buffer = this->device.get_device_address(hit_distance_buffer).value(),
                    // .instance_level_buffer = this->device.get_device_address(instance_level_buffer).value(),
                    // .instance_distance_buffer = this->device.get_device_address(instance_distance_buffer).value(),
                    // .aabb_buffer = this->device.get_device_address(gpu_aabb_buffer).value(),
                });

                recorder.trace_rays({
                    .width = width,
                    .height = height,
                    .depth = 1,
                });

                // recorder.pipeline_barrier({
                //     .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                //     .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_READ,
                // });

                // recorder.push_constant(PushConstant{
                //     .size = {width, height},
                //     .tlas = tlas,
                //     .swapchain = swapchain_image_view,
                //     .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                //     .status_buffer = this->device.get_device_address(status_buffer).value(),
                //     .world_buffer = this->device.get_device_address(world_buffer).value(),
                //     // .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                //     .restir_buffer = this->device.get_device_address(restir_buffer).value(),
                // });

                // recorder.trace_rays({
                //     .width = width,
                //     .height = height,
                //     .depth = 1,
                //     .raygen_shader_binding_table_offset = 1,
                // });

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_READ,
                });

                recorder.push_constant(PushConstant{
                    .size = {width, height},
                    .tlas = tlas,
                    .swapchain = swapchain_image_view,
                    .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                    .status_buffer = this->device.get_device_address(status_buffer).value(),
                    .world_buffer = this->device.get_device_address(world_buffer).value(),
                    // .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                    .restir_buffer = this->device.get_device_address(restir_buffer).value(),
                });

                recorder.trace_rays({
                    .width = width,
                    .height = height,
                    .depth = 1,
                    .raygen_shader_binding_table_offset = 2,
                });

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_READ,
                });

                recorder.push_constant(PushConstant{
                    .size = {width, height},
                    .tlas = tlas,
                    .swapchain = swapchain_image_view,
                    .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                    .status_buffer = this->device.get_device_address(status_buffer).value(),
                    .world_buffer = this->device.get_device_address(world_buffer).value(),
                    // .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                    .restir_buffer = this->device.get_device_address(restir_buffer).value(),
                });

                recorder.trace_rays({
                    .width = width,
                    .height = height,
                    .depth = 1,
                    .raygen_shader_binding_table_offset = 3,
                });


                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                    .dst_access = daxa::AccessConsts::TRANSFER_READ,
                });

                recorder.copy_buffer_to_buffer({
                    .src_buffer = cam_buffer,
                    .dst_buffer = cam_buffer,
                    .src_offset = 0,
                    .dst_offset = cam_update_size,
                    .size = previous_matrices,
                });

                recorder.pipeline_barrier({
                    .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                    .dst_access = daxa::AccessConsts::HOST_READ,
                });

                recorder.pipeline_barrier_image_transition({
                    .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
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

                // Update/restore status
                status.frame_number++;
                status.num_accumulated_frames++;
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

#if(PERFECT_PIXEL_ON == 1)
                // // Some Device to Host copy here
                // auto status_output_staging_buffer = device.create_buffer({
                //     .size = max_status_output_buffer_size,
                //     .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                //     .name = ("status_output_staging_buffer"),
                // });
                // defer { device.destroy_buffer(status_output_staging_buffer); };

                // /// Record build commands:
                // auto exec_cmds = [&]()
                // {
                //     auto recorder = device.create_command_recorder({});
                //     recorder.pipeline_barrier({
                //         .src_access = daxa::AccessConsts::HOST_WRITE,
                //         .dst_access = daxa::AccessConsts::TRANSFER_READ,
                //     });

                //     // recorder.copy_buffer_to_buffer({
                //     //     .src_buffer = instance_level_buffer,
                //     //     .dst_buffer = instance_level_staging_buffer,
                //     //     .size = instance_level_buffer_size,
                //     // });

                //     // recorder.copy_buffer_to_buffer({
                //     //     .src_buffer = hit_distance_buffer,
                //     //     .dst_buffer = hit_distance_staging_buffer,
                //     //     .size = hit_distance_buffer_size,
                //     // });

                //     // recorder.copy_buffer_to_buffer({
                //     //     .src_buffer = instance_distance_buffer,
                //     //     .dst_buffer = instance_distance_staging_buffer,
                //     //     .size = instance_distance_buffer_size,
                //     // });

                //     // recorder.copy_buffer_to_buffer({
                //     //     .src_buffer = gpu_aabb_buffer,
                //     //     .dst_buffer = aabb_staging_buffer,
                //     //     .size = aabb_buffer_size,
                //     // });

                //     recorder.copy_buffer_to_buffer({
                //         .src_buffer = status_output_buffer,
                //         .dst_buffer = status_output_staging_buffer,
                //         .size = max_status_output_buffer_size,
                //     });

                //     recorder.pipeline_barrier({
                //         .src_access = daxa::AccessConsts::TRANSFER_WRITE,
                //         .dst_access = daxa::AccessConsts::HOST_READ,
                //     });
                //     return recorder.complete_current_commands();
                // }();

                // // WAIT FOR COMMANDS TO FINISH
                // {
                //     device.submit_commands({
                //         .command_lists = std::array{exec_cmds},
                //         // .signal_binary_semaphores = std::array{swapchain.current_present_semaphore()},
                //         // .signal_timeline_semaphores = std::array{std::pair{swapchain.gpu_timeline_semaphore(), swapchain.current_cpu_timeline_value()}},
                //     });

                //     device.wait_idle();
                //     // daxa::TimelineSemaphore gpu_timeline = device.create_timeline_semaphore({
                //     //     .name = "timeline semaphpore",
                //     // });

                //     // usize cpu_timeline = 0;

                //     // device.submit_commands({
                //     //     .command_lists = std::array{exec_cmds},
                //     //     .signal_timeline_semaphores = std::array{std::pair{gpu_timeline, cpu_timeline}}
                //     // });

                //     // gpu_timeline.wait_for_value(cpu_timeline);
                // }

                // STATUS_OUTPUT status_output;


                // auto * status_buffer_ptr = device.get_host_address_as<Status>(status_output_staging_buffer).value();
                // std::memcpy(&status_output,
                //     status_buffer_ptr,
                //     max_status_output_buffer_size);


                // std::cout << "status pixel [" << status.pixel.x << ", " << status.pixel.y << "]" << std::endl;
                // std::cout << "status out instance index " << status_output.instance_id << " primitive index " << status_output.primitive_id
                //     << " distance " << status_output.hit_distance << " exit " << status_output.exit_distance
                //     << " position [" << status_output.hit_position.x << ", " << status_output.hit_position.y << ", " << status_output.hit_position.z << "]"
                //     << " normal [" << status_output.hit_normal.x << ", " << status_output.hit_normal.y << ", " << status_output.hit_normal.z << "]"
                //     << " origin [" << status_output.origin.x << ", " << status_output.origin.y << ", " << status_output.origin.z << "]"
                //     << " direction [" << status_output.direction.x << ", " << status_output.direction.y << ", " << status_output.direction.z << "]"
                //     << " primitive center [" << status_output.primitive_center.x << ", " << status_output.primitive_center.y << ", " << status_output.primitive_center.z << "]"
                //     << " material_index " << status_output.material_index << ", uv [" << status_output.uv.x << ", " << status_output.uv.y << "]"
                //     << std::endl;
#endif // PERFECT_PIXEL_ON


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
                //                 AABB min_max = AABB({center.x - VOXEL_EXTENT, center.y - VOXEL_EXTENT, center.z - VOXEL_EXTENT}, {center.x + VOXEL_EXTENT, center.y + VOXEL_EXTENT, center.z + VOXEL_EXTENT});
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
                //     if(instance_levels[i].level_index != instances.at(i).level_index) {
                //         std::cout << "instance " << i << " level changed from " << instances.at(i).level_index << " to " << instance_levels[i].level_index << std::endl;
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

            void on_mouse_move(f32 x, f32 y) {
                // Input mouse movement to camera
                // if (glfwGetMouseButton(glfw_window_ptr, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS)
                // {
                    camera_set_mouse_delta(camera, glm::vec2{x, y});
                // }
            }
            void on_mouse_button(i32 button, i32 action) {

                if(button == GLFW_MOUSE_BUTTON_1) {
                    // Click right button store the current mouse position
                    if (action == GLFW_PRESS)
                    {
                        double mouse_x, mouse_y;
                        glfwGetCursorPos(glfw_window_ptr, &mouse_x, &mouse_y);

                        status.pixel = {static_cast<daxa_u32>(mouse_x), static_cast<daxa_u32>(mouse_y)};
                        status.is_active = true;

                        camera_set_mouse_left_press(camera, true);
                    }
                    // Release right button
                    else if (action == GLFW_RELEASE)
                    {
                        camera_set_mouse_left_press(camera, false);
                    }
                } else if(button == GLFW_MOUSE_BUTTON_MIDDLE) {
                    if(action == GLFW_PRESS) {
                        camera_set_mouse_middle_pressed(camera, true);
                    } else if(action == GLFW_RELEASE) {
                        camera_set_mouse_middle_pressed(camera, false);
                    }
                }

            }

            void on_scroll(f32 x, f32 y) {
                // camera_set_focus_dist(camera, glm::vec2{x, y});
                // std::cout << "scroll x: " << x << " scroll y: " << y << std::endl;
                switch((u32)y) {
                    case 1:{
                        if(camera_get_shift_status(camera)) {
                            camera_set_focus_dist(camera, camera.focus_dist + 0.1f);
                        } else {
                            camera_set_defocus_angle(camera, camera.defocus_angle + 0.1f);
                        }
                        break;
                    }
                    case -1:{
                        if(camera_get_shift_status(camera)) {
                            camera_set_focus_dist(camera, camera.focus_dist - 0.1f);
                        } else {
                            camera_set_defocus_angle(camera, camera.defocus_angle - 0.1f);
                        }
                        break;
                    }
                    default:
                        break;
                }
            }



            void on_key(i32 key, i32 action) {

                switch(key) {
                    case GLFW_KEY_W:
                    case GLFW_KEY_UP:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_forward(camera);
                        }
                        break;
                    case GLFW_KEY_S:
                    case GLFW_KEY_DOWN:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_backward(camera);
                        }
                        break;
                    case GLFW_KEY_A:
                    case GLFW_KEY_LEFT:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_left(camera);
                        }
                        break;
                    case GLFW_KEY_D:
                    case GLFW_KEY_RIGHT:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_right(camera);
                        }
                        break;
                    case GLFW_KEY_X:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_up(camera);
                        }
                        break;
                    case GLFW_KEY_SPACE:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            move_camera_down(camera);
                        }
                        break;
                    case GLFW_KEY_PAGE_UP:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            // camera.center.y -= SPEED;
                        }
                        break;
                    case GLFW_KEY_PAGE_DOWN:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            // camera.center.y += SPEED;
                        }
                        break;
                    case GLFW_KEY_Q:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            // camera.center.x -= SPEED;
                        }
                        break;
                    case GLFW_KEY_E:
                        if(action == GLFW_PRESS || action == GLFW_REPEAT) {
                            // camera.center.x += SPEED;
                        }
                        break;
                    case GLFW_KEY_R:
                        if(action == GLFW_PRESS) {
                            reset_camera(camera);
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
                            camera_set_moved(camera);
                        }
                        break;
                    case GLFW_KEY_LEFT_SHIFT:
                        if(action == GLFW_PRESS) {
                            camera_shift_pressed(camera);
                        } else if(action == GLFW_RELEASE) {
                            camera_shift_released(camera);
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
                    // compute_motion_vectors();
                    // update_status();
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
    tests::cubeland_app();
    return 0;
}
