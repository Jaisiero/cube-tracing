#pragma once
#include "shared.inl"

// StructuredBuffer <INSTANCE> instances;
// RWStructuredBuffer <PRIMITIVE> primitives;
// RWStructuredBuffer <AABB> aabbs : AABB_BUFFER ;
// RWStructuredBuffer <MATERIAL> materials : MATERIAL_BUFFER ;
// RWStructuredBuffer <LIGHT> point_lights : POINT_LIGHT_BUFFER ;
// RWStructuredBuffer <LIGHT> env_lights : ENV_LIGHT_BUFFER ;
// RWStructuredBuffer <LIGHT> cube_lights : CUBE_LIGHT_BUFFER ;
// RWStructuredBuffer <RESERVOIR> prev_reservoirs : PREV_RESERVOIR_BUFFER ;
// RWStructuredBuffer <RESERVOIR> int_reservoirs : INT_RESERVOIR_BUFFER ;
// RWStructuredBuffer <RESERVOIR> reservoirs : RESERVOIR_BUFFER ;
// RWStructuredBuffer <VELOCITY> velocities : VELOCITY_BUFFER ;
// RWStructuredBuffer <DIRECT_ILLUMINATION_INFO> prev_di_info : PREV_DI_BUFFER ;
// RWStructuredBuffer <DIRECT_ILLUMINATION_INFO> di_info : DI_BUFFER ;
// RWStructuredBuffer <daxa_f32vec3> indirect_colors : INDIRECT_COLOR_BUFFER ;
// RWStructuredBuffer <PIXEL_RECONNECTION_DATA> reconnections : PIXEL_RECONNECTION_DATA_BUFFER ;
// RWStructuredBuffer <PATH_RESERVOIR> output_path_reservoirs : OUTPUT_PATH_RESERVOIR_BUFFER ;
// RWStructuredBuffer <PATH_RESERVOIR> temporal_path_reservoirs : TEMPORAL_PATH_RESERVOIR_BUFFER ;
// RWStructuredBuffer <BRUSH_COUNTER> brush_counter : BRUSH_COUNTER_BUFFER ;
// RWStructuredBuffer <daxa_u32> instance_bitmask : INSTANCE_BITMASK_BUFFER ;
// RWStructuredBuffer <daxa_u32> primitive_bitmask : PRIMITIVE_BITMASK_BUFFER ;


// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  INSTANCES_BUFFER  {INSTANCE instances[]; }; // Positions of an object
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  REMAPPED_PRIMITIVE_BUFFER  {daxa_u32 primitives[]; }; // Primitive data
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  PRIMITIVE_BUFFER  {PRIMITIVE primitives[]; }; // Primitive data

// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  AABB_BUFFER  {AABB aabbs[]; }; // Positions of a primitive

// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  MATERIAL_BUFFER  {MATERIAL materials[]; }; // Materials

// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  POINT_LIGHT_BUFFER  {LIGHT point_lights[]; }; // Lights
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  ENV_LIGHT_BUFFER  {LIGHT env_lights[]; }; // Environment lights
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  CUBE_LIGHT_BUFFER  {LIGHT cube_lights[]; }; // Cube lights
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  REMAPPED_CUBE_LIGHT_BUFFER  {daxa_u32 lights[]; }; // Primitive data
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  LIGHT_CONFIG_BUFFER  {LIGHT_CONFIG light_config; }; // Lights

// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  PREV_RESERVOIR_BUFFER  {RESERVOIR reservoirs[]; }; // Reservoirs from the previous frame
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  INT_RESERVOIR_BUFFER  {RESERVOIR reservoirs[]; }; // Intermediate reservoirs
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  RESERVOIR_BUFFER  {RESERVOIR reservoirs[]; }; // Reservoirs from the current frame
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  VELOCITY_BUFFER  {VELOCITY velocities[]; }; // Velocities
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  PREV_DI_BUFFER  {DIRECT_ILLUMINATION_INFO di_info[]; }; // Direct illumination info
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  DI_BUFFER  {DIRECT_ILLUMINATION_INFO di_info[]; }; // Direct illumination info


// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  INDIRECT_COLOR_BUFFER  {daxa_f32vec3 colors[]; }; // Indirect color


// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  PIXEL_RECONNECTION_DATA_BUFFER  {PIXEL_RECONNECTION_DATA reconnections[]; }; // Pixel reconnection data
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  OUTPUT_PATH_RESERVOIR_BUFFER  {PATH_RESERVOIR path_reservoirs[]; }; // Path reservoirs
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  TEMPORAL_PATH_RESERVOIR_BUFFER  {PATH_RESERVOIR path_reservoirs[]; }; // Path reservoirs


// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  BRUSH_COUNTER_BUFFER  {BRUSH_COUNTER brush_counter; }; // Brush counter
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  INSTANCE_BITMASK_BUFFER  {daxa_u32 instance_bitmask[]; }; // Instance bitmask
// layout(RWStructuredBuffer _reference, scalar) RWStructuredBuffer  PRIMITIVE_BITMASK_BUFFER  {daxa_u32 primitive_bitmask[]; }; // Primitive bitmask