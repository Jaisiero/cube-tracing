#pragma once

#ifndef CAMERA_H
#define CAMERA_H

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

typedef struct camera {
    glm::vec3 camera_pos = {0, 0, 2.5};
    glm::vec3 camera_center = {0, 0, 0};
    glm::vec3 camera_up = {0, 1, 0};
} camera;

#endif // CAMERA_H