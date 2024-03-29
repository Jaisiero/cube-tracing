#include <algorithm>
#include <thread>

#include <daxa/utils/pipeline_manager.hpp>
#include <daxa/utils/task_graph.hpp>

#include "defines.h"

#include <map_loader.hpp>
#include <accel_struct_mngr.hpp>

#include "rng.h"
#include "camera.h"
#include "texture.hpp"

using namespace std::chrono_literals;
using Clock = std::chrono::high_resolution_clock;
using TASK = ACCEL_STRUCT_MNGR::TASK;
namespace tests
{
  void cubeland_app()
  {
    struct App : AppWindow<App>
    {
      const char *RED_BRICK_WALL_IMAGE = "red_brick_wall.jpg";
      const char *MODEL_PATH = "assets/models/";
      // const char *MAP_NAME = "monu5.vox";
      // const char *MAP_NAME = "monu6.vox";
      // const char *MAP_NAME = "monu9.vox";
      const char *MAP_NAME = "room.vox";
      const float day_duration = 60.0f; // Duración de un día en segundos

      Clock::time_point start_time = std::chrono::steady_clock::now(), previous_time = start_time;
      Status status = {};
      camera camera = {};
      LIGHT_CONFIG *light_config = nullptr;

      daxa_u32 invocation_reorder_mode;
      daxa_b32 activate_filtering = false;
      daxa_b32 activate_day_night_cycle = false;
      daxa_b32 activate_point_lights = true;
      daxa_b32 activate_env_map = true;
      daxa_b32 activate_cube_lights = true;
      daxa_b32 activate_brdf = false;
      daxa_b32 activate_midday = false;
      daxa_b32 activate_sun_light = false;
      daxa_b32 building_mode = false;

      // Vulkan objects
      daxa::Instance daxa_ctx = {};
      daxa::Device device = {};
      // swapchain
      daxa::Swapchain swapchain = {};
      daxa::ImageId previous_frame = {};
      // TAA images
      daxa::ImageId taa_image[2] = {};
      // Pipelines
      daxa::PipelineManager pipeline_manager = {};
      std::shared_ptr<daxa::RayTracingPipeline> rt_pipeline = {};
      std::shared_ptr<daxa::ComputePipeline> compute_motion_vectors_pipeline = {};

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

      daxa::BufferId material_buffer = {};
      size_t max_material_buffer_size = sizeof(MATERIAL) * MAX_MATERIALS;

      daxa::BufferId point_light_buffer = {}, env_light_buffer = {};
      size_t max_point_light_buffer_size = sizeof(LIGHT) * MAX_POINT_LIGHTS;
      size_t max_env_light_buffer_size = sizeof(LIGHT) * MAX_ENV_LIGHTS;

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

      u32 current_material_count = 0;
      std::unique_ptr<MATERIAL[]> materials = {};

      // lights data from mapped buffer
      LIGHT *point_lights = nullptr;
      LIGHT *env_lights = nullptr;

      // std::vector<daxa_f32mat4x4> transforms = {};

      MapLoader map_loader = {};
      std::unique_ptr<ACCEL_STRUCT_MNGR> as_manager = {};

      App() : AppWindow<App>("Cubeland") {}

      ~App()
      {
        map_loader.destroy_gvox_context();
        device.wait_idle();
        device.collect_garbage();
        if (device.is_valid())
        {
          as_manager->destroy();
          device.destroy_buffer(light_config_buffer);
          device.destroy_buffer(cam_buffer);
          device.destroy_buffer(material_buffer);
          device.destroy_buffer(point_light_buffer);
          device.destroy_buffer(env_light_buffer);
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
          // DEBUGGING
          // device.destroy_buffer(hit_distance_buffer);
          for (auto image : taa_image)
            device.destroy_image(image);
        }
      }

      daxa_f32vec3 interpolate_sun_light(float t, bool is_afternoon)
      {
        // Definir las posiciones clave para el medio día y el atardecer
        glm::vec3 middayPosition = glm::vec3(SUN_TOP_POSITION_X, SUN_TOP_POSITION_Y, SUN_TOP_POSITION_Z);
        glm::vec3 sunsetPosition = glm::vec3(20.0, 0.0, 0.0); // Modificar la posición del atardecer

        // Calcular las coordenadas elípticas basadas en el tiempo
        float angle = t * 2.0 * 3.14159; // Ángulo en radianes
        float ellipseRadiusX = 100.0;    // Radio en el eje X
        float ellipseRadiusY = 50.0;     // Radio en el eje Y

        float x = ellipseRadiusX * cos(angle);
        float y = ellipseRadiusY * sin(angle);

        // Interpolación elíptica desde mediodía hasta atardecer
        glm::vec3 interpolatedPosition;
        if (is_afternoon)
        {
          // Atardecer: t=0.0 -> posición = sunsetPosition
          // Mediodía: t=1.0 -> posición = middayPosition
          interpolatedPosition = glm::mix(sunsetPosition, middayPosition, t);
        }
        else
        {
          // Atardecer: t=1.0 -> posición = middayPosition
          // Mediodía: t=0.0 -> posición = -sunsetPosition
          interpolatedPosition = glm::mix(-sunsetPosition, middayPosition, t);
        }

        daxa_f32vec3 position = daxa_f32vec3(interpolatedPosition.x, interpolatedPosition.y, interpolatedPosition.z);

        // Ajustar la posición según la hora del día
        return position;
      }

      daxa_f32 interpolate_sun_intensity(float time, bool is_afternoon, float max_intensity, float min_intensity)
      {
        const daxa_f32 maxIntensityStartTime = 0.5;
        const daxa_f32 minIntensityEndTime = 0.5;

        float i = 0;

        if (time >= maxIntensityStartTime)
        {
          i = glm::mix(0.0f, max_intensity, time); // Adjust the range as needed
        }
        else
        {
          i = 0;
        }

        return i;
      }

      void load_reservoirs()
      {

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

      bool check_light_count(uint32_t max_light_count, uint32_t current_light_count)
      {
        if (current_light_count + 1 > max_light_count)
        {
          std::cout << "light_config->light_count > MAX_LIGHTS" << std::endl;
          return false;
        }
        return true;
      }

      void set_midday(bool midday_activated, LIGHT &light)
      {
        if (midday_activated)
        {
          light.position = daxa_f32vec3(SUN_TOP_POSITION_X, SUN_TOP_POSITION_Y, SUN_TOP_POSITION_Z);
          light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY, SUN_MAX_INTENSITY, SUN_MAX_INTENSITY);
          status.time = 1.0;
          status.is_afternoon = true;
        }
        else
        {
          light.position = daxa_f32vec3(SUN_TOP_POSITION_X, -SUN_TOP_POSITION_Y, SUN_TOP_POSITION_Z);
          light.emissive = daxa_f32vec3(0.0, 0.0, 0.0);
          status.time = 0.0;
          status.is_afternoon = false;
        }
      }

      bool create_point_lights()
      {
        // TODO: add more lights (random values?)

        if (!point_lights)
        {
          std::cout << "lights is nullptr" << std::endl;
          return false;
        }

        if (!check_light_count(MAX_POINT_LIGHTS, light_config->point_light_count))
        {
          std::cout << "light_config->light_count > MAX_LIGHTS" << std::endl;
          return false;
        }

        LIGHT light = {}; // 0: point light, 1: directional light
        light.position = daxa_f32vec3(SUN_TOP_POSITION_X, SUN_TOP_POSITION_Y, SUN_TOP_POSITION_Z);
        // #if DYNAMIC_SUN_LIGHT == 1
        //                 light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2, SUN_MAX_INTENSITY * 0.2);
        // #else
        // #if SUN_MIDDAY == 1
        light.emissive = daxa_f32vec3(SUN_MAX_INTENSITY, SUN_MAX_INTENSITY, SUN_MAX_INTENSITY);
        status.time = 1.0;
        status.is_afternoon = true;
        // #else
        //                 light.emissive = daxa_f32vec3(0.0, 0.0, 0.0);
        //                 status.time = 0.0;
        //                 status.is_afternoon = false;
        // #endif

        // #endif // DYNAMIC_SUN_LIGHT
        light.type = GEOMETRY_LIGHT_POINT;
        light.instance_info = OBJECT_INFO(INVALID_ID, INVALID_ID);
        point_lights[light_config->point_light_count++] = light;

        // LIGHT light2 = {};
        // light2.position = daxa_f32vec3( -AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.5f, 1.0, 0.0001);
        // light2.emissive = daxa_f32vec3(3.0, 3.0, 3.0);
        // light2.type = GEOMETRY_LIGHT_POINT;
        // point_lights[light_config->point_light_count++] = light2;

        // LIGHT light3 = {};
        // light3.position = daxa_f32vec3(AXIS_DISPLACEMENT * INSTANCE_X_AXIS_COUNT * 1.0f, 1.0, 0.0001);
        // light3.emissive = daxa_f32vec3(4.0, 4.0, 4.0);
        // light3.type = GEOMETRY_LIGHT_POINT;
        // point_lights[light_config->point_light_count++] = light3;

        return true;
      }

      bool create_environment_light()
      {
        if (!check_light_count(MAX_ENV_LIGHTS, light_config->env_map_count))
        {
          std::cout << "light_config->light_count > MAX_LIGHTS" << std::endl;
          return false;
        }

        LIGHT light = {};
        light.type = GEOMETRY_LIGHT_ENV_MAP;
        light.instance_info = OBJECT_INFO(INVALID_ID, INVALID_ID);
        light.position = daxa_f32vec3(0.0, 0.0, 0.0);
        light.emissive = daxa_f32vec3(5.0, 5.0, 5.0);
        light.size = 0.f;
        env_lights[light_config->env_map_count++] = light;

        return true;
      }

      void load_lights()
      {

        light_config->light_count = light_config->point_light_count + light_config->cube_light_count + light_config->sphere_light_count + light_config->analytic_light_count + light_config->env_map_count;

        light_config->point_light_pdf = light_config->point_light_count == 0 ? 0.f : (light_config->point_light_count / light_config->light_count);
        light_config->cube_light_pdf = light_config->cube_light_count == 0 ? 0.f : (light_config->cube_light_count / light_config->light_count);
        light_config->sphere_light_pdf = light_config->sphere_light_count == 0 ? 0.f : (light_config->sphere_light_count / light_config->light_count);
        light_config->analytic_light_pdf = light_config->analytic_light_count == 0 ? 0.f : (light_config->analytic_light_count / light_config->light_count);
        light_config->env_map_pdf = light_config->env_map_count == 0 ? 0.f : (light_config->env_map_count / light_config->light_count);
        light_config->brdf_pdf = light_config->brdf_count == 0 ? 0.f : (light_config->brdf_count / (light_config->cube_light_count + light_config->sphere_light_count));

        std::cout << "Num of lights: " << light_config->light_count << std::endl;
        std::cout << "  Num of point lights: " << light_config->point_light_count << std::endl;
        std::cout << "  Num of cube lights: " << light_config->cube_light_count << std::endl;
        std::cout << "  Num of environment map lights: " << light_config->env_map_count << std::endl;
        std::cout << "  Num of brdf lights: " << light_config->brdf_count << std::endl;
        std::cout << "  Num of sphere lights: " << light_config->sphere_light_count << std::endl;

        status.light_config_address = device.get_device_address(light_config_buffer).value();
      }

      void add_time(float time)
      {
        // Increment or decrement time
        status.time += time * (status.is_afternoon ? 1.0 : -1.0);
      }

      void update_time_and_sun_light()
      {
        if (activate_day_night_cycle)
        {
          update_time();
          if (activate_sun_light && point_lights)
          {
            update_sun_light();
          }
        }
      }

      void add_time_and_sun_light(daxa_f32 time)
      {
        if (!activate_day_night_cycle)
        {
          add_time(time);
          if (activate_sun_light && point_lights)
          {
            update_sun_light();
          }
        }
      }

      void update_time()
      {

        if (light_config->light_count == 0 || light_config->point_light_count == 0)
        {
          return;
        }

        if (light_config->point_light_count > MAX_POINT_LIGHTS)
        {
          std::cout << "current_light_count > MAX_LIGHTS" << std::endl;
          abort();
        }

        // Speed of time progression
        previous_time = start_time;

        start_time = std::chrono::steady_clock::now();

        auto time = std::chrono::duration<float>(start_time - previous_time).count();

        time = std::fmod(time / day_duration, 1.0f);

        // Increment or decrement time
        add_time(time);
      }

      void update_sun_light()
      {

        // Check for boundaries and reverse direction if needed
        if (status.time < 0.0 || status.time > 1.0)
        {
          status.is_afternoon = !status.is_afternoon;
          status.time = std::clamp(status.time, 0.0f, 1.0f);
        }

        point_lights[0].position = interpolate_sun_light(status.time, status.is_afternoon);
        daxa_f32 intensity = interpolate_sun_intensity(status.time, status.is_afternoon, SUN_MAX_INTENSITY /*max_intensity*/, 0.0f /*min_intensity*/);
        point_lights[0].emissive = daxa_f32vec3(intensity, intensity, intensity);
      }

      daxa_Bool8 load_materials(daxa_Bool8 synchronize)
      {
        // TODO: Refactor materials copies
        daxa_u32 material_buffer_size = static_cast<u32>(current_material_count * sizeof(MATERIAL));
        if (material_buffer_size > max_material_buffer_size)
        {
          std::cout << "material_buffer_size > max_material_buffer_size" << std::endl;
          abort();
        }

        auto material_staging_buffer = device.create_buffer({
            .size = material_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("material_staging_buffer"),
        });
        defer { device.destroy_buffer(material_staging_buffer); };

        auto *material_buffer_ptr = device.get_host_address_as<MATERIAL>(material_staging_buffer).value();
        std::memcpy(material_buffer_ptr,
                    materials.get(),
                    material_buffer_size);

        /// Record build commands:
        auto exec_cmds = [&]()
        {
          auto recorder = device.create_command_recorder({});

          recorder.copy_buffer_to_buffer({
              .src_buffer = material_staging_buffer,
              .dst_buffer = material_buffer,
              .size = material_buffer_size,
          });

          return recorder.complete_current_commands();
        }();
        device.submit_commands({.command_lists = std::array{exec_cmds}});
        if (synchronize)
        {
          device.wait_idle();
        }

        return true;
      }

      void upload_world()
      {

        // get world buffer host mapped pointer

        world.instance_address = device.get_device_address(as_manager->get_current_instance_buffer()).value();
        world.instance_address_prev = device.get_device_address(as_manager->get_previous_instance_buffer()).value();
        world.primitive_address = device.get_device_address(as_manager->get_current_primitive_buffer()).value();
        world.primitive_address_prev = device.get_device_address(as_manager->get_previous_primitive_buffer()).value();
        world.aabb_address = device.get_device_address(as_manager->get_current_aabb_buffer()).value();
        world.aabb_address_prev = device.get_device_address(as_manager->get_previous_aabb_buffer()).value();
        world.remapped_primitive_address = device.get_device_address(as_manager->get_remapping_primitive_buffer()).value();
        world.remapped_cube_light_address = device.get_device_address(as_manager->get_remapping_light_buffer()).value();
        world.material_address = device.get_device_address(material_buffer).value();
        world.point_light_address = device.get_device_address(point_light_buffer).value();
        world.cube_light_address = device.get_device_address(as_manager->get_cube_light_buffer()).value();
        world.env_light_address = device.get_device_address(env_light_buffer).value();

        // copy world to buffer

        daxa_u32 world_buffer_size = sizeof(WORLD);

        auto world_staging_buffer = device.create_buffer({
            .size = world_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("world_staging_buffer"),
        });
        defer { device.destroy_buffer(world_staging_buffer); };

        auto *world_buffer_ptr = device.get_host_address_as<WORLD>(world_staging_buffer).value();
        std::memcpy(world_buffer_ptr,
                    &world,
                    world_buffer_size);

        /// Record build commands:
        auto exec_cmds = [&]()
        {
          auto recorder = device.create_command_recorder({});
          recorder.copy_buffer_to_buffer({
              .src_buffer = world_staging_buffer,
              .dst_buffer = world_buffer,
              .size = world_buffer_size,
          });

          return recorder.complete_current_commands();
        }();
        device.submit_commands({.command_lists = std::array{exec_cmds}});
        device.wait_idle();
      }

      void upload_restir()
      {

        // get restir buffer host mapped pointer
        auto *restir_buffer_ptr = device.get_host_address(restir_buffer).value();

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

      // // TODO: This could be load from a file
      // daxa_Bool8 create_procedural_blas() {

      //     u32 instance_count_x = (INSTANCE_X_AXIS_COUNT * 2);
      //     u32 instance_count_z = (INSTANCE_Z_AXIS_COUNT * 2);

      //     daxa_u32 estimated_instance_count = (instance_count_x * instance_count_z + CLOUD_INSTANCE_COUNT_X) * CHUNK_VOXEL_COUNT;

      //     if (estimated_instance_count > INVALID_ID)
      //     {
      //         std::cout << "estimated_instance_count (" << estimated_instance_count << ") > INVALID_ID (" << INVALID_ID << ")." << std::endl;
      //         abort();
      //     }

      //     if (estimated_instance_count == 0)
      //     {
      //         std::cout << "estimated_instance_count == 0" << std::endl;
      //         abort();
      //     }

      //     transforms.reserve(estimated_instance_count);

      //     // Centered around 0, 0, 0 positioning instances like a mirror
      //     f32 x_axis_initial_position = ((INSTANCE_X_AXIS_COUNT)*AXIS_DISPLACEMENT / 2);
      //     f32 z_axis_initial_position = ((INSTANCE_Z_AXIS_COUNT)*AXIS_DISPLACEMENT / 2);

      //     for (i32 x_instance = -INSTANCE_X_AXIS_COUNT; x_instance < (i32)INSTANCE_X_AXIS_COUNT; x_instance++)
      //     {
      //         auto x_instance_displacement = (x_instance * (AXIS_DISPLACEMENT));
      //         for (i32 z_instance = -INSTANCE_Z_AXIS_COUNT; z_instance < (i32)INSTANCE_Z_AXIS_COUNT; z_instance++)
      //         {
      //             auto z_instance_displacement = (z_instance * (AXIS_DISPLACEMENT));
      //             for (u32 z = 0; z < VOXEL_COUNT_BY_AXIS; z++)
      //             {
      //                 for (u32 y = 0; y < VOXEL_COUNT_BY_AXIS; y++)
      //                 {
      //                     for (u32 x = 0; x < VOXEL_COUNT_BY_AXIS; x++)
      //                     {
      //                         // if(random_float(0.0, 1.0) > 0.95) {
      //                         if (random_float(0.0, 1.0) > 0.75)
      //                         {
      //                             auto position_instance = generate_center_by_coord(x, y, z, CHUNK_EXTENT);
      //                             transforms.push_back(daxa_f32mat4x4{
      //                                 {1, 0, 0, x_instance_displacement + position_instance.x},
      //                                 {0, 1, 0, position_instance.y},
      //                                 {0, 0, 1, z_instance_displacement + position_instance.z},
      //                                 {0, 0, 0, 1},
      //                             });
      //                         }
      //                     }
      //                 }
      //             }
      //         }
      //     }
      //     // transforms.push_back(daxa_f32mat4x4{
      //     //     {1, 0, 0, -AXIS_DISPLACEMENT},
      //     //     {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_Z_AXIS_COUNT},
      //     //     {0, 0, 1, 0},
      //     //     {0, 0, 0, 1},
      //     // });

      //     // transforms.push_back(daxa_f32mat4x4{
      //     //     {1, 0, 0, 0},
      //     //     {0, 1, 0, AXIS_DISPLACEMENT  * INSTANCE_X_AXIS_COUNT},
      //     //     {0, 0, 1, 0},
      //     //     {0, 0, 0, 1},
      //     // });

      //     current_instance_count[0] = transforms.size();

      //     // upload_textures();

      //     return true;
      // }

      // bool create_materials() {

      //     current_material_count = 0;

      //     for (u32 i = 0; i < LAMBERTIAN_MATERIAL_COUNT; i++)
      //     {

      //         daxa_u32 texture_id = MAX_TEXTURES;
      //         // daxa_f32 random_float_value = random_float(0.0, 1.0);
      //         // if (random_float_value > 0.80)
      //         // {
      //         //     texture_id = random_uint(0, current_texture_count - 1);
      //         // }

      //         materials[current_material_count++] = MATERIAL{
      //             .type = MATERIAL_TYPE_LAMBERTIAN,
      //             .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .diffuse = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .transmittance = {0.0f, 0.0f, 0.0f},
      //             .emission = {0.0, 0.0, 0.0},
      //             .shininess = random_float(0.0, 4.0),
      //             .roughness = random_float(0.0, 1.0),
      //             .ior = random_float(1.0, 2.65),
      //             // .dissolve = (-1/random_float(0.1, 1.0)),
      //             // .dissolve = (random_float(0.1, 1.0)),
      //             .dissolve = 1.0,
      //             .illum = 3
      //         };
      //     }

      //     for (u32 i = 0; i < METAL_MATERIAL_COUNT; i++)
      //     {
      //         materials[current_material_count++] = MATERIAL{
      //             .type = MATERIAL_TYPE_METAL,
      //             .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .diffuse = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .transmittance = {0.0f, 0.0f, 0.0f},
      //             .emission = {0.0, 0.0, 0.0},
      //             .shininess = random_float(0.0, 4.0),
      //             .roughness = random_float(0.0, 1.0),
      //             .ior = random_float(1.0, 2.65),
      //             // .dissolve = (-1/random_float(0.1, 1.0)),
      //             // .dissolve = (random_float(0.1, 1.0)),
      //             .dissolve = 1.0,
      //             .illum = 3
      //         };
      //     }

      //     for (u32 i = 0; i < DIALECTRIC_MATERIAL_COUNT; i++)
      //     {
      //         materials[current_material_count++] = MATERIAL{
      //             .type = MATERIAL_TYPE_DIELECTRIC,
      //             .ambient = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .diffuse = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .specular = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .transmittance = {0.0f, 0.0f, 0.0f},
      //             .emission = {0.0, 0.0, 0.0},
      //             .shininess = random_float(0.0, 4.0),
      //             .roughness = random_float(0.0, 1.0),
      //             .ior = random_float(1.0, 2.65),
      //             .dissolve = 1.0,
      //             .illum = 3
      //         };
      //     }

      //     for (u32 i = 0; i < EMISSIVE_MATERIAL_COUNT; i++)
      //     {
      //         materials[current_material_count++] = MATERIAL{
      //             .type = MATERIAL_TYPE_LAMBERTIAN,
      //             .ambient = {1.0, 1.0, 1.0},
      //             .diffuse = {random_float(0.001, 0.999), random_float(0.001, 0.999), random_float(0.001, 0.999)},
      //             .specular = {1.0, 1.0, 1.0},
      //             .transmittance = {0.0, 0.0, 0.0},
      //             .emission = {random_float(10.0, 20.0), random_float(10.0, 20.0), random_float(10.0, 20.0)},
      //             .shininess = random_float(0.0, 4.0),
      //             .roughness = random_float(0.0, 1.0),
      //             .ior = random_float(1.0, 2.65),
      //             .dissolve = 1.0,
      //             .illum = 3
      //         };
      //     }

      //     for (u32 i = 0; i < CONSTANT_MEDIUM_MATERIAL_COUNT; i++)
      //     {
      //         materials[current_material_count++] = MATERIAL{
      //             .type = MATERIAL_TYPE_CONSTANT_MEDIUM,
      //             .ambient = {0.999, 0.999, 0.999},
      //             .diffuse = {0.999, 0.999, 0.999},
      //             .specular = {0.999, 0.999, 0.999},
      //             .transmittance = {random_float(0.9, 0.999), random_float(0.9, 0.999), random_float(0.9, 0.999)},
      //             .emission = {0.0, 0.0, 0.0},
      //             .shininess = random_float(0.0, 4.0),
      //             .roughness = random_float(0.0, 1.0),
      //             .ior = random_float(1.0, 2.65),
      //             // .dissolve = (-1.0f/random_float(0.1, 0.5)),
      //             .dissolve = random_float(0.1, 0.3),
      //             .illum = 4
      //         };
      //     }

      //     return true;
      // }

      void initialize()
      {
        daxa_ctx = daxa::create_instance({});
        device = daxa_ctx.create_device({
            .selector = [](daxa::DeviceProperties const &prop) -> i32
            {
              auto value = daxa::default_device_score(prop);
              return prop.ray_tracing_properties.has_value() ? value : -1;
            },
            .flags = daxa::DeviceFlagBits::RAY_TRACING,
        });

        bool ray_tracing_supported = device.properties().ray_tracing_properties.has_value();
        invocation_reorder_mode = device.properties().invocation_reorder_properties.has_value() ? device.properties().invocation_reorder_properties.value().invocation_reorder_mode : 0;
        std::string ray_tracing_supported_str = ray_tracing_supported ? "available" : "not available";

        std::cout << "Choosen Device: " << device.properties().device_name << ", Ray Tracing: " << ray_tracing_supported_str << ", Invocation Reordering mode: " << invocation_reorder_mode << std::endl;

        if (ray_tracing_supported == false)
        {
          std::cout << "Ray tracing is not supported" << std::endl;
          abort();
        }

        // acceleration_structure_scratch_offset_alignment = device.properties().acceleration_structure_properties.value().min_acceleration_structure_scratch_offset_alignment;

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

        taa_image[0] = device.create_image({
            .format = swapchain.get_format(),
            .size = {swapchain.get_surface_extent().x, swapchain.get_surface_extent().y, 1},
            .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE,
            .name = "taa_image_0",
        });

        taa_image[1] = device.create_image({
            .format = swapchain.get_format(),
            .size = {swapchain.get_surface_extent().x, swapchain.get_surface_extent().y, 1},
            .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE,
            .name = "taa_image_1",
        });

        light_config_buffer = device.create_buffer(daxa::BufferInfo{
            .size = light_config_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
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

        material_buffer = device.create_buffer(daxa::BufferInfo{
            .size = max_material_buffer_size,
            .name = ("material_buffer"),
        });

        point_light_buffer = device.create_buffer(daxa::BufferInfo{
            .size = max_point_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("light_buffer"),
        });

        env_light_buffer = device.create_buffer(daxa::BufferInfo{
            .size = max_env_light_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("env_light_buffer"),
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

        // hit_distance_buffer = device.create_buffer(daxa::BufferInfo{
        //     .size = max_hit_distance_buffer_size,
        //     .name = ("hit_distance_buffer"),
        // });

        // DEBUGGING
        // hit_distances.resize(WIDTH_RES * HEIGHT_RES);

        light_config = device.get_host_address_as<LIGHT_CONFIG>(light_config_buffer).value();

        light_config->light_count = light_config->point_light_count = light_config->cube_light_count = light_config->env_map_count = 0;

        point_lights = device.get_host_address_as<LIGHT>(point_light_buffer).value();
        env_lights = device.get_host_address_as<LIGHT>(env_light_buffer).value();
        

        as_manager = std::make_unique<ACCEL_STRUCT_MNGR>(device);
        as_manager->create(MAX_INSTANCES, MAX_PRIMITIVES, MAX_CUBE_LIGHTS, &light_config->cube_light_count);

        status.time = 1.0;
        status.is_afternoon = true;
#if POINT_LIGHT_ON == 1
        activate_sun_light = true;
        if (!create_point_lights())
        {
          std::cout << "Failed to create point lights" << std::endl;
          abort();
        }
#endif
        if (!create_environment_light())
        {
          std::cout << "Failed to create environment light" << std::endl;
          abort();
        }

        status.brush_counter_address = device.get_device_address(as_manager->get_brush_counter_buffer()).value();
        status.instance_bitmask_address = device.get_device_address(as_manager->get_brush_instance_bitmask_buffer()).value();
        status.primitive_bitmask_address = device.get_device_address(as_manager->get_brush_primitive_bitmask_buffer()).value();


        materials = std::make_unique<MATERIAL[]>(MAX_MATERIALS);

        // Create a new context for the gvox library
        map_loader.create_gvox_context();

        GvoxModelDataSerialize gvox_map_serialize = {
            .axis_direction = AXIS_DIRECTION::X_BOTTOM_TOP,
            .max_instance_count = MAX_INSTANCES,
            .instances = as_manager->get_instances(),
            .max_primitive_count = MAX_PRIMITIVES,
            .primitives = as_manager->get_primitives(),
            .aabbs = device.get_host_address_as<AABB>(as_manager->get_aabb_host_buffer()).value(),
            .max_material_count = MAX_MATERIALS,
            .materials = materials.get(),
            .max_light_count = MAX_CUBE_LIGHTS - light_config->cube_light_count,
            .lights = &as_manager->get_cube_lights()[light_config->cube_light_count],
        };

        // load map
        GvoxModelData gvox_map = map_loader.load_gvox_data(std::string(MODEL_PATH) + "/" + MAP_NAME, gvox_map_serialize);

        std::cout << "gvox_map" << std::endl;
        std::cout << "  instances: " << gvox_map.instance_count << std::endl;
        std::cout << "  primitives: " << gvox_map.primitive_count << std::endl;
        std::cout << "  materials: " << gvox_map.material_count << std::endl;

        current_material_count += gvox_map.material_count;
        light_config->cube_light_count += gvox_map.light_count;

        if (light_config->cube_light_count > 0)
        {
          light_config->brdf_count = BRDF_SAMPLING_COUNT;
        }

        load_materials(false);

        as_manager->task_queue_add(TASK{
            .type = TASK::TYPE::BUILD_BLAS_FROM_CPU,
            .blas_build_from_cpu = {.instance_count = gvox_map.instance_count,
                                    .primitive_count = gvox_map.primitive_count},
        });

        // Update the scene
        as_manager->update_scene(true);
        
        upload_world();
        upload_restir();

        // if (!as_manager->build_new_blas(0, false))
        // {
        //   std::cout << "Failed to build blas" << std::endl;
        //   abort();
        // }

        // if (!as_manager->build_tlas(0, false))
        // {
        //   std::cout << "Failed to build tlas" << std::endl;
        //   abort();
        // }

        // if (!as_manager->build_tlas(1, true))
        // {
        //   std::cout << "Failed to build tlas" << std::endl;
        //   abort();
        // }

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
                "src/shaders/restir_di",
            },
            .write_out_preprocessed_code = "build/Debug",
            .write_out_shader_binary = "build/Debug",
            .enable_debug_info = false,
        };

        auto rgen_restir_prepass_selection_compile_options = rt_shader_compile_options;
        rgen_restir_prepass_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"RESTIR_PREPASS_AND_FIRST_VISIBILITY_TEST", "1"}};
        if (invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER))
        {
          rgen_restir_prepass_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
        }

        // NOTE: splitting the restir prepass and the first visibility impacts performance
        // auto rgen_restir_first_vis_test_selection_compile_options = rt_shader_compile_options;
        // rgen_restir_first_vis_test_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"FIRST_VISIBILITY_TEST", "1"}};

        auto rgen_restir_temp_reuse_selection_compile_options = rt_shader_compile_options;
        rgen_restir_temp_reuse_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"TEMPORAL_REUSE_PASS", "1"}};
        if (invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER))
        {
          rgen_restir_temp_reuse_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
        }

        // It doesn't improve visual quality too much
        // auto rgen_restir_second_vis_test_selection_compile_options = rt_shader_compile_options;
        // rgen_restir_second_vis_test_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"SECOND_VISIBILITY_TEST", "1"}};

        auto rgen_restir_spatial_reuse_selection_compile_options = rt_shader_compile_options;
        rgen_restir_spatial_reuse_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"SPATIAL_REUSE_PASS", "1"}};
        if (invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER))
        {
          rgen_restir_spatial_reuse_selection_compile_options.defines.push_back(daxa::ShaderDefine{"SER", "1"});
        }

        auto rgen_restir_shading_selection_compile_options = rt_shader_compile_options;
        rgen_restir_shading_selection_compile_options.defines = std::vector{daxa::ShaderDefine{"THIRD_VISIBILITY_TEST_AND_SHADING_PASS", "1"}};
        if (invocation_reorder_mode == static_cast<daxa_u32>(daxa::InvocationReorderMode::ALLOW_REORDER))
        {
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
                                                                                })
                                              .value();
      }

      auto update() -> bool
      {
        auto reload_result = pipeline_manager.reload_all();

        if (auto *reload_err = daxa::get_if<daxa::PipelineReloadError>(&reload_result))
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
#if POINT_LIGHT_ON == 1
          update_time_and_sun_light();
#endif // DYNAMIC_SUN_LIGHT == 1
          // Update the scene if needed
          as_manager->update_scene();
          upload_world();
          draw();
          download_gpu_info();
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

        auto *buffer_ptr = device.get_host_address_as<daxa_f32mat4x4>(cam_staging_buffer).value();
        std::memcpy(buffer_ptr,
                    &camera_view,
                    cam_update_size);

        // Update/restore status

        if (camera_get_moved(camera))
        {
          camera_reset_moved(camera);
          status.num_accumulated_frames = 0;
        }

        auto swapchain_image_view = swapchain_image.default_view();
        auto previous_swapchain_image_view = previous_frame.is_empty() ? swapchain_image_view : previous_frame.default_view();
        auto taa_image_view = taa_image[status.frame_number % 2].default_view();
        auto previous_taa_image_view = taa_image[(status.frame_number + 1) % 2].default_view();

        daxa_b32 filter_activated = previous_swapchain_image_view != swapchain_image_view && activate_filtering;

        if (activate_point_lights)
        {
          status.is_active += RIS_POINT_LIGHT_BIT;
        }

        if (activate_env_map)
        {
          status.is_active += RIS_ENV_LIGHT_BIT;
        }

        if (activate_cube_lights)
        {
          status.is_active += RIS_CUBE_LIGHT_BIT;
        }

        if (activate_brdf)
        {
          status.is_active += RIS_BRDF_BIT;
        }

        if(as_manager->is_switching())
        {
          status.is_active += REMAP_BIT;
        }

        if (filter_activated)
        {
          status.is_active += TAA_BIT;

          recorder.pipeline_barrier_image_transition({
              .dst_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
              .src_layout = daxa::ImageLayout::UNDEFINED,
              .dst_layout = daxa::ImageLayout::GENERAL,
              .image_id = previous_frame,
          });
        }

        auto status_staging_buffer = device.create_buffer({
            .size = status_buffer_size,
            .allocate_info = daxa::MemoryFlagBits::HOST_ACCESS_RANDOM,
            .name = ("status_staging_buffer"),
        });
        defer { device.destroy_buffer(status_staging_buffer); };

        auto *status_buffer_ptr = device.get_host_address_as<Status>(status_staging_buffer).value();
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
            .tlas = as_manager->get_current_tlas(),
            .tlas_previous = as_manager->get_previous_tlas(),
            .swapchain = swapchain_image_view,
            .previous_swapchain = previous_swapchain_image_view,
            .taa_frame = taa_image_view,
            .taa_prev_frame = previous_taa_image_view,
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
            .tlas = as_manager->get_current_tlas(),
            .tlas_previous = as_manager->get_previous_tlas(),
            .swapchain = swapchain_image_view,
            .previous_swapchain = previous_swapchain_image_view,
            .taa_frame = taa_image_view,
            .taa_prev_frame = previous_taa_image_view,
            .camera_buffer = this->device.get_device_address(cam_buffer).value(),
            .status_buffer = this->device.get_device_address(status_buffer).value(),
            .world_buffer = this->device.get_device_address(world_buffer).value(),
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
            .tlas = as_manager->get_current_tlas(),
            .tlas_previous = as_manager->get_previous_tlas(),
            .swapchain = swapchain_image_view,
            .previous_swapchain = previous_swapchain_image_view,
            .taa_frame = taa_image_view,
            .taa_prev_frame = previous_taa_image_view,
            .camera_buffer = this->device.get_device_address(cam_buffer).value(),
            .status_buffer = this->device.get_device_address(status_buffer).value(),
            .world_buffer = this->device.get_device_address(world_buffer).value(),
            .restir_buffer = this->device.get_device_address(restir_buffer).value(),
        });

        recorder.trace_rays({
            .width = width,
            .height = height,
            .depth = 1,
            .raygen_shader_binding_table_offset = 3,
        });

        if (filter_activated)
        {

          recorder.pipeline_barrier({
              .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
              .dst_access = daxa::AccessConsts::COMPUTE_SHADER_READ,
          });

          recorder.set_pipeline(*compute_motion_vectors_pipeline);

          recorder.push_constant(PushConstant{
              .size = {width, height},
              .tlas = as_manager->get_current_tlas(),
              .tlas_previous = as_manager->get_previous_tlas(),
              .swapchain = swapchain_image_view,
              .previous_swapchain = previous_swapchain_image_view,
              .taa_frame = taa_image_view,
              .taa_prev_frame = previous_taa_image_view,
              .camera_buffer = this->device.get_device_address(cam_buffer).value(),
              .status_buffer = this->device.get_device_address(status_buffer).value(),
              .world_buffer = this->device.get_device_address(world_buffer).value(),
              .restir_buffer = this->device.get_device_address(restir_buffer).value(),
          });

          recorder.dispatch({
              .x = width / 8,
              .y = height / 8,
              .z = 1,
          });

          recorder.pipeline_barrier({
              .src_access = daxa::AccessConsts::COMPUTE_SHADER_WRITE,
              .dst_access = daxa::AccessConsts::TRANSFER_READ,
          });
        }
        else
        {
          recorder.pipeline_barrier({
              .src_access = daxa::AccessConsts::RAY_TRACING_SHADER_WRITE,
              .dst_access = daxa::AccessConsts::TRANSFER_READ,
          });
        }

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
        previous_frame = swapchain_image;
      }

      void download_gpu_info()
      {
        as_manager->check_voxel_modifications();

#if (PERFECT_PIXEL_ON == 1)
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

        status.is_active = 0;
        status.pixel = {0, 0};
      }

      void on_mouse_move(f32 x, f32 y)
      {
        // Input mouse movement to camera
        // if (glfwGetMouseButton(glfw_window_ptr, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS)
        // {
        camera_set_mouse_delta(camera, glm::vec2{x, y});
        // }
      }
      void on_mouse_button(i32 button, i32 action)
      {

        if (button == GLFW_MOUSE_BUTTON_1)
        {
          double mouse_x, mouse_y;
          glfwGetCursorPos(glfw_window_ptr, &mouse_x, &mouse_y);
          camera_set_last_mouse_pos(camera, glm::vec2(mouse_x, mouse_y));
          // Click right button store the current mouse position
          if (action == GLFW_PRESS)
          {
            if(building_mode) {
              status.pixel = {static_cast<daxa_u32>(mouse_x), static_cast<daxa_u32>(mouse_y)};
              status.is_active += PERFECT_PIXEL_BIT;
            }

            camera_set_mouse_left_press(camera, true);
          }
          // Release right button
          else if (action == GLFW_RELEASE)
          {
            camera_set_mouse_left_press(camera, false);
          }
        }
        else if (button == GLFW_MOUSE_BUTTON_MIDDLE)
        {
          if (action == GLFW_PRESS)
          {
            camera_set_mouse_middle_pressed(camera, true);
          }
          else if (action == GLFW_RELEASE)
          {
            camera_set_mouse_middle_pressed(camera, false);
          }
        }
      }

      void on_scroll(f32 x, f32 y)
      {
        // camera_set_focus_dist(camera, glm::vec2{x, y});
        // std::cout << "scroll x: " << x << " scroll y: " << y << std::endl;
        switch ((u32)y)
        {
        case 1:
        {
          if (camera_get_shift_status(camera))
          {
            camera_set_focus_dist(camera, camera.focus_dist + 0.1f);
          }
          else
          {
            camera_set_defocus_angle(camera, camera.defocus_angle + 0.1f);
          }
          break;
        }
        case -1:
        {
          if (camera_get_shift_status(camera))
          {
            camera_set_focus_dist(camera, camera.focus_dist - 0.1f);
          }
          else
          {
            camera_set_defocus_angle(camera, camera.defocus_angle - 0.1f);
          }
          break;
        }
        default:
          break;
        }
      }

      void on_key(i32 key, i32 action)
      {

        switch (key)
        {
        case GLFW_KEY_W:
        case GLFW_KEY_UP:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_forward(camera);
          }
          break;
        case GLFW_KEY_S:
        case GLFW_KEY_DOWN:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_backward(camera);
          }
          break;
        case GLFW_KEY_A:
        case GLFW_KEY_LEFT:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_left(camera);
          }
          break;
        case GLFW_KEY_D:
        case GLFW_KEY_RIGHT:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_right(camera);
          }
          break;
        case GLFW_KEY_X:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_up(camera);
          }
          break;
        case GLFW_KEY_SPACE:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            move_camera_down(camera);
          }
          break;
        case GLFW_KEY_PAGE_UP:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            // camera.center.y -= SPEED;
          }
          break;
        case GLFW_KEY_PAGE_DOWN:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            // camera.center.y += SPEED;
          }
          break;
        case GLFW_KEY_Q:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            // camera.center.x -= SPEED;
          }
          break;
        case GLFW_KEY_E:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            // camera.center.x += SPEED;
          }
          break;
        case GLFW_KEY_C:
          if (action == GLFW_PRESS)
          {
            reset_camera(camera);
          }
          break;
        case GLFW_KEY_ESCAPE:
          if (action == GLFW_PRESS)
          {
            glfwSetWindowShouldClose(glfw_window_ptr, GLFW_TRUE);
          }
          break;
        case GLFW_KEY_M:
          if (action == GLFW_PRESS)
          {
            if (!activate_day_night_cycle)
            {
              activate_midday = !activate_midday;
              if (activate_sun_light && point_lights)
              {
                set_midday(activate_midday, point_lights[0]);
              }
            }
            // change_random_material_primitives();
            // camera_set_moved(camera);
          }
          break;
        case GLFW_KEY_LEFT_SHIFT:
          if (action == GLFW_PRESS)
          {
            camera_shift_pressed(camera);
          }
          else if (action == GLFW_RELEASE)
          {
            camera_shift_released(camera);
          }
          break;
        case GLFW_KEY_F:
          if (action == GLFW_PRESS)
          {
            activate_filtering = !activate_filtering;
          }
          break;
        case GLFW_KEY_N:
          if (action == GLFW_PRESS)
          {
            activate_day_night_cycle = !activate_day_night_cycle;
            start_time = std::chrono::steady_clock::now();
          }
          break;
        case GLFW_KEY_V:
        case GLFW_KEY_KP_SUBTRACT:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            add_time_and_sun_light(-0.01f);
          }
          break;
        case GLFW_KEY_B:
        case GLFW_KEY_KP_ADD:
          if (action == GLFW_PRESS || action == GLFW_REPEAT)
          {
            add_time_and_sun_light(0.01f);
          }
          break;
        case GLFW_KEY_1:
        case GLFW_KEY_KP_1:
          if (action == GLFW_PRESS)
          {
            if (point_lights)
            {
              activate_point_lights = !activate_point_lights;
              std::string point_light_msg = activate_point_lights ? "Activated point light sampling" : "Deactivated point light sampling";
              std::cout << point_light_msg << std::endl;
            }
          }
          break;
        case GLFW_KEY_2:
        case GLFW_KEY_KP_2:
          if (action == GLFW_PRESS)
          {
            if (env_lights)
            {
              activate_env_map = !activate_env_map;
              std::string env_map_msg = activate_env_map ? "Activated env map sampling" : "Deactivated env map sampling";
              std::cout << env_map_msg << std::endl;
            }
          }
          break;
        case GLFW_KEY_3:
        case GLFW_KEY_KP_3:
          if (action == GLFW_PRESS)
          {
            if (as_manager->get_cube_lights())
            {
              activate_cube_lights = !activate_cube_lights;
              std::string cube_msg = activate_cube_lights ? "Activated cube light sampling" : "Deactivated cube light sampling";
              std::cout << cube_msg << std::endl;
            }
          }
          break;
        case GLFW_KEY_4:
        case GLFW_KEY_KP_4:
          if (action == GLFW_PRESS)
          {
            if (as_manager->get_cube_lights())
            {
              activate_brdf = !activate_brdf;
              std::string brdf_msg = activate_brdf ? "Activated brdf sampling" : "Deactivated brdf sampling";
              std::cout << brdf_msg << std::endl;
            }
          }
          break;
        case GLFW_KEY_R:
          if (action == GLFW_PRESS)
          {
            as_manager->task_queue_add(TASK{
                .type = TASK::TYPE::UNDO_OP_CPU
            });
          }
          break;
        case GLFW_KEY_LEFT_CONTROL:
          if (action == GLFW_PRESS)
          {
            building_mode = !building_mode;
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

          previous_frame = daxa::ImageId{};

          for (auto image : taa_image)
            device.destroy_image(image);

          taa_image[0] = device.create_image({
              .format = swapchain.get_format(),
              .size = {size_x, size_y, 1},
              .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE,
              .name = "taa_image_0",
          });

          taa_image[1] = device.create_image({
              .format = swapchain.get_format(),
              .size = {size_x, size_y, 1},
              .usage = daxa::ImageUsageFlagBits::SHADER_STORAGE,
              .name = "taa_image_1",
          });

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
