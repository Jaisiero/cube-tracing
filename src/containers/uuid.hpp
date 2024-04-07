#pragma once
#include "defines.h"

CL_NAMESPACE_BEGIN


// template class for unsigned integer types and size_t
template <typename T, typename = std::enable_if_t<std::is_integral_v<T>>>
class free_uuid_list
{
public:
  free_uuid_list(size_t N) {
    size_ = N;
    free_list_.resize(size_);
    for(T index = 0; index < N; index++) {
      deallocate(index);
    }
  }
  ~free_uuid_list() = default;

  // allocate a new element
  T allocate()
  {
    T new_free_index = 0;
    for(T index = 0; index < size_; index++)
    {
      if(!is_allocated(index))
      {
        // memset to zeros as many bytes as the size of T
        // this is to make sure that the memory is not reused
        set_allocated(index);
        // return the index of the allocated element
        new_free_index = index;
        break;
      }
    }

    return new_free_index;
  }

  // deallocate an element
  void deallocate(T index)
  {
    // memset to ones as many bytes as the size of T
    // this is to make sure that the memory is not reused
    // before the next frame
    for(size_t i = 0; i < sizeof(T); i++)
    {
      *(((u8*)&free_list_[index]) + i) = 0xFF;
    }
  }

  // get the number of free elements
  size_t size() const
  {
    return size_;
  }

private:
  // check if an element is allocated by checking if the element is in the free list
  // A free element has all bytes set to 1
  bool is_allocated(T index)
  {
    for(size_t i = 0; i < sizeof(T); i++)
    {
      if(*(((u8*)&free_list_[index]) + i) != 0xFF)
      {
        return true;
      }
    }
    return false;
  }

  void set_allocated(T index)
  {
    for(size_t i = 0; i < sizeof(T); i++)
    {
      *(((u8*)&free_list_[index]) + i) = 0x00;
    }
  }


  std::vector<T> free_list_;
  T size_;
};


CL_NAMESPACE_END