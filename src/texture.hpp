#pragma once 

#ifndef TEXTURE_HPP
#define TEXTURE_HPP

#include "defines.h"
#include "rtw_stb_image.hpp"
#include "interval.h"

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

    virtual glm::vec3 value(double u, double v, const glm::vec3& p) const = 0;

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

    glm::vec3 value(double u, double v, const glm::vec3& p) const override {
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

    ~ImageTexture() = default;

    const unsigned char* get_data() const {
        return image.data_ptr();
    }

  private:
    RTWimage image;
};
#endif // TEXTURE_HPP