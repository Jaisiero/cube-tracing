

#include "map_loader.hpp"

#include <mutex>

#include <gvox/adapters/input/file.h>
#include <gvox/adapters/input/byte_buffer.h>
#include <gvox/adapters/output/byte_buffer.h>
#include <gvox/adapters/parse/voxlap.h>


GvoxOffset3D operator+(GvoxOffset3D const &lhs, GvoxOffset3D const &rhs)
{
    return GvoxOffset3D{lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z};
}


// Called when creating the adapter context
void create(GvoxAdapterContext *ctx, void const *config) {
    // here you can create any resources you want to associate with your adapter.
    // you can tie your state to the adapter context `ctx` with this function:
    //   void *my_pointer = malloc(sizeof(int));
    //   gvox_adapter_set_user_pointer(ctx, my_pointer);
    // which can be retrieved at any time with the get variant of this function.
}
// Called when destroying the adapter context (for freeing any resources created by the adapter)
void destroy(GvoxAdapterContext *ctx) {
    // here we'd free `my_pointer`
    //   void *my_pointer = gvox_adapter_get_user_pointer(ctx);
    //   free(my_pointer);
}
// Called at the beginning of a blit operation.
void blit_begin(GvoxBlitContext *blit_ctx, GvoxAdapterContext *ctx, GvoxRegionRange const *range, uint32_t channel_flags) {
    // We get a minimal description of the volume we're
}
void blit_end(GvoxBlitContext *blit_ctx, GvoxAdapterContext *ctx) {
}
void serialize_region(GvoxBlitContext *blit_ctx, GvoxAdapterContext *ctx, GvoxRegionRange const *range, uint32_t channel_flags) {
}

// This function may be called in a parallel nature by the parse adapter.
void receive_region(GvoxBlitContext *blit_ctx, GvoxAdapterContext *ctx, GvoxRegion const *region) {
    // `GvoxRegion` description:
    //  `.range.offset` is the 3D location of the 3D array in world-space
    //  `.range.extent` is the dimensions of the 3D array.
    //  `.channels` is the channel flags, in this case it should just be `GVOX_CHANNEL_BIT_COLOR`.
    //  `.flags` is a set of GVOX_REGION_FLAG_ bits, which describe extra metadata about the region.

    GvoxOffset3D sample_position = region->range.offset;
    // In order to sample voxel data from the region, use `gvox_sample_region()`:
    //  - blit_ctx is necessary as the data is extracted from the parser's custom region data format.
    //  - region is the pointer to the region that has been acquired.
    //  - sample position is the coordinate from [ range.offset, range.offset + range.extent ) that the serializer
    //    would like to query. If a coordinate is specified outside this range, the resulting sample should have
    //    0 for `.is_present`.
    GvoxSample region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_COLOR);
    // `GvoxSample` description:
    //  `.is_present` is either 0 or 1 depending on whether there is valid data at the specified coordinate.
    //  `.data` is a single uint32_t that holds the actual data. How this data is represented is defined by
    //     the channel in question. If, for example, one requested GVOX_CHANNEL_ID_COLOR, the 8bpc color data
    //     would be packed into the first 24 bits of the uint32_t.

    {
        static auto printf_mtx = std::mutex{};

        // If necessary in our application, we may need to synchronize. For example,
        // here we need to lock printf because we only want one thread writing to
        // the console at any time.
        auto lock = std::lock_guard{printf_mtx};

        uint8_t r = 0;
        uint8_t g = 0;
        uint8_t b = 0;
        if (region_sample.is_present != 0) {
            r = (region_sample.data >> 0u) & 0xff;
            g = (region_sample.data >> 8u) & 0xff;
            b = (region_sample.data >> 16u) & 0xff;
        }
        // print-out the color of the voxel in the 0, 0, 0 corner of the region
        printf("\033[48;2;%03d;%03d;%03dm  \033[0m", r, g, b);
        printf("offset: (%d %d %d) extent: (%d %d %d) channels: %d flags: %d\n",
               region->range.offset.x,
               region->range.offset.y,
               region->range.offset.z,
               region->range.extent.x,
               region->range.extent.y,
               region->range.extent.z,
               region->channels,
               region->flags);

        uint32_t voxel_count = 0;
        uint32_t light_count = 0;

        struct palette_entry {
            uint8_t id;
            uint8_t count;
        };

        std::vector<palette_entry> palette_data;

        for(int z = 0; z < region->range.extent.z; ++z) {
            for(int y = 0; y < region->range.extent.y; ++y) {
                for(int x = 0; x < region->range.extent.x; ++x) {
                    GvoxOffset3D sample_position = region->range.offset + GvoxOffset3D{x, y, z};
                    GvoxSample region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_COLOR);
                    uint8_t r = 0;
                    uint8_t g = 0;
                    uint8_t b = 0;
                    if (region_sample.is_present != 0) {
                        r = (region_sample.data >> 0u) & 0xff;
                        g = (region_sample.data >> 8u) & 0xff;
                        b = (region_sample.data >> 16u) & 0xff;

                        ++voxel_count;
                    }
                    // printf("\033[48;2;%03d;%03d;%03dm  \033[0m", r, g, b);
                    region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_EMISSIVITY);
                    uint8_t l_r = 0;
                    uint8_t l_g = 0;
                    uint8_t l_b = 0;
                    if (region_sample.is_present != 0) {
                        l_r = (region_sample.data >> 0u) & 0xff;
                        l_g = (region_sample.data >> 8u) & 0xff;
                        l_b = (region_sample.data >> 16u) & 0xff;
                        if(l_r != 0 || l_g != 0 || l_b != 0)
                            ++light_count;
                    }
                    region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_MATERIAL_ID);
                    uint8_t id = 0;
                    if (region_sample.is_present != 0) {
                        id = (region_sample.data >> 0u) & 0xff;
                        // printf(" %u ", id);

                        bool found = false;

                        for(auto &entry : palette_data) {
                            if(entry.id == id) {
                                ++entry.count;
                                found = true;
                            } 
                        }

                        if(!found) {
                            palette_data.push_back({id, 1});
                        }
                    }
                    region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_ROUGHNESS);
                    float roughtness = 0;
                    if (region_sample.is_present != 0) {
                        roughtness = *(float *)(&region_sample.data);
                        if(roughtness != 0.0f)
                            printf("roughtness: %f\n", roughtness);
                    }
                    region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_METALNESS);
                    float metalness = 0;
                    if (region_sample.is_present != 0) {
                        metalness = *(float *)(&region_sample.data);
                        if(metalness != 0.0f)
                            printf("metalness: %f\n", metalness);
                    }
                    region_sample = gvox_sample_region(blit_ctx, region, &sample_position, GVOX_CHANNEL_ID_IOR);
                    float ior = 0;
                    if (region_sample.is_present != 0) {
                        ior = *(float *)(&region_sample.data);
                        if(ior != 0.0f)
                            printf("ior: %f\n", ior);
                    }
                    // printf("\033[48;2;%03d;%03d;%03dm\033[38;2;%03d;%03d;%03dm\033[30;1m%02x\033[0m", r, g, b, l_r, l_g, l_b, id);
                }
                // printf("\n");
            }
            // printf("\n");
        }

        printf("voxel count: %d\n", voxel_count);
        printf("light count: %d\n", light_count);


        for(auto &entry : palette_data) {
            printf("id: %u count: %u\n", entry.id, entry.count);
        }
    }
}

void handle_gvox_error(GvoxContext *gvox_ctx) {
    GvoxResult res = gvox_get_result(gvox_ctx);
    int error_count = 0;
    while (res != GVOX_RESULT_SUCCESS) {
        size_t size = 0;
        gvox_get_result_message(gvox_ctx, nullptr, &size);
        char *str = new char[size + 1];
        gvox_get_result_message(gvox_ctx, str, nullptr);
        str[size] = '\0';
        printf("ERROR: %s\n", str);
        gvox_pop_result(gvox_ctx);
        delete[] str;
        res = gvox_get_result(gvox_ctx);
        ++error_count;
    }
    if (error_count != 0) {
        exit(-error_count);
    }
}

auto const my_adapter_info = GvoxSerializeAdapterInfo{
    .base_info = {
        .name_str = "my_adapter",
        .create = create,
        .destroy = destroy,
        .blit_begin = blit_begin,
        .blit_end = blit_end,
    },
    .serialize_region = serialize_region,
    .receive_region = receive_region,
};


void MapLoader::create_gvox_context()
{
    gvox_ctx = gvox_create_context();
    // register our custom adapter that'll receive all the model data
    gvox_register_serialize_adapter(gvox_ctx, &my_adapter_info);
}

void MapLoader::destroy_gvox_context()
{
    gvox_destroy_context(gvox_ctx);
}


auto MapLoader::load_gvox_data(std::filesystem::path gvox_model_path) -> GvoxModelData
{
    auto result = GvoxModelData{};
    auto file = std::ifstream(gvox_model_path, std::ios::binary);
    if (!file.is_open())
    {
        std::cerr << "[error] Failed to load the model" << std::endl;
        // should_upload_gvox_model = false;
        return result;
    }
    file.seekg(0, std::ios_base::end);
    auto temp_gvox_model_size = static_cast<daxa_u32>(file.tellg());
    auto temp_gvox_model = std::vector<uint8_t>{};
    temp_gvox_model.resize(temp_gvox_model_size);
    {
        // time_t start = clock();
        file.seekg(0, std::ios_base::beg);
        file.read(reinterpret_cast<char *>(temp_gvox_model.data()), static_cast<std::streamsize>(temp_gvox_model_size));
        file.close();
        // time_t end = clock();
        // double cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
        // AppUi::Console::s_instance->add_log("(pulling file into memory: {}s)", cpu_time_used);
    }
    GvoxByteBufferInputAdapterConfig i_config = {
        .data = temp_gvox_model.data(),
        .size = temp_gvox_model_size,
    };
    GvoxByteBufferOutputAdapterConfig o_config = {
        .out_size = &result.size,
        .out_byte_buffer_ptr = &result.ptr,
        .allocate = nullptr,
    };
    void *i_config_ptr = nullptr;
    auto voxlap_config = GvoxVoxlapParseAdapterConfig{
        .size_x = 512,
        .size_y = 512,
        .size_z = 64,
        .make_solid = 1,
        .is_ace_of_spades = 1,
    };
    char const *gvox_model_type = "gvox_palette";
    if (gvox_model_path.has_extension())
    {
        auto ext = gvox_model_path.extension();
        if (ext == ".vox")
        {
            gvox_model_type = "magicavoxel";
        }
        if (ext == ".rle")
        {
            gvox_model_type = "gvox_run_length_encoding";
        }
        if (ext == ".oct")
        {
            gvox_model_type = "gvox_octree";
        }
        if (ext == ".glp")
        {
            gvox_model_type = "gvox_global_palette";
        }
        if (ext == ".brk")
        {
            gvox_model_type = "gvox_brickmap";
        }
        if (ext == ".gvr")
        {
            gvox_model_type = "gvox_raw";
        }
        if (ext == ".vxl")
        {
            i_config_ptr = &voxlap_config;
            gvox_model_type = "voxlap";
        }
    }

#if 0 // we optionally can provide a specified range of the file to parse
    auto region_range = GvoxRegionRange{.offset = {-4, -4, -4}, .extent = {8, 8, 8}};
    auto *region_range_ptr = &region_range;
#else // otherwise, we're going to parse the entire region of the file
    auto *region_range_ptr = (GvoxRegionRange *)nullptr;
#endif

    GvoxAdapterContext *i_ctx = gvox_create_adapter_context(gvox_ctx, gvox_get_input_adapter(gvox_ctx, "byte_buffer"), &i_config);
    GvoxAdapterContext *o_ctx = gvox_create_adapter_context(gvox_ctx, gvox_get_output_adapter(gvox_ctx, "byte_buffer"), &o_config);
    GvoxAdapterContext *p_ctx = gvox_create_adapter_context(gvox_ctx, gvox_get_parse_adapter(gvox_ctx, gvox_model_type), i_config_ptr);
    GvoxAdapterContext *s_ctx = gvox_create_adapter_context(gvox_ctx, gvox_get_serialize_adapter(gvox_ctx, "my_adapter"), nullptr);

    {
        // time_t start = clock();
        gvox_blit_region(
            i_ctx, o_ctx, p_ctx, s_ctx,
            region_range_ptr,
            // GVOX_CHANNEL_BIT_COLOR | GVOX_CHANNEL_BIT_MATERIAL_ID | GVOX_CHANNEL_BIT_EMISSIVITY);
            GVOX_CHANNEL_BIT_COLOR);
        // time_t end = clock();
        // double cpu_time_used = ((double)(end - start)) / CLOCKS_PER_SEC;
        // AppUi::Console::s_instance->add_log("{}s, new size: {} bytes", cpu_time_used, result.size);

        GvoxResult res = gvox_get_result(gvox_ctx);
        // int error_count = 0;
        while (res != GVOX_RESULT_SUCCESS)
        {
            size_t size = 0;
            gvox_get_result_message(gvox_ctx, nullptr, &size);
            char *str = new char[size + 1];
            gvox_get_result_message(gvox_ctx, str, nullptr);
            str[size] = '\0';
            std::cerr << "ERROR loading model: " << str << std::endl;
            gvox_pop_result(gvox_ctx);
            delete[] str;
            res = gvox_get_result(gvox_ctx);
            // ++error_count;
        }
    }

    gvox_destroy_adapter_context(i_ctx);
    gvox_destroy_adapter_context(o_ctx);
    gvox_destroy_adapter_context(p_ctx);
    gvox_destroy_adapter_context(s_ctx);
    return result;
}