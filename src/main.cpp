#include <daxa/daxa.hpp>

#include <GLFW/glfw3.h>

struct WindowInfo
{
  daxa::u32 width{}, height{};
  bool swapchain_out_of_date{false};
};

auto main() -> int
{
  auto window_info = WindowInfo{.width = 800, .height = 600};
  glfwInit();
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
  auto *glfw_window_ptr = glfwCreateWindow(window_info.width, window_info.height, "Daxa sample", nullptr, nullptr);
  glfwSetWindowUserPointer(glfw_window_ptr, &window_info);
  glfwSetWindowSizeCallback(glfw_window_ptr, [](GLFWwindow *window, int width, int height)
                            {
    auto *window_info = static_cast<WindowInfo *>(glfwGetWindowUserPointer(window));
    window_info->width = static_cast<daxa::u32>(width);
    window_info->height = static_cast<daxa::u32>(height);
    window_info->swapchain_out_of_date = true; });
  // daxa structs
  daxa::Instance instance = daxa::create_instance({});
  daxa::Device device = instance.create_device({
      .selector = [](daxa::DeviceProperties const &prop) -> daxa::i32
      {
        auto value = daxa::default_device_score(prop);
        return prop.ray_tracing_properties.has_value() ? value : -1;
      },
      .flags = daxa::DeviceFlagBits::RAY_TRACING,
  });

  bool ray_tracing_supported = device.properties().ray_tracing_properties.has_value();
  daxa_u32 invocation_reorder_mode = device.properties().invocation_reorder_properties.has_value() ? device.properties().invocation_reorder_properties.value().invocation_reorder_mode : 0;
  std::string ray_tracing_supported_str = ray_tracing_supported ? "available" : "not available";

  std::cout << "Choosen Device: " << device.properties().device_name << ", Ray Tracing: " << ray_tracing_supported_str << ", Invocation Reordering mode: " << invocation_reorder_mode << std::endl;

  if (ray_tracing_supported == false)
  {
    std::cout << "Ray tracing is not supported" << std::endl;
    abort();
  }

  while (true)
  {
    glfwPollEvents();
    if (glfwWindowShouldClose(glfw_window_ptr))
    {
      break;
    }
  }

  return 0;
}
