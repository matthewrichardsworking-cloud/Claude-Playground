// Fast line traces for the playtest bot (trace.cpp); shared by dllmain.cpp.
#pragma once
#include <cstdint>

namespace coop_trace
{
    struct Hit
    {
        bool hit = false;
        float point[3] = {0, 0, 0};
        float normal[3] = {0, 0, 0};
        float distance = 0;
        int32_t actor_index = -1;
    };
    auto set_targets(uintptr_t cdo, uintptr_t fn, uintptr_t ctx) -> bool;
    auto set_context(uintptr_t ctx) -> void;
    auto ready() -> bool;
    auto line(const float a[3], const float b[3], Hit& out, double& micros) -> bool;
} // namespace coop_trace
