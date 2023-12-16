#ifndef PERLIN_HPP
#define PERLIN_HPP

#include "defines.h"
#include "rng.h"

class Perlin {
  public:
    Perlin() {
        ranfloat = new float[Perlin::point_count];
        for (int i = 0; i < Perlin::point_count; ++i) {
            // ranfloat[i] = random_float_rand();
            ranfloat[i] = random_float();
            // ranfloat[i] = 1.0f;
        }

        perm_x = perlin_generate_perm();
        perm_y = perlin_generate_perm();
        perm_z = perlin_generate_perm();
    }

    ~Perlin() {
        delete[] ranfloat;
        delete[] perm_x;
        delete[] perm_y;
        delete[] perm_z;
    }

    float noise(const glm::vec3& p) const {
        auto i = static_cast<int>(4*p.x) & 255;
        auto j = static_cast<int>(4*p.y) & 255;
        auto k = static_cast<int>(4*p.z) & 255;

        return ranfloat[perm_x[i] ^ perm_y[j] ^ perm_z[k]];
    }

    static unsigned int get_size() {
        return Perlin::point_count;
    }

    int* perm_x_data() const {
        return perm_x;
    }

    int* perm_y_data() const {
        return perm_y;
    }

    int* perm_z_data() const {
        return perm_z;
    }

    float* ranfloat_data() const {
        return ranfloat;
    }

  private:
    static const int point_count = 256;
    float* ranfloat;
    int* perm_x;
    int* perm_y;
    int* perm_z;

    static int* perlin_generate_perm() {
        auto p = new int[Perlin::point_count];

        for (int i = 0; i < Perlin::point_count; i++)
            p[i] = i;

        permute(p, Perlin::point_count);

        return p;
    }

    static void permute(int* p, int n) {
        for (int i = n-1; i > 0; i--) {
            int target = random_int(0, i);
            int tmp = p[i];
            p[i] = p[target];
            p[target] = tmp;
        }
    }
};

unsigned char perm[256]= {151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180};

int grad3[16][3] = {{0,1,1},{0,1,-1},{0,-1,1},{0,-1,-1},
                   {1,0,1},{1,0,-1},{-1,0,1},{-1,0,-1},
                   {1,1,0},{1,-1,0},{-1,1,0},{-1,-1,0}, // 12 cube edges
                   {1,0,-1},{-1,0,-1},{0,-1,1},{0,1,1}}; // 4 more to make 16

#include <memory>

std::unique_ptr<unsigned char[]> get_perm_noise_texture()
{
  auto pixels = std::make_unique<unsigned char[]>(256*256*4);
  unsigned int i,j;

  for(i = 0; i<256; i++)
    for(j = 0; j<256; j++) {
      unsigned int offset = (i*256+j)*4;
      unsigned char value = perm[(j+perm[i]) & 0xFF];
      pixels[offset] = grad3[value & 0x0F][0] * 64 + 64;   // Gradient x
      pixels[offset+1] = grad3[value & 0x0F][1] * 64 + 64; // Gradient y
      pixels[offset+2] = grad3[value & 0x0F][2] * 64 + 64; // Gradient z
      pixels[offset+3] = value;                     // Permuted index
    }

    return pixels;
}

#endif // PERLIN_HPP