#pragma once

#include "defines.slang"

[[vk::push_constant]] mpm_push_constant p;

// TODO: move to material
const bool plastic = true;

float3x3 outer_product(float3 a, float3 b) {
    // Compute the outer product of two 3D vectors a and b
    return float3x3(
        a.x * b.x, a.x * b.y, a.x * b.z,
        a.y * b.x, a.y * b.y, a.y * b.z,
        a.z * b.x, a.z * b.y, a.z * b.z
    );
}

float3x3 inverse(float3x3 A) {
    // Compute the inverse of the 3x3 matrix A
    float3x3 inv_A;
    
    // Compute the determinant of A
    float det_A = A[0][0] * (A[1][1] * A[2][2] - A[1][2] * A[2][1]) - A[0][1] * (A[1][0] * A[2][2] - A[1][2] * A[2][0]) + A[0][2] * (A[1][0] * A[2][1] - A[1][1] * A[2][0]);
    
    // Compute the inverse of A using the adjugate matrix
    inv_A[0] = float3(A[1][1] * A[2][2] - A[1][2] * A[2][1], A[0][2] * A[2][1] - A[0][1] * A[2][2], A[0][1] * A[1][2] - A[0][2] * A[1][1]) / det_A;
    inv_A[1] = float3(A[1][2] * A[2][0] - A[1][0] * A[2][2], A[0][0] * A[2][2] - A[0][2] * A[2][0], A[0][2] * A[1][0] - A[0][0] * A[1][2]) / det_A;
    inv_A[2] = float3(A[1][0] * A[2][1] - A[1][1] * A[2][0], A[0][1] * A[2][0] - A[0][0] * A[2][1], A[0][0] * A[1][1] - A[0][1] * A[1][0]) / det_A;
    
    return inv_A;
}

void eigen(float3x3 A, out float3x3 eigenvectors, out float3 eigenvalues) {
    // Compute the eigenvalues and eigenvectors of the symmetric matrix A
    // A symmetric matrix has real eigenvalues and orthogonal eigenvectors
    
    // Compute the characteristic polynomial coefficients
    float a = 1.0;
    float b = -(A[0][0] + A[1][1] + A[2][2]);
    float c = A[0][0] * A[1][1] + A[0][0] * A[2][2] + A[1][1] * A[2][2] - A[0][1] * A[1][0] - A[0][2] * A[2][0] - A[1][2] * A[2][1];
    
    // Solve the characteristic polynomial for the eigenvalues using the quadratic formula
    float discriminant = b * b - 4.0 * a * c;
    float sqrt_discriminant = sqrt(abs(discriminant));
    
    // Compute the eigenvalues
    eigenvalues = float3((-b + sqrt_discriminant) / (2.0 * a), (-b - sqrt_discriminant) / (2.0 * a), A[2][2]);
    
    // Compute the eigenvectors from the eigenvalues
    float3x3 I = float3x3(1.0);
    float3x3 shifted_A = A - float3x3(eigenvalues[0] * I[0], eigenvalues[1] * I[1], eigenvalues[2] * I[2]);
    eigenvectors = inverse(shifted_A);
}

void svd(float3x3 A, out float3x3 U, out float3x3 S, out float3x3 V) {
    // Compute the singular value decomposition (SVD) of the input matrix A
    // The SVD decomposes A into three matrices: U, sig, and V such that A = U * diag(sig) * transpose(V)
    
    // Step 1: Compute the symmetric matrix A^T * A
    float3x3 ATA = transpose(A) * A;
    
    // Step 2: Compute the eigenvalues and eigenvectors of ATA
    float3x3 eigenvectors;
    float3 eigenvalues;
    eigen(ATA, eigenvectors, eigenvalues);
    
    // Step 3: Compute the singular values from the square roots of the eigenvalues
    float3 sig = sqrt(eigenvalues);
    
    // Step 4: Compute the right singular vectors (V) from the eigenvectors of ATA
    V = eigenvectors;

    S = float3x3(
        float3(sig.x, 0.0, 0.0),
        float3(0.0, sig.y, 0.0),
        float3(0.0, 0.0, sig.z)
    );
    
    // Step 5: Compute the left singular vectors (U) from the singular values and right singular vectors
    U = A * V * inverse(S);
} 

void polar_decomposition(float3x3 F, out float3x3 R, out float3x3 S) {
  // Initialize R as F to make sure it has the same size
    R = F;
    
    // Perform the polar decomposition using Singular Value Decomposition (SVD)
    // Use SVD to decompose F into U, S, and V, where:
    // F = U * S * transpose(V)
    // R = U * transpose(V)
    
    float3x3 U, V;
    svd(F, U, S, V);
    
    // Set R to be the product of U and transpose(V)
    R = mul(U, transpose(V));
}

// __glsl_extension(GL_EXT_shader_atomic_float)
// float spvAtomicAdd(__ref float value, float amount)
// {
//     return spirv_asm
//     {
//         OpExtension "SPV_EXT_shader_atomic_float_add";
//         OpCapability AtomicFloat32AddEXT;
//         result:$$float = OpAtomicFAddEXT &value Device None $amount
//     };
// }

// float atomicAdd(__ref float value, float amount)
// {
//     __target_switch
//     {
//     // case cpp:
//     //     __requirePrelude("#include <atomic>");
//     //     __intrinsic_asm "std::atomic_ref(*$0).fetch_add($1)";
//     case spirv:
//         return __atomicAdd(value, amount);
//     }
//     return 0;
// }

        
[shader("compute")]
    [numthreads(MPM_P2G_COMPUTE_X, 1, 1)] void
    entry_MPM_P2G(uint3 pixel_i : SV_DispatchThreadID)
{
  Ptr<Status> status =
      Ptr<Status>(p.head.status_buffer);

  Ptr<WORLD> world =
      Ptr<WORLD>(p.head.world_buffer);

  Ptr<MPM_CONFIG> MPM_config =
      Ptr<MPM_CONFIG>(world->mpm_config_address);

  if (pixel_i.x >= MPM_config->p_count)
  {
    return;
  }

  float inv_dx = MPM_config->inv_dx;
  float dt = MPM_config->dt;

  PRIMITIVE particle = Ptr<PRIMITIVE>(world->primitive_address)[pixel_i.x];
  AABB aabb = Ptr<AABB>(world->aabb_address)[pixel_i.x];
  MATERIAL material = Ptr<MATERIAL>(world->material_address)[particle.material_index];

  float3 particle_center = (aabb.maximum + aabb.minimum) * 0.5f;
  float3 particle_center_dx = particle_center * inv_dx - float3(0.5f, 0.5f, 0.5f);

  int3 base_coord = int3(particle_center_dx); // Floor

  float3 fx = particle_center_dx - base_coord; // Fractional

  // Cubic kernels
  float3 w[3] = { float3(0.5f) * pow(1.5f - abs(fx - float3(0.5f)), 2), float3(0.75f) * pow(1.5f - abs(fx - float3(0.5f)), 2), float3(1.125f) * pow(1.5f - abs(fx - float3(0.5f)), 2) };

  float e = exp(material.hardening * (1.f - particle.Jp));
  float mu = material.mu_0 * e;
  float lambda = material.lambda_0 * e;
  
  float J = determinant(particle.F); // current volume
  
  // TODO: check this for 3D
  float3x3 r, s;
  polar_decomposition(particle.F, r, s); // Polar decomposition for fixed corotated model

  // TODO: check this 3D
  float3x3 stress = -4 * inv_dx * inv_dx * dt * material.volume * (2 * mu * (particle.F - r) * transpose(particle.F) + lambda * (J - 1) * J); //* particle.F);

  float3x3 affine = stress + material.mass * particle.C;

  // Transactional momentum
  float4 mv = float4(material.mass * particle.velocity, material.mass);

  uint3 array_grid = uint3((MPM_config->grid_dim * 0.5) + base_coord);

  // Scatter to grid
  for(uint i = 0; i < 3; ++i) {
    for(uint j = 0; j < 3; ++j) {
      for(uint k = 0; k < 3; ++k) {
        uint3 coord = array_grid + daxa_u32vec3(i, j, k);
        float3 dpos = float3(i, j, k) - fx;

        float weight = w[i].x * w[j].y * w[k].z;

        float4 velocity_mass = weight * (mv + float4(mul(affine, dpos), 0));

        uint index = (coord.x + coord.y * MPM_config->grid_dim.x + coord.z * MPM_config->grid_dim.x * MPM_config->grid_dim.y);
        index = min(index, MPM_config->grid_dim.x * MPM_config->grid_dim.y * MPM_config->grid_dim.z - 1);
        float4 old_vel_mass_value;

        Ptr<MPM_CELL> cell = &Ptr<MPM_CELL>(world->mpm_grid_address)[index];
        // cell->info = float4(particle_center_dx, 0);
        cell->info += velocity_mass;
        // TODO: Test
        // cell->base_coord = base_coord;
        // cell->array_grid = uint3(index, 0, 0);
        // TODO: Test
        
        // Ptr<MPM_CELL> cell = &Ptr<MPM_CELL>(world->mpm_grid_address)[0];
        // cell->info += 1.f;
        // Ptr<float4> cell_info = &cell->info;
        // Ptr<float> cell_info_x = &cell_info[0].x;

        // Ptr<float> grid_x = &Ptr<float>(world->mpm_grid_address)[index];
        // Ptr<float> grid_y = &Ptr<float>(world->mpm_grid_address)[index + 1];
        // Ptr<float> grid_z = &Ptr<float>(world->mpm_grid_address)[index + 2];
        // Ptr<float> grid_w = &Ptr<float>(world->mpm_grid_address)[index + 3];

        // old_vel_mass_value.x = atomicAdd(*grid_x, velocity_mass.x);
        // old_vel_mass_value.y = atomicAdd(*grid_y, velocity_mass.y);
        // old_vel_mass_value.z = atomicAdd(*grid_z, velocity_mass.z);
        // old_vel_mass_value.w = atomicAdd(*grid_w, velocity_mass.w);
      }
    }
  }
}


[shader("compute")]
    [numthreads(MPM_GRID_COMPUTE_X, MPM_GRID_COMPUTE_Y, MPM_GRID_COMPUTE_Z)] void
    entry_MPM_grid(uint3 pixel_i : SV_DispatchThreadID)
{
  Ptr<Status> status =
      Ptr<Status>(p.head.status_buffer);

  Ptr<WORLD> world =
      Ptr<WORLD>(p.head.world_buffer);

  Ptr<MPM_CONFIG> MPM_config =
      Ptr<MPM_CONFIG>(world->mpm_config_address);

  if (pixel_i.x >= MPM_config->grid_dim.x || pixel_i.y >= MPM_config->grid_dim.y || pixel_i.z >= MPM_config->grid_dim.z)
  {
    return;
  }

  float dt = MPM_config->dt;

  uint cell_index = pixel_i.x + pixel_i.y * MPM_config->grid_dim.x + pixel_i.z * MPM_config->grid_dim.x * MPM_config->grid_dim.y;

  Ptr<MPM_CELL> cell = &Ptr<MPM_CELL>(world->mpm_grid_address)[cell_index];

  if(cell->info.w > 0) {
    cell->info /= cell->info.w; // Normalize by mass
    cell->info += dt * float4(0, MPM_config->gravity, 0, 0); // Gravity
  }
}


[shader("compute")]
    [numthreads(MPM_P2G_COMPUTE_X, 1, 1)] void
    entry_MPM_G2P(uint3 pixel_i : SV_DispatchThreadID)
{
  Ptr<Status> status =
      Ptr<Status>(p.head.status_buffer);

  Ptr<WORLD> world =
      Ptr<WORLD>(p.head.world_buffer);

  Ptr<MPM_CONFIG> MPM_config =
      Ptr<MPM_CONFIG>(world->mpm_config_address);

  if (pixel_i.x >= MPM_config->p_count)
  {
    return;
  }

  float inv_dx = MPM_config->inv_dx;
  float dt = MPM_config->dt;

  PRIMITIVE particle = Ptr<PRIMITIVE>(world->primitive_address)[pixel_i.x];
  AABB aabb = Ptr<AABB>(world->aabb_address)[pixel_i.x];
  MATERIAL material = Ptr<MATERIAL>(world->material_address)[particle.material_index];

  if(particle.material_index < 12) {
    return;
  }
  
  float3 particle_center = (aabb.maximum + aabb.minimum) * 0.5f;
  float3 particle_center_dx = particle_center * inv_dx - float3(0.5f, 0.5f, 0.5f);

  int3 base_coord = int3(particle_center_dx); // Floor

  float3 fx = particle_center_dx - base_coord; // Fractional

  // Cubic kernels
  float3 w[3] = { float3(0.5f) * pow(1.5f - abs(fx - float3(0.5f)), 2), float3(0.75f) * pow(1.5f - abs(fx - float3(0.5f)), 2), float3(1.125f) * pow(1.5f - abs(fx - float3(0.5f)), 2) };

  particle.C = float3x3(0);
  particle.velocity = float3(0);
  
  uint3 array_grid = uint3((MPM_config->grid_dim * 0.5) + base_coord);

  for(uint i = 0; i < 3; ++i) {
    for(uint j = 0; j < 3; ++j) {
      for(uint k = 0; k < 3; ++k) {
        int3 coord = array_grid + int3(i, j, k);
        float3 dpos = float3(i, j, k) - fx;

        float weight = w[i].x * w[j].y * w[k].z;

        uint index = coord.x + coord.y * MPM_config->grid_dim.x + coord.z * MPM_config->grid_dim.x * MPM_config->grid_dim.y;

        float4 grid_value = Ptr<MPM_CELL>(world->mpm_grid_address)[index].info;

        particle.velocity += weight * grid_value.xyz; // Velocity
        particle.C += 4 * inv_dx * outer_product(weight * grid_value.xyz, dpos); // APIC C
      }
    }
  }

  // Advect particle
  if(isnan(particle.velocity.x) || isnan(particle.velocity.y) || isnan(particle.velocity.z)) {
    particle.velocity = float3(0);
  }
  if(isinf(particle.velocity.x) || isinf(particle.velocity.y) || isinf(particle.velocity.z)) {
    particle.velocity = float3(0);
  }
  aabb.minimum += particle.velocity * dt;
  aabb.maximum += particle.velocity * dt;

  // Update particle position
  Ptr<AABB>(world->aabb_address)[pixel_i.x] = aabb;

  float3x3 F = (float3x3(1) + dt * particle.C) * particle.F; // MLS-MPM F-update

  float3x3 svd_u, sig, svd_v;
  svd(F, svd_u, sig, svd_v);

  for(uint i = 0; i < 2 * (plastic ? 1 : 0); ++i) {
    // TODO: check this for other materials
    sig[i][i] = clamp(sig[i][i], 1.0_f - 2.5e-2_f, 1.0_f + 7.5e-3_f); // Snow plasticity
  }

  float oldJ = determinant(F);
  F = mul(svd_u, mul(float3x3(sig), transpose(svd_v))); // Update deformation gradient

  // TODO: why this values?
  float Jp = clamp(particle.Jp * oldJ / determinant(F), 0.6_f, 20.0_f); // Plasticity
  
  particle.F = F;
  particle.Jp = Jp;

  // TODO: optimize this write
  Ptr<PRIMITIVE>(world->primitive_address)[pixel_i.x] = particle;
}