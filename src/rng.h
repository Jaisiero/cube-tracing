#pragma once

#ifndef RANDOM_H
#define RANDOM_H

#include <random>

inline float random_float() {
    static std::uniform_real_distribution<float> distribution(0.0, 1.0);
    static std::mt19937 generator;
    return distribution(generator);
}

inline float random_float(float min, float max) {
    return min + (max - min) * random_float();
}

inline unsigned int random_uint(unsigned int min, unsigned int max) {
    static std::mt19937 generator;
    return std::uniform_int_distribution<unsigned int>{min, max}(generator);
}

inline int random_int(int min, int max) {
    static std::mt19937 generator;
    return std::uniform_int_distribution<int>{min, max}(generator);
}

#endif // RANDOM_H