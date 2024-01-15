#include <iostream>
#include <algorithm>
#include <thread>

#include <daxa/daxa.hpp>
#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>

#include <window.hpp>
#include <shared.hpp>

#include "shaders/shared.inl"
#include "rng.h"
#include "camera.h"
#include "texture.hpp"


namespace tests
{
    void ray_querry_triangle()
    {
        struct App : AppWindow<App>
        {
            const f32 AXIS_DISPLACEMENT = VOXEL_EXTENT * VOXEL_COUNT_BY_AXIS; //(2^4)
            const u32 INSTANCE_X_AXIS_COUNT = 2; // 2^2 (mirrored on both sides of the x axis)
            const u32 INSTANCE_Z_AXIS_COUNT = 2; // 2^2 (mirrored on both sides of the z axis)
            const u32 CLOUD_INSTANCE_COUNT = 1; // 2^1 (mirrored on both sides of the x axis)
            const u32 CLOUD_INSTANCE_COUNT_X = (CLOUD_INSTANCE_COUNT * 2);
            // const u32 INSTANCE_COUNT = INSTANCE_X_AXIS_COUNT * INSTANCE_Z_AXIS_COUNT;
            const u32 LAMBERTIAN_MATERIAL_COUNT = 80;
            const u32 METAL_MATERIAL_COUNT = 15;
            const u32 DIALECTRIC_MATERIAL_COUNT = 5;
            const u32 EMISSIVE_MATERIAL_COUNT = 5;
            const u32 CONSTANT_MEDIUM_MATERIAL_COUNT = 5;
            const u32 MATERIAL_COUNT = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT + EMISSIVE_MATERIAL_COUNT + CONSTANT_MEDIUM_MATERIAL_COUNT;
            const u32 MATERIAL_COUNT_UP_TO_DIALECTRIC = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT;
            const u32 MATERIAL_COUNT_UP_TO_EMISSIVE = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT + EMISSIVE_MATERIAL_COUNT;

            const char* RED_BRICK_WALL_IMAGE = "red_brick_wall.jpg";

            Status status = {};
            camera camera = {};


            daxa::Instance daxa_ctx = {};
            daxa::Device device = {};
            daxa::Swapchain swapchain = {};
            daxa::PipelineManager pipeline_manager = {};
            std::shared_ptr<daxa::RayTracingPipeline> rt_pipeline = {};
            std::shared_ptr<daxa::ComputePipeline> compute_motion_vectors_pipeline = {};
            daxa::TlasId tlas = {};
            std::vector<daxa::BlasId> proc_blas = {};

            // BUFFERS
            daxa::BufferId cam_buffer = {};
            size_t cam_buffer_size = sizeof(camera_view);
            size_t previous_matrices = sizeof(daxa_f32mat4x4) * 2;
            size_t cam_update_size = cam_buffer_size - previous_matrices;

            daxa::BufferId status_buffer = {};
            size_t status_buffer_size = sizeof(Status);

            daxa::BufferId instance_buffer = {};
            size_t max_instance_buffer_size = sizeof(INSTANCE) * MAX_INSTANCES;

            daxa::BufferId primitive_buffer = {};
            size_t max_primitive_buffer_size = sizeof(PRIMITIVE) * MAX_PRIMITIVES;

            daxa::BufferId aabb_buffer = {};
            size_t max_aabb_buffer_size = sizeof(daxa_f32mat3x2) * MAX_PRIMITIVES;

            u32 current_texture_count = 0;
            std::vector<daxa::ImageId> images = {};
            std::vector<daxa::SamplerId> samplers = {};

            daxa::BufferId material_buffer = {};
            size_t max_material_buffer_size = sizeof(MATERIAL) * MAX_MATERIALS;

            daxa::BufferId light_buffer = {};
            size_t max_light_buffer_size = sizeof(LIGHT) * MAX_LIGHTS;

            daxa::BufferId status_output_buffer = {};
            size_t max_status_output_buffer_size = sizeof(STATUS_OUTPUT);
            
            daxa::BufferId previous_reservoir_buffer = {};
            daxa::BufferId reservoir_buffer = {};
            size_t max_reservoir_buffer_size = sizeof(RESERVOIR) * MAX_RESERVOIRS;

            daxa::BufferId velocity_buffer = {};
            size_t max_velocity_buffer_size = sizeof(VELOCITY) * MAX_RESERVOIRS;

            daxa::BufferId previous_direct_illum_buffer = {};
            daxa::BufferId direct_illum_buffer = {};
            size_t max_direct_illum_buffer_size = sizeof(DIRECT_ILLUMINATION_INFO) * MAX_RESERVOIRS;

            // DEBUGGING
            // daxa::BufferId hit_distance_buffer = {};
            // size_t max_hit_distance_buffer_size = sizeof(HIT_DISTANCE) * WIDTH_RES * HEIGHT_RES;
            // std::vector<HIT_DISTANCE> hit_distances = {};
            // DEBUGGING
            
            // CPU DATA
            std::vector<daxa::BlasBuildInfo> blas_build_infos = {};
            std::vector<std::vector<daxa::BlasAabbGeometryInfo>> aabb_geometries = {};
            
            u32 current_instance_count = 0;
            std::array<INSTANCE, MAX_INSTANCES> instances = {};

            u32 current_primitive_count = 0;
            u32 max_current_primitive_count = 0;
            std::vector<PRIMITIVE> primitives = {};

            u32 current_material_count = 0;
            std::vector<MATERIAL> materials = {};

            std::vector<LIGHT> lights = {};

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
                    device.destroy_buffer(aabb_buffer);
                    device.destroy_buffer(material_buffer);
                    for(auto image : images)
                        device.destroy_image(image);
                    for(auto sampler : samplers)
                        device.destroy_sampler(sampler);
                    device.destroy_buffer(light_buffer);
                    device.destroy_buffer(status_buffer);
                    device.destroy_buffer(status_output_buffer);
                    device.destroy_buffer(previous_reservoir_buffer);
                    device.destroy_buffer(reservoir_buffer);
                    device.destroy_buffer(velocity_buffer);
                    device.destroy_buffer(previous_direct_illum_buffer);
                    device.destroy_buffer(direct_illum_buffer);
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

            daxa_f32mat3x4 daxa_f32mat4x4_to_daxa_f32mat3x4(daxa_f32mat4x4 const & mat)
            {
                return daxa_f32mat3x4{
                    {mat.x.x, mat.x.y, mat.x.z, mat.x.w},
                    {mat.y.x, mat.y.y, mat.y.z, mat.y.w},
                    {mat.z.x, mat.z.y, mat.z.z, mat.z.w}
                };
            }

            // Generate min max by coord (x, y, z) where x, y, z are 0 to VOXEL_COUNT_BY_AXIS-1 where VOXEL_COUNT_BY_AXIS / 2 is the center at (0, 0, 0)
            constexpr daxa_f32mat2x3 generate_min_max_by_coord(u32 x, u32 y, u32 z) const {
                return daxa_f32mat2x3{
                    {
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + (x * VOXEL_EXTENT) + AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + (y * VOXEL_EXTENT) + AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + (z * VOXEL_EXTENT) + AVOID_VOXEL_COLLAIDE
                    },
                    {
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + ((x + 1) * VOXEL_EXTENT) - AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + ((y + 1) * VOXEL_EXTENT) - AVOID_VOXEL_COLLAIDE,
                        -((VOXEL_COUNT_BY_AXIS/ 2) * VOXEL_EXTENT) + ((z + 1) * VOXEL_EXTENT) - AVOID_VOXEL_COLLAIDE
                    }
                };
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
                glm::vec3 middayPosition = glm::vec3(0.0, 20.0, 0.0);
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

                const daxa_u32 reservoir_buffer_size = static_cast<u32>(sizeof(RESERVOIR) * MAX_RESERVOIRS);

                // get previous reservoir buffer host mapped pointer
                auto * previous_reservoir_staging_buffer_ptr = device.get_host_address(previous_reservoir_buffer).value();

                // copy previous reservoirs to buffer
                std::memset(previous_reservoir_staging_buffer_ptr, 
                    0,
                    reservoir_buffer_size);

                // get reservoir buffer host mapped pointer
                auto * reservoir_staging_buffer_ptr = device.get_host_address(reservoir_buffer).value();

                // copy reservoirs to buffer
                std::memset(reservoir_staging_buffer_ptr, 
                    0,
                    reservoir_buffer_size);
                    
                const daxa_u32 velocity_buffer_size = static_cast<u32>(sizeof(daxa_i32vec2) * MAX_RESERVOIRS);

                // get velocity buffer host mapped pointer
                auto * velocity_staging_buffer_ptr = device.get_host_address(velocity_buffer).value();

                // copy velocities to buffer
                std::memset(velocity_staging_buffer_ptr, 
                    0,
                    velocity_buffer_size);

                const daxa_u32 direct_illum_buffer_size = static_cast<u32>(sizeof(DIRECT_ILLUMINATION_INFO) * MAX_RESERVOIRS);

                // get previous normal buffer host mapped pointer
                auto * previous_direct_illum_staging_buffer_ptr = device.get_host_address(previous_direct_illum_buffer).value();

                // copy previous normals to buffer
                std::memset(previous_direct_illum_staging_buffer_ptr, 
                    0,
                    direct_illum_buffer_size);

                // get normal buffer host mapped pointer
                auto * direct_illum_staging_buffer_ptr = device.get_host_address(direct_illum_buffer).value();

                // copy normals to buffer
                std::memset(direct_illum_staging_buffer_ptr, 
                    0,
                    direct_illum_buffer_size);
            }


            void create_point_lights() {
                // TODO: add more lights (random values?)
                status.light_count += 3;
                // status.light_count = 1;
                status.is_afternoon = true;

                if(status.light_count > MAX_LIGHTS) {
                    std::cout << "status.light_count > MAX_LIGHTS" << std::endl;
                    abort();
                }

                LIGHT light = {}; // 0: point light, 1: directional light
                light.position = daxa_f32vec3(0.0, 20.0, 0.0);
#if DYNAMIC_SUN_LIGHT == 1
                light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2);
#else 
                light.intensity = SUN_MAX_INTENSITY;
                status.time = 1.0;
                
#endif // DYNAMIC_SUN_LIGHT
                light.type = GEOMETRY_LIGHT_POINT;
                lights.push_back(light);

                LIGHT light2 = {};
                light2.position = daxa_f32vec3( -AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.5f, 1.0, 0.0);
                light2.emissive = daxa_f32vec3(3.0, 3.0, 3.0);
                light2.type = GEOMETRY_LIGHT_POINT;
                lights.push_back(light2);

                LIGHT light3 = {};
                light3.position = daxa_f32vec3(AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.0f, 1.0, 0.0);
                light3.emissive = daxa_f32vec3(4.0, 4.0, 4.0);
                light3.type = GEOMETRY_LIGHT_POINT;
                lights.push_back(light3);
            }

            void load_lights() {

                // Calculate light buffer size
                auto light_buffer_size = static_cast<u32>(sizeof(LIGHT) * status.light_count);
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
            }

             void update_lights() {

                if(lights.size() == 0) {
                    return;
                }

                if(status.light_count == 0) {
                    return;
                }

                if(status.light_count > MAX_LIGHTS) {
                    std::cout << "current_light_count > MAX_LIGHTS" << std::endl;
                    abort();
                }

                if(status.light_count != lights.size()) {
                    std::cout << "current_light_count != lights.size()" << std::endl;
                    abort();
                }

                // for(u32 i = 0; i < status.light_count; i++) {
                //     lights[i].position.x += 0.005;
                //     lights[i].position.y -= 0.005;
                //     lights[i].position.z += 0.005;
                // }

                // Speed of time progression
                float timeSpeed = 0.001;

                // Increment or decrement time
                status.time += timeSpeed * (status.is_afternoon ? 1.0 : -1.0);

                // Check for boundaries and reverse direction if needed
                if (status.time < 0.0 || status.time > 1.0) {
                    status.is_afternoon = !status.is_afternoon;
                    status.time = std::clamp(status.time, 0.0f, 1.0f);
                }

                lights[0].position = interpolate_sun_light(status.time, status.is_afternoon);
                daxa_f32 intensity = interpolate_sun_intensity(status.time, status.is_afternoon, SUN_MAX_INTENSITY /*max_intensity*/, 0.0f /*min_intensity*/);
                lights[0].emissive = daxa_f32vec3(intensity, intensity, intensity);
                
                // Calculate light buffer size
                auto light_buffer_size = static_cast<u32>(sizeof(LIGHT) * status.light_count);
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

             }

            daxa_Bool8 build_tlas(u32 instance_count) {
                daxa_Bool8 some_level_changed = false;

                if(instance_count == 0) {
                    std::cout << "instance_count == 0" << std::endl;
                    return false;
                }

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

                // https://registry.khronos.org/vulkan/specs/1.3-extensions/html/vkspec.html#VUID-VkAccelerationStructureBuildGeometryInfoKHR-type-03792
                // GeometryType of each element of pGeometries must be the same
                aabb_buffer = device.create_buffer({
                    .size = max_aabb_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = "aabb buffer",
                });

                current_primitive_count = 0;
                    
                std::vector<daxa_f32mat2x3> min_max;
                min_max.reserve(CHUNK_VOXEL_COUNT);

                for(u32 i = 0; i < instance_count; i++) {
                    min_max.clear();
                    
                    for(u32 z = 0; z < VOXEL_COUNT_BY_AXIS; z++) {
                        for(u32 y = 0; y < VOXEL_COUNT_BY_AXIS; y++) {
                            for(u32 x = 0; x < VOXEL_COUNT_BY_AXIS; x++) {
                                
                                if(random_float(0.0, 1.0) > 0.75) {
                                    min_max.push_back(generate_min_max_by_coord(x, y, z));
                                }
                            }
                        }
                    }

                    u32 primitive_count_current_instance = min_max.size();

                    instances[i].transform = {
                        transforms[i],
                    },
                    // TODO: get previous transform from previous build
                    instances[i].prev_transform = {
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

                        daxa_u32 material_index = (i < instance_count - CLOUD_INSTANCE_COUNT_X) ? random_uint(0, current_material_count - CONSTANT_MEDIUM_MATERIAL_COUNT - 1) : random_uint(current_material_count - CONSTANT_MEDIUM_MATERIAL_COUNT, current_material_count - 1);
                        if(material_index >= MATERIAL_COUNT_UP_TO_DIALECTRIC && material_index < MATERIAL_COUNT_UP_TO_EMISSIVE) {
                            LIGHT surface_light = {};
                            surface_light.position = daxa_f32vec3( );
                            surface_light.emissive = materials[material_index].emission;
                            surface_light.instance_index = i;
                            surface_light.primitive_index = j;
                            surface_light.type = GEOMETRY_LIGHT_QUAD;
                            lights.push_back(surface_light);
                            status.light_count++;
                        }

                        primitives.push_back(PRIMITIVE{
                            .material_index = material_index,
                        });
                    }
                }

                
                // COMMENT FROM HERE
                blas_build_infos.reserve(instance_count);

                std::vector<daxa_BlasInstanceData> blas_instance_array = {};
                blas_instance_array.reserve(instance_count);

                // TODO: As much geometry as instances for now
                aabb_geometries.resize(instance_count);


                u32 current_instance_index = 0;

                for(u32 i = 0; i < instance_count; i++) {

                    aabb_geometries.at(i).push_back(daxa::BlasAabbGeometryInfo{
                        .data = device.get_device_address(aabb_buffer).value() + (instances[i].first_primitive_index * sizeof(daxa_f32mat3x2)),
                        .stride = sizeof(daxa_f32mat3x2),
                        .count = instances[i].primitive_count,
                        // .flags = daxa::GeometryFlagBits::OPAQUE,                                    // Is also default
                        .flags = i < instance_count - CLOUD_INSTANCE_COUNT_X ? (u32)0x1 : (u32)0x2, // 0x1: OPAQUE, 0x2: NO_DUPLICATE_ANYHIT_INVOCATION, 0x4: TRI_CULL_DISABLE
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
                            daxa_f32mat4x4_to_daxa_f32mat3x4(instances[i].transform),
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

                light_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_light_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
                    .name = ("light_buffer"),
                });

                status_output_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_status_output_buffer_size,
                    .name = ("status_output_buffer"),
                });

                previous_reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_reservoir_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("previous_reservoir_buffer"),
                });

                reservoir_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_reservoir_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("reservoir_buffer"),
                });

                velocity_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_velocity_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("velocity_buffer"),
                });

                previous_direct_illum_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_direct_illum_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("previous_direct_illum_buffer"),
                });

                direct_illum_buffer = device.create_buffer(daxa::BufferInfo{
                    .size = max_direct_illum_buffer_size,
                    .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_SEQUENTIAL_WRITE,
                    .name = ("direct_illum_buffer"),
                });

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

                    current_instance_count = instance_count_x * instance_count_z + CLOUD_INSTANCE_COUNT_X;

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
                    transforms.push_back(daxa_f32mat4x4{
                        {1, 0, 0, -AXIS_DISPLACEMENT},
                        {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_Z_AXIS_COUNT},
                        {0, 0, 1, 0},
                        {0, 0, 0, 1},
                    });

                    transforms.push_back(daxa_f32mat4x4{
                        {1, 0, 0, 0},
                        {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_X_AXIS_COUNT},
                        {0, 0, 1, 0},
                        {0, 0, 0, 1},
                    });

                    if(transforms.size() < current_instance_count) {
                        std::cout << "transforms.size() != current_instance_count" << std::endl;
                        abort();
                    }

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

                        auto * image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                        // for(u32 i = 0; i < SIZE_X * SIZE_Y * SIZE_Z; i++) {
                        //     image_staging_buffer_ptr[i * 4 + 0] = 255;
                        //     image_staging_buffer_ptr[i * 4 + 1] = 255;
                        //     image_staging_buffer_ptr[i * 4 + 2] = 255;
                        //     image_staging_buffer_ptr[i * 4 + 3] = 255;
                        // }

                        // chessboard pattern for testing (black and white) 8x8 squares based on SIZE_X length
                        for(u32 x = 0; x < SIZE_X; x++) {
                            for(u32 y = 0; y < SIZE_Y; y++) {
                                for(u32 z = 0; z < SIZE_Z; z++) {
                                    if((x / 32) % 2 == 0) {
                                        if((y / 32) % 2 == 0) {
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 255;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 255;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 255;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                        } else {
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                        }
                                    } else {
                                        if((y / 32) % 2 == 0) {
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 0] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 1] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 2] = 0;
                                            image_staging_buffer_ptr[(x + y * SIZE_X + z * SIZE_X * SIZE_Y) * 4 + 3] = 255;
                                        } else {
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

                        auto * image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                        memcpy(
                            image_staging_buffer_ptr,
                            red_brick_wall.get_data(),
                            image_stage_buffer_size
                        );
                        
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

                        auto * image_staging_buffer_ptr = device.get_host_address_as<uint8_t>(image_staging_buffer).value();

                        memcpy(
                            image_staging_buffer_ptr,
                            perlin_data.get(),
                            image_stage_buffer_size
                        );
                        
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

                    
                    current_material_count = MATERIAL_COUNT;

                    materials.reserve(current_material_count);

                    for(u32 i = 0; i < LAMBERTIAN_MATERIAL_COUNT; i++) {
                        
                        daxa_u32 texture_id = MAX_TEXTURES;
                        daxa_f32 random_float_value = random_float(0.0, 1.0);
                        if(random_float_value > 0.95) {
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
                            .emission = {random_float(1.0, 20.0), random_float(1.0, 20.0), random_float(1.0, 20.0)},
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

                    proc_blas.reserve(current_instance_count);
                }

                status.light_count = 0;
                lights.reserve(MAX_LIGHTS);
                create_point_lights();

                // call build tlas
                if(!build_tlas(current_instance_count)) {
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
                    },
                    .write_out_preprocessed_code = "build/Debug",
                    .write_out_shader_binary = "build/Debug",
                    .enable_debug_info = false,
                };

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

                auto const ray_trace_pipe_info = daxa::RayTracingPipelineCompileInfo{
                    .ray_gen_infos = daxa::ShaderCompileInfo{
                        .source = daxa::ShaderFile{"rgen.glsl"},
                        .compile_options = rt_shader_compile_options,
                    },
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
                            .compile_options = rt_shader_compile_options,
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
                            .general_shader_index = 10,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 11,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::PROCEDURAL_HIT_GROUP,
                            .closest_hit_shader_index = 9,
                            .any_hit_shader_index = 2,
                            .intersection_shader_index = 1,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 3,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 4,
                        },
                        daxa::RayTracingShaderGroupInfo{
                            .type = daxa::ShaderGroup::GENERAL,
                            .general_shader_index = 5,
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
                using namespace std::literals;
                std::this_thread::sleep_for(1ms);
                glfwPollEvents();
                if (glfwWindowShouldClose(glfw_window_ptr) != 0)
                {
                    return true;
                }

                if (!minimized)
                {
#if DYNAMIC_SUN_LIGHT == 1                    
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
                    &instances,
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
                    .size = cam_buffer_size - previous_matrices,
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
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_READ,
                });

                recorder.pipeline_barrier_image_transition({
                    .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
                    .src_layout = daxa::ImageLayout::UNDEFINED,
                    .dst_layout = daxa::ImageLayout::GENERAL,
                    .image_id = swapchain_image,
                });

                recorder.set_pipeline(*rt_pipeline);
                recorder.push_constant(PushConstant{
                    .size = {width, height},
                    .tlas = tlas,
                    .swapchain = swapchain_image.default_view(),
                    .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                    .status_buffer = this->device.get_device_address(status_buffer).value(),
                    .instance_buffer = this->device.get_device_address(instance_buffer).value(),
                    .primitives_buffer = this->device.get_device_address(primitive_buffer).value(),
                    .aabb_buffer = this->device.get_device_address(aabb_buffer).value(),
                    .materials_buffer = this->device.get_device_address(material_buffer).value(),
                    .light_buffer = this->device.get_device_address(light_buffer).value(),
                    .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                    .velocity_buffer = this->device.get_device_address(velocity_buffer).value(),
                    .previous_di_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(previous_direct_illum_buffer).value() : this->device.get_device_address(direct_illum_buffer).value(),
                    .di_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(direct_illum_buffer).value() : this->device.get_device_address(previous_direct_illum_buffer).value(),
                    .previous_reservoir_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(previous_reservoir_buffer).value() : this->device.get_device_address(reservoir_buffer).value(),
                    .reservoir_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(reservoir_buffer).value() : this->device.get_device_address(previous_reservoir_buffer).value(),
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
                //     .dst_access = daxa::AccessConsts::TRANSFER_READ,
                // });

                // // recorder.set_pipeline(*compute_motion_vectors_pipeline);
                // // recorder.push_constant(PushConstant{
                // //     .size = {width, height},
                // //     .tlas = tlas,
                // //     .camera_buffer = this->device.get_device_address(cam_buffer).value(),
                // //     .status_buffer = this->device.get_device_address(status_buffer).value(),
                // //     .instance_buffer = this->device.get_device_address(instance_buffer).value(),
                // //     .primitives_buffer = this->device.get_device_address(primitive_buffer).value(),
                // //     .aabb_buffer = this->device.get_device_address(aabb_buffer).value(),
                // //     .materials_buffer = this->device.get_device_address(material_buffer).value(),
                // //     .light_buffer = this->device.get_device_address(light_buffer).value(),
                // //     .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
                // //     .velocity_buffer = this->device.get_device_address(velocity_buffer).value(),
                // //     .previous_di_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(previous_direct_illum_buffer).value() : this->device.get_device_address(direct_illum_buffer).value(),
                // //     .di_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(direct_illum_buffer).value() : this->device.get_device_address(previous_direct_illum_buffer).value(),
                // //     .previous_reservoir_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(previous_reservoir_buffer).value() : this->device.get_device_address(reservoir_buffer).value(),
                // //     .reservoir_buffer = (status.frame_number % 2) == 0 ? this->device.get_device_address(reservoir_buffer).value() : this->device.get_device_address(previous_reservoir_buffer).value(),
                // // });

                // // recorder.dispatch({
                // //     .x = width,
                // //     .y = height,
                // //     .z = 1,
                // // });

                // // recorder.pipeline_barrier({
                // //     .src_access = daxa::AccessConsts::COMPUTE_SHADER_WRITE,
                // //     .dst_access = daxa::AccessConsts::TRANSFER_READ,
                // // });

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


            // void compute_motion_vectors() {

            //     size_t previous_matrices = sizeof(daxa_f32mat4x4) * 2;
            //     daxa_u32 width = size_x;
            //     daxa_u32 height = size_y;

            //     daxa_u32 frame = (status.frame_number - 1);

            //      /// Record build commands:
            //     auto exec_cmds = [&]()
            //     {

            //         auto recorder = device.create_command_recorder({});
            //         recorder.set_pipeline(*compute_motion_vectors_pipeline);
            //         recorder.push_constant(PushConstant{
            //             .size = {width, height},
            //             .tlas = tlas,
            //             .camera_buffer = this->device.get_device_address(cam_buffer).value(),
            //             .status_buffer = this->device.get_device_address(status_buffer).value(),
            //             .instance_buffer = this->device.get_device_address(instance_buffer).value(),
            //             .primitives_buffer = this->device.get_device_address(primitive_buffer).value(),
            //             .aabb_buffer = this->device.get_device_address(aabb_buffer).value(),
            //             .materials_buffer = this->device.get_device_address(material_buffer).value(),
            //             .light_buffer = this->device.get_device_address(light_buffer).value(),
            //             .status_output_buffer = this->device.get_device_address(status_output_buffer).value(),
            //             .velocity_buffer = this->device.get_device_address(velocity_buffer).value(),
            //             .previous_di_buffer = (frame % 2) == 0 ? this->device.get_device_address(previous_direct_illum_buffer).value() : this->device.get_device_address(direct_illum_buffer).value(),
            //             .di_buffer = (frame % 2) == 0 ? this->device.get_device_address(direct_illum_buffer).value() : this->device.get_device_address(previous_direct_illum_buffer).value(),
            //             .previous_reservoir_buffer = (frame % 2) == 0 ? this->device.get_device_address(previous_reservoir_buffer).value() : this->device.get_device_address(reservoir_buffer).value(),
            //             .reservoir_buffer = (frame % 2) == 0 ? this->device.get_device_address(reservoir_buffer).value() : this->device.get_device_address(previous_reservoir_buffer).value(),
            //         });

            //         recorder.dispatch({
            //             .x = width,
            //             .y = height,
            //             .z = 1,
            //         });

            //         recorder.pipeline_barrier({
            //             .src_access = daxa::AccessConsts::COMPUTE_SHADER_WRITE,
            //             .dst_access = daxa::AccessConsts::TRANSFER_READ,
            //         });
                    
            //         recorder.copy_buffer_to_buffer({
            //             .src_buffer = cam_buffer,
            //             .dst_buffer = cam_buffer,
            //             .src_offset = 0,
            //             .dst_offset = cam_buffer_size - previous_matrices,
            //             .size = previous_matrices,
            //         });

            //         recorder.pipeline_barrier({
            //             .src_access = daxa::AccessConsts::TRANSFER_WRITE,
            //             .dst_access = daxa::AccessConsts::HOST_READ,
            //         });
            //         return recorder.complete_current_commands();
            //     }();

            //     // WAIT FOR COMMANDS TO FINISH
            //     {
            //         device.submit_commands({
            //             .command_lists = std::array{exec_cmds},
            //         });

            //         device.wait_idle();
            //     }
            // }

            // void update_status() {
            //     // Update status
            //     {
            //         // Update/restore status
            //         status.frame_number++;
            //         status.num_accumulated_frames++;
            //     }
            // }

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
                    << " distance " << status_output.hit_distance << " exit " << status_output.exit_distance
                    << " position [" << status_output.hit_position.x << ", " << status_output.hit_position.y << ", " << status_output.hit_position.z << "]" 
                    << " normal [" << status_output.hit_normal.x << ", " << status_output.hit_normal.y << ", " << status_output.hit_normal.z << "]"
                    << " origin [" << status_output.origin.x << ", " << status_output.origin.y << ", " << status_output.origin.z << "]"
                    << " direction [" << status_output.direction.x << ", " << status_output.direction.y << ", " << status_output.direction.z << "]" 
                    << " primitive center [" << status_output.primitive_center.x << ", " << status_output.primitive_center.y << ", " << status_output.primitive_center.z << "]"
                    << " material_index " << status_output.material_index << ", uv [" << status_output.uv.x << ", " << status_output.uv.y << "]" 
                    << std::endl;
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
                //                 daxa_f32mat3x2 min_max = daxa_f32mat3x2({center.x - VOXEL_EXTENT, center.y - VOXEL_EXTENT, center.z - VOXEL_EXTENT}, {center.x + VOXEL_EXTENT, center.y + VOXEL_EXTENT, center.z + VOXEL_EXTENT});
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
    tests::ray_querry_triangle();
    return 0;
}
