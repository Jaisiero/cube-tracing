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

#define FATAL 1
#define WARN 1
#define INFO 1
#define DEBUG 1
#define TRACE 1

const uint32_t DOUBLE_BUFFERING = 2;

#define CL_NAMESPACE_BEGIN namespace cubeland {
#define CL_NAMESPACE_END }

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


CL_NAMESPACE_BEGIN

inline namespace types
{
    using u8 = std::uint8_t;
    using u16 = std::uint16_t;
    using u32 = std::uint32_t;
    using u64 = std::uint64_t;
    using usize = std::size_t;
    using b32 = u32;

    using i8 = std::int8_t;
    using i16 = std::int16_t;
    using i32 = std::int32_t;
    using i64 = std::int64_t;
    using isize = std::ptrdiff_t;

    using uuid32 = u32;
    using uuid64 = u64;

    using f32 = float;
    using f64 = double;

    using DeviceAddress = u64;
} // namespace types


struct  CubelandGPUResource
{
    u64 index = 0xFFFFFFFFFFFFFFFF;

    auto is_valid() const -> bool { return index != 0xFFFFFFFFFFFFFFFF; }
    auto is_invalid() const -> bool { return index == 0xFFFFFFFFFFFFFFFF; }

    constexpr auto operator<=>(CubelandGPUResource const & other) const
    {
        return std::bit_cast<u64>(*this) <=> std::bit_cast<u64>(other);
    }
    
    constexpr bool operator==(CubelandGPUResource const &other) const = default;
    constexpr bool operator!=(CubelandGPUResource const &other) const = default;
    constexpr bool operator<(CubelandGPUResource const &other) const = default;
    constexpr bool operator>(CubelandGPUResource const &other) const = default;
    constexpr bool operator<=(CubelandGPUResource const &other) const = default;
    constexpr bool operator>=(CubelandGPUResource const &other) const = default;
};

struct VoxelBuffer : public CubelandGPUResource
{
    
};

CL_NAMESPACE_END

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
    uint32_t current_instance_index;
    INSTANCE* const instances;
    uint32_t current_primitive_index;
    uint32_t max_primitive_count;
    PRIMITIVE* const primitives;
    AABB* const aabbs;
    uint32_t current_material_index;
    uint32_t max_material_count;
    MATERIAL* const materials;
    uint32_t current_light_index;
    uint32_t max_light_count;
    LIGHT* const lights;
};

struct GvoxModelDataSerializeInternal {
  GvoxModelData& scene_info;
  GvoxModelDataSerialize& params;
};