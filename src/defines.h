#pragma once

#include <iostream>

#include <daxa/daxa.hpp>
#include <window.hpp>
#include <shared.hpp>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>

#include "shaders/shared.inl"

#define DEBUG 0

const uint32_t DOUBLE_BUFFERING = 2;

// const daxa_f32 AXIS_DISPLACEMENT = VOXEL_EXTENT * VOXEL_COUNT_BY_AXIS; //(2^4)
// const daxa_u32 INSTANCE_X_AXIS_COUNT = 1;                              // X^2 (mirrored on both sides of the x axis)
// const daxa_u32 INSTANCE_Z_AXIS_COUNT = 1;                              // Z^2 (mirrored on both sides of the z axis)
// const daxa_u32 CLOUD_INSTANCE_COUNT = 1;                               // 2^1 (mirrored on both sides of the x axis)
// const daxa_u32 CLOUD_INSTANCE_COUNT_X = (CLOUD_INSTANCE_COUNT * 2);
// // const daxa_u32 INSTANCE_COUNT = INSTANCE_X_AXIS_COUNT * INSTANCE_Z_AXIS_COUNT;
// const daxa_u32 LAMBERTIAN_MATERIAL_COUNT = 3000;
// // const daxa_u32 METAL_MATERIAL_COUNT = 15;
// const daxa_u32 METAL_MATERIAL_COUNT = 0;
// // const daxa_u32 DIALECTRIC_MATERIAL_COUNT = 5;
// const daxa_u32 DIALECTRIC_MATERIAL_COUNT = 0;
// const daxa_u32 EMISSIVE_MATERIAL_COUNT = 1;
// const daxa_u32 CONSTANT_MEDIUM_MATERIAL_COUNT = 5;
// const daxa_u32 MATERIAL_COUNT = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT + EMISSIVE_MATERIAL_COUNT + CONSTANT_MEDIUM_MATERIAL_COUNT;
// const daxa_u32 MATERIAL_COUNT_UP_TO_DIALECTRIC = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT;
// const daxa_u32 MATERIAL_COUNT_UP_TO_EMISSIVE = LAMBERTIAN_MATERIAL_COUNT + METAL_MATERIAL_COUNT + DIALECTRIC_MATERIAL_COUNT + EMISSIVE_MATERIAL_COUNT;


struct GvoxModelData {
    uint32_t instance_count;
    uint32_t primitive_count;
    uint32_t material_count;
    uint32_t light_count;
};

enum AXIS_DIRECTION {
    X_BOTTOM_TOP = 0,
    Y_BOTTOM_TOP = 1,
    Z_BOTTOM_TOP = 2,
    X_TOP_BOTTOM = 3,
    Y_TOP_BOTTOM = 4,
    Z_TOP_BOTTOM = 5
};


struct GvoxModelDataSerialize {
    AXIS_DIRECTION axis_direction;
    uint32_t max_instance_count;
    INSTANCE* const instances;
    uint32_t max_primitive_count;
    PRIMITIVE* const primitives;
    AABB* const aabbs;
    uint32_t max_material_count;
    MATERIAL* const materials;
    uint32_t max_light_count;
    LIGHT* const lights;
};

struct GvoxModelDataSerializeInternal {
  GvoxModelData& scene_info;
  GvoxModelDataSerialize& params;
};

constexpr daxa_f32mat4x4 glm_mat4_to_daxa_f32mat4x4(glm::mat4 const &mat)
{
  return daxa_f32mat4x4{
      {mat[0][0], mat[0][1], mat[0][2], mat[0][3]},
      {mat[1][0], mat[1][1], mat[1][2], mat[1][3]},
      {mat[2][0], mat[2][1], mat[2][2], mat[2][3]},
      {mat[3][0], mat[3][1], mat[3][2], mat[3][3]},
  };
}

constexpr daxa_f32mat3x4 daxa_f32mat4x4_to_daxa_f32mat3x4(daxa_f32mat4x4 const &mat)
{
  return daxa_f32mat3x4{
      {mat.x.x, mat.y.x, mat.z.x, mat.w.x},
      {mat.x.y, mat.y.y, mat.z.y, mat.w.y},
      {mat.x.z, mat.y.z, mat.z.z, mat.w.z}};
}

constexpr daxa_f32mat4x4 get_daxa_f32mat4x4_transpose(daxa_f32mat4x4 const &mat)
{
  return daxa_f32mat4x4{
      {mat.x.x, mat.y.x, mat.z.x, mat.w.x},
      {mat.x.y, mat.y.y, mat.z.y, mat.w.y},
      {mat.x.z, mat.y.z, mat.z.z, mat.w.z},
      {mat.x.w, mat.y.w, mat.z.w, mat.w.w},
  };
}

// Generate min max by coord (x, y, z) where x, y, z are 0 to VOXEL_COUNT_BY_AXIS-1 where VOXEL_COUNT_BY_AXIS / 2 is the center at (0, 0, 0)
constexpr daxa_f32mat2x3 generate_min_max_by_coord(daxa_u32 x, daxa_u32 y, daxa_u32 z, daxa_f32 voxel_extent)
{
  return daxa_f32mat2x3{
      {-((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + (x * voxel_extent) + AVOID_VOXEL_COLLAIDE,
       -((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + (y * voxel_extent) + AVOID_VOXEL_COLLAIDE,
       -((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + (z * voxel_extent) + AVOID_VOXEL_COLLAIDE},
      {-((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + ((x + 1) * voxel_extent) - AVOID_VOXEL_COLLAIDE,
       -((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + ((y + 1) * voxel_extent) - AVOID_VOXEL_COLLAIDE,
       -((VOXEL_COUNT_BY_AXIS / 2) * voxel_extent) + ((z + 1) * voxel_extent) - AVOID_VOXEL_COLLAIDE}};
}

constexpr daxa_f32vec3 generate_center_by_coord(daxa_u32 x, daxa_u32 y, daxa_u32 z, daxa_f32 chunck_extent)
{
  return daxa_f32vec3{
      -((VOXEL_COUNT_BY_AXIS / 2) * chunck_extent) + (x * chunck_extent) + (chunck_extent / 2),
      -((VOXEL_COUNT_BY_AXIS / 2) * chunck_extent) + (y * chunck_extent) + (chunck_extent / 2),
      -((VOXEL_COUNT_BY_AXIS / 2) * chunck_extent) + (z * chunck_extent) + (chunck_extent / 2)};
}

constexpr daxa_f32mat2x3 generate_min_max_at_origin(daxa_f32 extent)
{
  return daxa_f32mat2x3{
      {
          daxa_f32vec3(-extent + AVOID_VOXEL_COLLAIDE, -extent + AVOID_VOXEL_COLLAIDE, -extent + AVOID_VOXEL_COLLAIDE),
      },
      {
          daxa_f32vec3(extent - AVOID_VOXEL_COLLAIDE, extent - AVOID_VOXEL_COLLAIDE, extent - AVOID_VOXEL_COLLAIDE),
      }};
}

constexpr daxa_f32vec3 daxa_f32mat4x4_multiply_by_daxa_f32vec4(daxa_f32mat4x4 const &mat, daxa_f32vec4 const &vec)
{
  return daxa_f32vec3{
      mat.x.x * vec.x + mat.y.x * vec.y + mat.z.x * vec.z + mat.w.x * vec.w,
      mat.x.y * vec.x + mat.y.y * vec.y + mat.z.y * vec.z + mat.w.y * vec.w,
      mat.x.z * vec.x + mat.y.z * vec.y + mat.z.z * vec.z + mat.w.z * vec.w,
  };
}

constexpr daxa_f32vec3 daxa_f32vec3_add_daxa_f32vec3(daxa_f32vec3 const &vec1, daxa_f32vec3 const &vec2)
{
  return daxa_f32vec3{
      vec1.x + vec2.x,
      vec1.y + vec2.y,
      vec1.z + vec2.z,
  };
}

constexpr daxa_f32vec3 daxa_f32vec3_multiply_by_scalar(daxa_f32vec3 const &vec, daxa_f32 const &scalar)
{
  return daxa_f32vec3{
      vec.x * scalar,
      vec.y * scalar,
      vec.z * scalar,
  };
}