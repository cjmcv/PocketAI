/*!
* \brief Buffer
*    Used to manage VkBuffer and VkDeviceMemory bound to it
*/

#ifndef POCKET_AI_ENGINE_VULKAN_BUFFER_HPP_
#define POCKET_AI_ENGINE_VULKAN_BUFFER_HPP_

#include <vulkan/vulkan.h>

#include "common.hpp"

namespace pai {
namespace vk {
  
class Buffer {
public:
    // Create VkBuffer, Allocate VkDeviceMemory, and bind the buffer and memory
    static Buffer* Create(VkDevice device, VkPhysicalDeviceMemoryProperties &memory_properties,
                          VkBufferUsageFlags usage_flags, 
                          VkMemoryPropertyFlags memory_flags,
                          VkDeviceSize size){

        VkBufferCreateInfo create_info = {};
        create_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        create_info.pNext = nullptr;
        create_info.flags = 0;
        create_info.size = size;
        create_info.usage = usage_flags;
        create_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

        VkBuffer buffer;
        vkCreateBuffer(device, &create_info, /*pAllocator=*/nullptr, &buffer);
        
        // Get memory requirements for the buffer
        VkMemoryRequirements memory_requirements;
        vkGetBufferMemoryRequirements(device, buffer, &memory_requirements);

        // Allocate memory for the buffer
        VkDeviceMemory memory = AllocateMemory(device, memory_properties, memory_requirements, memory_flags);

        // Bind the memory to the buffer
        vkBindBufferMemory(device, buffer, memory, /*memoryOffset=*/0);

        return new Buffer(device, buffer, size, memory);
    }

    ~Buffer() {
        vkDestroyBuffer(device_, buffer_, /*pAllocator=*/nullptr);
        vkFreeMemory(device_, memory_, /*pAllocator=*/nullptr);
    }

    inline VkBuffer buffer() const { return buffer_; }
    inline uint32_t buffer_size() const { return buffer_size_; }

    // Gets a CPU accessible memory address for the current buffer.
    void *MapMemory(size_t offset, size_t size) {
        void *data = nullptr;
        VK_CHECK(vkMapMemory(device_, memory_, offset, size, /*flags=*/0, &data));
        return data;
    }

    // Invalidate the CPU accessible memory address for the current buffer.
    void UnmapMemory() { vkUnmapMemory(device_, memory_); }

private:
    Buffer(VkDevice device, VkBuffer buffer, VkDeviceSize size, VkDeviceMemory memory)
    : device_(device), buffer_(buffer), buffer_size_(size), memory_(memory) {}

    static uint32_t SelectMemoryType(VkPhysicalDeviceMemoryProperties &memory_properties,
                                     uint32_t supported_memory_types,
                                     VkMemoryPropertyFlags desired_memory_properties) {
        for (uint32_t i = 0; i < memory_properties.memoryTypeCount; ++i) {
            if ((supported_memory_types & (1 << i)) &&
                ((memory_properties.memoryTypes[i].propertyFlags &
                desired_memory_properties) == desired_memory_properties))
            return i;
        }
        PAI_LOGE("Cannot find memory type with required bits.\n");
        return -1;
    }
    static VkDeviceMemory AllocateMemory(VkDevice device, 
                                         VkPhysicalDeviceMemoryProperties &memory_properties,
                                         VkMemoryRequirements memory_requirements,
                                         VkMemoryPropertyFlags memory_flags) {
        VkMemoryAllocateInfo allocate_info = {};
        allocate_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocate_info.pNext = nullptr;
        allocate_info.allocationSize = memory_requirements.size;
        allocate_info.memoryTypeIndex = SelectMemoryType(memory_properties, memory_requirements.memoryTypeBits, memory_flags);

        VkDeviceMemory memory = VK_NULL_HANDLE;
        vkAllocateMemory(device, &allocate_info, /*pAlloator=*/nullptr, &memory);
        return memory;
    }

private: 
    VkDevice device_;

    VkBuffer buffer_;
    uint32_t buffer_size_;
    VkDeviceMemory memory_;
};

}  // end of namespace vk
}  // end of namespace pai

#endif  // POCKET_AI_ENGINE_VULKAN_BUFFER_HPP_
