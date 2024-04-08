#pragma once
#include "defines.h"

#include <memory>
#include <type_traits>

CL_NAMESPACE_BEGIN

template <typename T>
class gpu_allocator
{
public:
  gpu_allocator() = default;
  ~gpu_allocator() = default;
  void printid(T id)
  {
  }
  template <typename... Args>
  T allocate(daxa::Device &device, daxa::BufferId buffer, size_t size, size_t offset, Args... args)
  {
    return T();
  }

  template <typename... Args>
  void deallocate(daxa::Device &device, daxa::BlasId id, Args... args) {}
};

// gpu_allocator specialization for daxa::BlasId
template <>
class gpu_allocator<daxa::BlasId>
{
public:
  gpu_allocator() = default;
  ~gpu_allocator() = default;

  template <typename... Args>
  auto allocate(daxa::Device &device, daxa::BufferId buffer, size_t size, size_t offset, Args... args)
  {
    auto id = device.create_blas_from_buffer({
        .blas_info = {
            .size = size,
            .name = "procedural_blas_" + std::to_string(offset),
        },
        .buffer_id = buffer,
        .offset = offset,
    });
#if TRACE
    std::cout << "  *Allocating BLAS " << id.index << " version " << id.version << std::endl;
#endif
    return id;
  }

  template <typename... Args>
  void deallocate(daxa::Device &device, daxa::BlasId id, Args... args)
  {
#if TRACE
    std::cout << "  *Deallocating BLAS " << id.index << " version " << id.version << std::endl;
#endif
    device.destroy_blas(id);
  }

  void print_id(daxa::BlasId id)
  {
    std::cout << "  *BLAS index: " << id.index << " version: " << id.version << std::endl;
  }
};


// gpu_allocator specialization for daxa::BlasId
template <>
class gpu_allocator<VoxelBuffer>
{
public:
  gpu_allocator() = default;
  ~gpu_allocator() = default;

  template <typename... Args>
  auto allocate(daxa::Device &device, daxa::BufferId buffer, size_t size, size_t offset, Args... args)
  {
    // get index from args
    return VoxelBuffer( { .index = args... });
  }

  template <typename... Args>
  void deallocate(daxa::Device &device, VoxelBuffer v, Args... args)
  {
#if TRACE
    std::cout << "  *Deallocating VoxelRange " << v.index << std::endl;
#endif
  }

  void print_id(VoxelBuffer v)
  {
    std::cout << "  *VoxelBuffer index: " << v.index << std::endl;
  }
};


// T is the element type of the free list
// U is the allocator type

template <typename T, typename U = gpu_allocator<T>>
class gpu_free_list
{
public:
  gpu_free_list(daxa::Device &device, size_t size, BufferId buffer) : m_device(device), m_buffer(buffer)
  {
    static_assert(std::is_base_of<daxa::GPUResourceId, T>::value ||  std::is_base_of<CubelandGPUResource, T>::value, "T is not derived from daxa::GPUResourceId or CubelandGPUResource");
    m_head = std::make_shared<free_list_node>();
    m_head->size = size;
    m_head->offset = 0;
    m_head->next = nullptr;
    m_head->prev = nullptr;
    m_head->data = T();
  }

  ~gpu_free_list() = default;

  // Use the m_allocator to allocate
  template <typename... Args>
  T allocate(size_t size, size_t& offset, Args... args)
  {
    auto node = m_head;
    while (node)
    {
      if (node->size >= size && node->data == T())
      {
        // split the node, save data in the first part and create a new node for the second part
        if (node->size > size)
        {
          // create a new node for the second part
          auto new_node = std::make_shared<free_list_node>();
          new_node->size = node->size - size;
          new_node->offset = node->offset + size;
          new_node->next = node->next;
          new_node->prev = node;
          new_node->data = T();
#if TRACE
          std::cout << "  *Splitting node at offset " << node->offset << " into " << size << " and " << new_node->size << " bytes" << std::endl; 
#endif
          if (node->next)
          {
            node->next->prev = new_node;
          }
          node->next = new_node;

          // allocate the first part
          node->data = m_allocator.allocate(m_device, m_buffer, size, node->offset, args...);
          node->size = size;
#if TRACE
        std::cout << "  *Allocated " << size << " bytes at offset " << node->offset << std::endl;
        m_allocator.print_id(node->data);
        print();
#endif
        } 
        else if(node->size == size)
        {
          node->data = m_allocator.allocate(m_device, m_buffer, size, node->offset, args...);
#if TRACE
        std::cout << "  *Allocated " << size << " bytes at offset " << node->offset << std::endl;
        m_allocator.print_id(node->data);
        print();
#endif
        }
        else
        {
#if WARN
          std::cout << "  *Failed to allocate " << size << " bytes" << std::endl;
#endif
          return T();
        }

        // return the offset
        offset = node->offset;

        return node->data;
      }
      node = node->next;
    }
#if WARN
    std::cout << "  *Failed to allocate " << size << " bytes" << std::endl;
#endif

    return T();
  }

  // Use the m_allocator to deallocate
  template <typename... Args>
  bool deallocate(T data, Args... args)
  {
    auto node = m_head;
    while (node)
    {
      if (node->data == data)
      {
#if TRACE
        std::cout << "  *Deallocating node at offset " << node->offset << " with size " << node->size << std::endl;
#endif
        m_allocator.deallocate(m_device, data, args...);
        node->data = T();

        // merge with the next node if possible
        if (node->next && node->next->data == T())
        {
          node->size += node->next->size;
          node->next = node->next->next;
          if (node->next)
          {
            node->next->prev = node;
          }
#if TRACE
          std::cout << "  *Merging node at offset " << node->offset << " with next node" << std::endl;
#endif
        }

        // merge with the previous node if possible
        if (node->prev && node->prev->data == T())
        {
          node->prev->size += node->size;
          node->prev->next = node->next;
          if (node->next)
          {
            node->next->prev = node->prev;
          }
#if TRACE
          std::cout << "  *Merging node at offset " << node->offset << " with previous node" << std::endl;
#endif
        }


#if TRACE
        std::cout << "  *Deallocated " << std::endl;
        m_allocator.print_id(data);
        print();
#endif
        return true;
      }
      node = node->next;
    }
#if WARN
    std::cout << "  *Failed to deallocate " << std::endl;
#endif
    return false;
  }

  void print()
  {
    auto node = m_head;
    u32 node_count = 0;
    u64 total_size = 0;
    std::cout << "Free list:" << std::endl;
    while (node)
    {
      std::cout << "  *Node at offset " << node->offset << " with size " << node->size << " and data ";
      m_allocator.print_id(node->data);
      total_size += node->size;
      node = node->next;
      node_count++;
    }
    std::cout << "  *Total nodes: " << node_count << " with total size " << total_size << std::endl;
  }

private:
  struct free_list_node
  {
    T data = T();                                   // data
    size_t size = 0;                                // size of the buffer
    size_t offset = 0;                              // offset from the start of the buffer
    std::shared_ptr<free_list_node> next = nullptr; // next node
    std::shared_ptr<free_list_node> prev = nullptr; // previous node
  };

  std::shared_ptr<free_list_node> m_head;
  BufferId m_buffer;
  U m_allocator;
  daxa::Device &m_device;
};

CL_NAMESPACE_END