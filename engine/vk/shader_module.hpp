/*!
* \brief ShaderModule
*      Create VkShaderModule and VkDescriptorSetLayout based on spir-v code
*/

#ifndef POCKET_AI_ENGINE_VULKAN_SHADER_MODULE_HPP_
#define POCKET_AI_ENGINE_VULKAN_SHADER_MODULE_HPP_

#include <vulkan/vulkan.h>

#include <memory>
#include <unordered_map>
#include <vector>
#include <math.h>
#include "common.hpp"

namespace pai {
namespace vk {

// 
struct DescriptorSetLayout {    
    VkDescriptorSetLayoutCreateInfo create_info;
    std::vector<VkDescriptorSetLayoutBinding> bindings;
    
    VkDescriptorSetLayout layout;
};

class ShaderModule {
public:
    // Creates a Vulkan shader module from SPIR-V code 
    // and creates descriptor set layout objects
    // for each descriptor set in the shader module.
    static ShaderModule *Create(VkDevice device, 
                                std::vector<VkDescriptorType>& buffer_types,
                                const char* filename) {
        uint32_t file_length;
        uint32_t* code = ReadSpvFile(file_length, filename);
        ShaderModule *shader_module = Create(device, buffer_types, code, file_length);
        delete[] code;

        return shader_module;
    }

    static ShaderModule *Create(VkDevice device, 
                                std::vector<VkDescriptorType>& buffer_types,
                                const uint32_t *spirv_data, 
                                size_t spirv_size) {
        // Create the VkShaderModule object for the given SPIR-V code
        VkShaderModuleCreateInfo module_create_info = {};
        module_create_info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        module_create_info.pNext = nullptr;
        module_create_info.flags = 0;
        module_create_info.codeSize = spirv_size;
        module_create_info.pCode = spirv_data;

        VkShaderModule shader_module = VK_NULL_HANDLE;
        vkCreateShaderModule(device, &module_create_info, /*pAllocator=*/nullptr, &shader_module);

        std::vector<DescriptorSetLayout> set_layouts(1); //sets.size() 默认1个描述集
        { // for each DescriptorSetLayout.
            DescriptorSetLayout &layout = set_layouts[0]; // 取第0个
            layout.create_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
            layout.create_info.pNext = nullptr;
            layout.create_info.flags = 0;

            uint32_t binding_count = buffer_types.size();
            layout.bindings.resize(binding_count);
            for (uint32_t i = 0; i < binding_count; ++i) {
                VkDescriptorSetLayoutBinding &binding = layout.bindings[i];
                binding.binding = i;
                binding.descriptorType = buffer_types[i];
                binding.descriptorCount = 1;
                binding.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
                binding.pImmutableSamplers = nullptr;
            }
            layout.create_info.bindingCount = binding_count;
            // layout.create_info.pBindings = layout.bindings.data();
            layout.create_info.pBindings = &(layout.bindings[0]);
        }

        // Create all VkDescriptorSetLayout objects
        for (uint32_t i = 0; i < set_layouts.size(); ++i) {
            vkCreateDescriptorSetLayout(
            device, &set_layouts[i].create_info,
            /*pAllocator=*/nullptr, &set_layouts[i].layout);
        }

        return new ShaderModule(shader_module, device, std::move(set_layouts));
    }

    ~ShaderModule() {
        for (const auto &set_layout : set_layouts_) {
            vkDestroyDescriptorSetLayout(device_, set_layout.layout, /*pAllocator=*/nullptr);
        }
        vkDestroyShaderModule(device_, shader_module_, /*pAllocator=*/nullptr);
    }

    inline VkShaderModule shader_module() const { return shader_module_; }

    inline uint32_t num_sets() const { return set_layouts_.size(); }

    // Returns all descriptor set layout objects for this shader module.
    std::vector<VkDescriptorSetLayout> descriptor_set_layouts() const {
        return vk_set_layouts_; // 移动拷贝
    }

    // Calculates minimal pool size requirements for each descriptor type used in
    // this shader module.
    std::vector<VkDescriptorPoolSize> CalculateDescriptorPoolSize() const  {
        std::unordered_map<VkDescriptorType, uint32_t> descriptor_counts;
        for (const auto &set_layout : set_layouts_) {
            for (const auto &binding : set_layout.bindings) {
                descriptor_counts[binding.descriptorType] += binding.descriptorCount;
            }
        }

        std::vector<VkDescriptorPoolSize> pool_sizes(descriptor_counts.size());
        size_t index = 0;
        for (const auto &descriptor_count : descriptor_counts) {
            pool_sizes[index].type = descriptor_count.first;
            pool_sizes[index].descriptorCount = descriptor_count.second;
            ++index;
        }

        return pool_sizes;
    }

private:
    ShaderModule(VkShaderModule module, VkDevice device,
                 std::vector<DescriptorSetLayout> set_layouts)
        : shader_module_(module),
          device_(device),
          set_layouts_(std::move(set_layouts)) {

        vk_set_layouts_.resize(set_layouts_.size());
        for (uint32_t i = 0; i < set_layouts_.size(); ++i) {
            vk_set_layouts_[i] = set_layouts_[i].layout;
        }
    }

    // Read file into array of bytes, and cast to uint32_t*, then return.
    // The data has been padded, so that it fits into an array uint32_t.
    // glslangValidator.exe -V shader.comp
    static uint32_t* ReadSpvFile(uint32_t& length, const char* filename) {

        FILE* fp = fopen(filename, "rb");
        if (fp == NULL) {
            printf("Could not find or open file: %s\n", filename);
        }

        // get file size.
        fseek(fp, 0, SEEK_END);
        long filesize = ftell(fp);
        fseek(fp, 0, SEEK_SET);

        long filesizepadded = long(ceil(filesize / 4.0)) * 4;

        // read file contents.
        char *str = new char[filesizepadded];
        fread(str, filesize, sizeof(char), fp);
        fclose(fp);

        // data padding. 
        for (int i = filesize; i < filesizepadded; i++) {
            str[i] = 0;
        }

        length = filesizepadded;
        return (uint32_t *)str;
    }

private:
    VkDevice device_;

    VkShaderModule shader_module_;

    std::vector<DescriptorSetLayout> set_layouts_;
    // Taken from set_layouts_，used to specify multiple set layouts 
    // when calling vkCreatePipelineLayout
    std::vector<VkDescriptorSetLayout> vk_set_layouts_;
};

} // namespace vk
} // namespace pai

#endif // UVKC_VULKAN_SHADER_MODULE_H_
