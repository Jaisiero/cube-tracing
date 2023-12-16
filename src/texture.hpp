#pragma once 

#ifndef TEXTURE_HPP
#define TEXTURE_HPP

#include "defines.h"
#include "rtw_stb_image.hpp"
#include "interval.h"
#include "perlin.hpp"

// #include "perlin.h"
class AbstractTexture {
public:
    virtual ~AbstractTexture () = default;
    virtual std::unique_ptr<AbstractTexture> clone() const = 0;
};

template <typename Derived>
class Texture : public AbstractTexture {
public:
    std::unique_ptr<AbstractTexture> clone() const override {
        return std::make_unique<Derived>(static_cast<Derived const&>(*this));
    }

    virtual glm::vec3 value(float u, float v, const glm::vec3& p) const = 0;

protected:
   // We make clear Texture class needs to be inherited
   Texture() = default;
   Texture(const Texture&) = default;
   Texture(Texture&&) = default;
};


// TODO: solid_color texture?
class ImageTexture : public Texture<ImageTexture> {
  public:
    ImageTexture(const char* filename) : image(filename) {}

    glm::vec3 value(float u, float v, const glm::vec3& p) const override {
        // If we have no texture data, then return solid cyan as a debugging aid.
        if (image.height() <= 0) return glm::vec3(0,1,1);

        // Clamp input texture coordinates to [0,1] x [1,0]
        u = interval(0,1).clamp(u);
        v = 1.0 - interval(0,1).clamp(v);  // Flip V to image coordinates

        auto i = static_cast<int>(u * image.width());
        auto j = static_cast<int>(v * image.height());
        auto pixel = image.pixel_data(i,j);

        auto color_scale = 1.0 / 255.0;
        return glm::vec3(color_scale*pixel[0], color_scale*pixel[1], color_scale*pixel[2]);
    }

    unsigned int get_size() const {
        return image.size();
    }

    unsigned int get_width() const {
        return image.width();
    }

    unsigned int get_height() const {
        return image.height();
    }

    const unsigned char* get_data() const {
        return image.data_ptr();
    }

    ~ImageTexture() = default;

  private:
    RTWimage image;
};

class NoiseTexture : public Texture<ImageTexture> {
  public:
    NoiseTexture() {}

    glm::vec3 value(float u, float v, const glm::vec3& p) const override {
        return glm::vec3(1,1,1) * noise.noise(p);
    }

    unsigned int get_size() const {
        return noise.get_size();
    }

    unsigned int get_pixel_count() const {
        return get_size() * 4;
    }

    unsigned int get_pixel_count_in_bytes() const {
        return noise.get_size() * sizeof(int) * 3 + noise.get_size() * sizeof(float);
    }

    unsigned int get_perm_x_size_in_bytes() const {
        return noise.get_size() * sizeof(int);
    }

    unsigned int get_perm_y_size_in_bytes() const {
        return noise.get_size() * sizeof(int);
    }

    unsigned int get_perm_z_size_in_bytes() const {
        return noise.get_size() * sizeof(int);
    }

    unsigned int get_ranfloat_size_in_bytes() const {
        return noise.get_size() * sizeof(float);
    }

    int* get_perm_x_data() const {
        return noise.perm_x_data();
    }

    int* get_perm_y_data() const {
        return noise.perm_y_data();
    }

    int* get_perm_z_data() const {
        return noise.perm_z_data();
    }

    float* get_ranfloat_data() const {
        return noise.ranfloat_data();
    }

    ~NoiseTexture() = default;

  private:
    Perlin noise;
};
#endif // TEXTURE_HPP