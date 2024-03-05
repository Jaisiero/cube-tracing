#pragma once


#ifndef DAXA_LOD_DEFINES_H
#define DAXA_LOD_DEFINES_H

#include <iostream>

#include <daxa/daxa.hpp>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>

struct GvoxModelData {
    size_t size = 0;
    uint8_t *ptr = nullptr;
};

#endif // DAXA_LOD_DEFINES_H