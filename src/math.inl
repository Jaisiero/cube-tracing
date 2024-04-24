#pragma once

#include "defines.h"

constexpr daxa_f32mat3x3 glm_mat3_to_daxa_f32mat3x3(glm::mat3 const &mat)
{
  return daxa_f32mat3x3{
      {mat[0][0], mat[0][1], mat[0][2]},
      {mat[1][0], mat[1][1], mat[1][2]},
      {mat[2][0], mat[2][1], mat[2][2]},
  };
}

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


constexpr daxa_f32mat4x4 daxa_f32mat4x4_mult(daxa_f32mat4x4 const &mat, daxa_f32mat4x4 const &mat2)
{
  return daxa_f32mat4x4{
      {
          mat.x.x * mat2.x.x + mat.y.x * mat2.x.y + mat.z.x * mat2.x.z + mat.w.x * mat2.x.w,
          mat.x.y * mat2.x.x + mat.y.y * mat2.x.y + mat.z.y * mat2.x.z + mat.w.y * mat2.x.w,
          mat.x.z * mat2.x.x + mat.y.z * mat2.x.y + mat.z.z * mat2.x.z + mat.w.z * mat2.x.w,
          mat.x.w * mat2.x.x + mat.y.w * mat2.x.y + mat.z.w * mat2.x.z + mat.w.w * mat2.x.w,
      },
      {
          mat.x.x * mat2.y.x + mat.y.x * mat2.y.y + mat.z.x * mat2.y.z + mat.w.x * mat2.y.w,
          mat.x.y * mat2.y.x + mat.y.y * mat2.y.y + mat.z.y * mat2.y.z + mat.w.y * mat2.y.w,
          mat.x.z * mat2.y.x + mat.y.z * mat2.y.y + mat.z.z * mat2.y.z + mat.w.z * mat2.y.w,
          mat.x.w * mat2.y.x + mat.y.w * mat2.y.y + mat.z.w * mat2.y.z + mat.w.w * mat2.y.w,
      },
      {
          mat.x.x * mat2.z.x + mat.y.x * mat2.z.y + mat.z.x * mat2.z.z + mat.w.x * mat2.z.w,
          mat.x.y * mat2.z.x + mat.y.y * mat2.z.y + mat.z.y * mat2.z.z + mat.w.y * mat2.z.w,
          mat.x.z * mat2.z.x + mat.y.z * mat2.z.y + mat.z.z * mat2.z.z + mat.w.z * mat2.z.w,
          mat.x.w * mat2.z.x + mat.y.w * mat2.z.y + mat.z.w * mat2.z.z + mat.w.w * mat2.z.w,
      },
      {
          mat.x.x * mat2.w.x + mat.y.x * mat2.w.y + mat.z.x * mat2.w.z + mat.w.x * mat2.w.w,
          mat.x.y * mat2.w.x + mat.y.y * mat2.w.y + mat.z.y * mat2.w.z + mat.w.y * mat2.w.w,
          mat.x.z * mat2.w.x + mat.y.z * mat2.w.y + mat.z.z * mat2.w.z + mat.w.z * mat2.w.w,
          mat.x.w * mat2.w.x + mat.y.w * mat2.w.y + mat.z.w * mat2.w.z + mat.w.w * mat2.w.w,
      }};
}


template <typename T>
auto constexpr get_aligned(T operand, T granularity) -> T
{
    return ((operand + (granularity - 1)) & ~(granularity - 1));
};