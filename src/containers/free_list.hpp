#pragma once
#include "defines.h"

#include <memory>
#include <type_traits>

CL_NAMESPACE_BEGIN

template <typename T>
class gpu_allocator {
public:
  gpu_allocator() = default;
  ~gpu_allocator() = default;
};


// gpu_allocator specialization for daxa::BlasId
template <>
class gpu_allocator<daxa::BlasId> {
public:
  gpu_allocator() = default;
  ~gpu_allocator() = default;

  auto allocate(daxa::Device& device, daxa::BufferId buffer, size_t size, size_t offset) {
    return device.create_blas_from_buffer({
        .blas_info = {
            .size = size,
            .name = "procedural_blas_" + std::to_string(offset),
        },
        .buffer_id = buffer,
        .offset = offset,
    });
  }

  void deallocate(daxa::Device& device, daxa::BlasId id) {
    device.destroy_blas(id);
  }
};




// T is the element type of the free list
// U is the allocator type

template <typename T, typename U = gpu_allocator<T>>
class gpu_free_list
{
public:
  gpu_free_list(daxa::Device& device, size_t size, BufferId buffer) : m_device(device), m_buffer(buffer) {
    static_assert(std::is_base_of<daxa::GPUResourceId, T>::value, "T is not derived from daxa::GPUResourceId");
    m_head = std::make_shared<free_list_node>();
    m_head->size = size;
    m_head->offset = 0;
    m_head->next = nullptr;
    m_head->prev = nullptr;
    m_head->data = T();
  }

  ~gpu_free_list() = default;
  
  // Use the m_allocator to allocate
  T allocate(size_t size) {
    auto node = m_head;
    while(node) {
      if (node->size >= size && node->data == T()) {
        auto data = m_allocator.allocate(m_device, m_buffer, size, node->offset);
        // split the node, save data in the first part and create a new node for the second part
        if (node->size > size) {
          auto new_node = std::make_shared<free_list_node>();
          new_node->size = node->size - size;
          new_node->offset = node->offset + size;
          new_node->next = node->next;
          new_node->prev = node;
          new_node->data = T();
          if (node->next) {
            node->next->prev = new_node;
          }
          node->next = new_node;
        }

        node->data = data;

        return data;
      }
      node = node->next;
    }
    return T();
  }

  // Use the m_allocator to deallocate
  bool deallocate(T data) {
    auto node = m_head;
    while(node) {
      if (node->data == data) {
        m_allocator.deallocate(m_device, data);
        node->data = T();

        // merge with the next node if possible
        if (node->next && node->next->data == T()) {
          node->size += node->next->size;
          node->next = node->next->next;
          if (node->next) {
            node->next->prev = node;
          }
        }

        // merge with the previous node if possible
        if (node->prev && node->prev->data == T()) {
          node->prev->size += node->size;
          node->prev->next = node->next;
          if (node->next) {
            node->next->prev = node->prev;
          }
        }
        return true;
      }
      node = node->next;
    }
    return false;
  }
  
    

private:

  struct free_list_node {
    T data; // data
    size_t size; // size of the buffer
    size_t offset; // offset from the start of the buffer
    std::shared_ptr<free_list_node> next; // next node
    std::shared_ptr<free_list_node> prev; // previous node
  };
  
  std::shared_ptr<free_list_node> m_head;
  BufferId m_buffer;
  U m_allocator;
  daxa::Device& m_device;
};

CL_NAMESPACE_END