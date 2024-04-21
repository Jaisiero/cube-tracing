#pragma once

#include "defines.slang"

[[vk::push_constant]] changes_push_constant p;

// primitive index of the ordinal deleted in the current instance
uint get_primitive_index_from_ordinal_in_bitmask(
    Ptr<daxa_u32> primitive_bitmask,
    uint ordinal_number, uint first_primitive_index, uint primitive_count)
{

    uint deleted_primitive_count = 0;
    uint current_primitive_index = 0;
    uint deleted_primitive_index = 0;
    for (uint i = first_primitive_index; i < (first_primitive_index + primitive_count); i++)
    {
        if ((primitive_bitmask[i >> 5] & (1 << (i & 31))) != 0)
        {
            if (ordinal_number == deleted_primitive_count)
            {
                deleted_primitive_index = current_primitive_index;
                break;
            }
            ++deleted_primitive_count;
        }
        ++current_primitive_index;
    }
    return deleted_primitive_index;
}

// primitive index of the ordinal deleted in the current instance
uint get_primitive_index_from_ordinal_out_bitmask(
    Ptr<daxa_u32> primitive_bitmask,
    uint ordinal_number, uint first_primitive_index, uint primitive_count)
{
    uint deleted_primitive_count = 0;
    uint current_primitive_index = 0;
    uint deleted_primitive_index = 0;
    for (uint p = first_primitive_index; p < (first_primitive_index + primitive_count); p++)
    {
        if ((primitive_bitmask[p >> 5] & (1 << (p & 31))) == 0)
        {
            if (ordinal_number == deleted_primitive_count)
            {
                deleted_primitive_index = p;
                break;
            }
            ++deleted_primitive_count;
        }
        ++current_primitive_index;
    }
    return deleted_primitive_index;
}

[shader("compute")]
    [numthreads(BRUSH_COMPUTE_X, 1, 1)] void
    entry_brush(uint3 pixel_i : SV_DispatchThreadID)
{
    // Access instance & primitive counters
    Ptr<BRUSH_COUNTER> brush_counter = Ptr<BRUSH_COUNTER>(p.head.status_buffer->brush_counter_address);

    // Get instance count
    uint instance_count = brush_counter->instance_count;
    // Get primitive count
    uint primitive_count = brush_counter->primitive_count;
    // Get the current thread index
    uint thread_index = pixel_i.x;

    if (primitive_count == 0 || instance_count == 0)
        return;

    if (thread_index >= primitive_count)
        return;

    // Get the current instance bitmask
    Ptr<daxa_u32> instance_bitmask = Ptr<daxa_u32>(p.head.status_buffer->instance_bitmask_address);

    // Get the current primitive bitmask
    Ptr<daxa_u32> primitive_bitmask = Ptr<daxa_u32>(p.head.status_buffer->primitive_bitmask_address);

    // Get the current instance index for this thread
    uint instance_index = 0;
    // Get the current ordinal index for this thread which means
    // the number of the primitive inside the instance region
    // that is going to be deleted.
    // NOTE: for instance, the 1st ordinal primitive to be deleted could be any primitive in the range of the instance primitive region (primitive_index 5).
    // Instance primitive region -> [ | | | | |x|...]
    uint deleted_ordinal_index = 0;

    INSTANCE t_instance_prev = {0};

    uint total_primitive_count_deleted = 0;
    uint total_primitive_count_deleted_by_instance = 0;

    bool is_instance = false;

    // Calculate the number of packets needed to store the instance bitmask
    uint instance_packet_count = (instance_count >> 5);

    // If the instance count is not a multiple of 32, add one more packet
    instance_packet_count = instance_packet_count + ((instance_count & 31) > 0 ? 1 : 0);

    uint current_instance_primitive_pack = 0;

    // Iterate over the mask and find who you are
    for (uint i = 0; i < instance_packet_count && !is_instance; i++)
    {
        if (instance_bitmask[i] == 0)
        {
            instance_index += 32;
            continue;
        }

        // Iterate over the mask and find who you are
        for (uint j = 0; j < 32 && !is_instance; j++)
        {
            // If instance has primitive deleted
            if ((instance_bitmask[i] & (1 << j)) != 0)
            {
                // Get the instance
                t_instance_prev = Ptr<INSTANCE>(p.head.world_buffer->instance_address_prev)[i * 32 + j];

                total_primitive_count_deleted_by_instance = 0;

                current_instance_primitive_pack = (t_instance_prev.primitive_count >> 5);

                current_instance_primitive_pack = current_instance_primitive_pack + ((t_instance_prev.primitive_count & 31) > 0 ? 1 : 0);

                uint first_prim_pack = t_instance_prev.first_primitive_index >> 5;

                // Iterate over the mask and find who you are
                for (uint p = 0; p < current_instance_primitive_pack; p++)
                {
                    uint current_primitive_index = p + first_prim_pack;

                    uint count = countbits(primitive_bitmask[current_primitive_index]);

                    // Total primitives deleted in the whole scene
                    total_primitive_count_deleted += count;

                    // Total primitives deleted in the current instance
                    total_primitive_count_deleted_by_instance += count;
                }

                // If the total primitive count deleted is greater than the current thread index, then this is the instance
                if (total_primitive_count_deleted >= thread_index)
                {
                    is_instance = true;
                    deleted_ordinal_index = (total_primitive_count_deleted_by_instance - (total_primitive_count_deleted - thread_index));
                    break;
                }
            }
            ++instance_index;
        }
    }

    if (is_instance)
    {

        uint first_prim_index = t_instance_prev.first_primitive_index;

        uint primitive_count = t_instance_prev.primitive_count;

        // Index of the last primitive deleted
        uint index_from_to_delete = (primitive_count - total_primitive_count_deleted_by_instance);

        Ptr<INSTANCE> t_instance = &(Ptr<INSTANCE>(p.head.world_buffer.instance_address)[instance_index]);

        // Implement atomic decrease of t_instance->primitive_count
        // Atomic decrease of t_instance->primitive_count
        uint old_primitive_count;
        InterlockedAdd(t_instance->primitive_count, -1, old_primitive_count);

        uint primitive_index = get_primitive_index_from_ordinal_in_bitmask(
            primitive_bitmask,
            deleted_ordinal_index, first_prim_index, primitive_count);

        if (primitive_index < index_from_to_delete)
        {
            // find the index primitive remplacement in the instance for the ordinal primitive
            // NOTE: the replacement region is the last primitive of the instance minus the deleted primitive count backwards (primitive count - deleted primitive count) that's where the replacement region starts.
            uint primitive_replacement_index = get_primitive_index_from_ordinal_out_bitmask(
                primitive_bitmask,
                deleted_ordinal_index, index_from_to_delete, total_primitive_count_deleted_by_instance);

            // Swap the primitive and AABB at the given indices
            Ptr<PRIMITIVE>(p.head.world_buffer->primitive_address)[first_prim_index + primitive_index] = Ptr<PRIMITIVE>(p.head.world_buffer->primitive_address)[first_prim_index + primitive_replacement_index];
            Ptr<AABB>(p.head.world_buffer->aabb_address)[first_prim_index + primitive_index] = Ptr<AABB>(p.head.world_buffer->aabb_address)[first_prim_index + primitive_replacement_index];

            // TODO: for debbuging
            // Fill test primitive with the new primitive
            p.head.test_brush_primitive_buffer.primitive_replacement_index = primitive_replacement_index;

            // apply remapping to the replacement index
            Ptr<daxa_i32>(p.head.world_buffer->remapped_primitive_address)[first_prim_index + primitive_replacement_index] =  primitive_index;
        }
        // TODO: for debbuging
        // Fill test primitive with the new primitive
        p.head.test_brush_primitive_buffer.primitive_index = primitive_index;

        // apply remapping to the primitive index
        Ptr<daxa_i32>(p.head.world_buffer->remapped_primitive_address)[first_prim_index + primitive_index] =  -1;
    }
}