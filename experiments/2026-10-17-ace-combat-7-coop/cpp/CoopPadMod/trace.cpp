// Fast line traces for the playtest bot's "vision" (CoopPadMod, 18 Oct 2026).
//
// From Lua, every call to UKismetSystemLibrary::LineTraceSingle goes through UE4SS's
// general-purpose bridge (every argument and the whole hit result converted to and from
// Lua tables), which measured about 1.2 ms per trace in flight. Here the same engine
// function is called directly: a parameter block is filled in by hand and handed to the
// engine's ProcessEvent through UE4SS's exported UObject::ProcessEvent.
//
// UE4SS's own engine headers are private (cpp\README.md), so this file declares only the
// one exported function it needs, with the exact name UE4SS.dll exports
// (?ProcessEvent@UObject@Unreal@RC@@QEAAXPEAVUFunction@23@PEAX@Z). The function, the
// library's default object and a world-context object (the player's plane) are handed
// over from Lua as addresses (UObject:GetAddress()), so nothing is looked up by guesswork.
//
// The parameter layout is this game build's own, read from its object dump
// (dumps\2026-10-18_ue4ss-in-mission-ex01, KismetSystemLibrary:LineTraceSingle):
//   0x00 WorldContextObject   0x08 Start (3 floats)   0x14 End (3 floats)
//   0x20 TraceChannel (byte)  0x21 bTraceComplex      0x28 ActorsToIgnore (TArray, empty)
//   0x38 DrawDebugType        0x40 OutHit (FHitResult: +0x08 Distance, +0x18 ImpactPoint,
//                                          +0x30 ImpactNormal, +0x64 Actor weak pointer)
//   0xD0 bIgnoreSelf          0xD4 TraceColor  0xE4 TraceHitColor  0xF4 DrawTime
//   0xF8 ReturnValue

#include <cstdint>
#include <cstring>

#include <windows.h>

#include "trace.hpp"

namespace RC::Unreal
{
    class UFunction;
    class UObject
    {
      public:
        auto ProcessEvent(UFunction* function, void* params) -> void;
    };
} // namespace RC::Unreal

namespace coop_trace
{
    namespace
    {
        RC::Unreal::UObject* g_cdo = nullptr;
        RC::Unreal::UFunction* g_fn = nullptr;
        void* g_ctx = nullptr;
        LARGE_INTEGER g_freq{};
    }

    auto set_targets(uintptr_t cdo, uintptr_t fn, uintptr_t ctx) -> bool
    {
        g_cdo = reinterpret_cast<RC::Unreal::UObject*>(cdo);
        g_fn = reinterpret_cast<RC::Unreal::UFunction*>(fn);
        g_ctx = reinterpret_cast<void*>(ctx);
        if (!g_freq.QuadPart) QueryPerformanceFrequency(&g_freq);
        return g_cdo && g_fn && g_ctx;
    }

    auto set_context(uintptr_t ctx) -> void { g_ctx = reinterpret_cast<void*>(ctx); }

    auto ready() -> bool { return g_cdo && g_fn && g_ctx; }

    // One trace from a to b (game units). Returns the hit, and the time it took in microseconds.
    auto line(const float a[3], const float b[3], Hit& out, double& micros) -> bool
    {
        out = Hit{};
        if (!ready()) return false;
        alignas(16) uint8_t p[0x110];
        std::memset(p, 0, sizeof(p));
        std::memcpy(p + 0x00, &g_ctx, sizeof(void*));
        std::memcpy(p + 0x08, a, 12);
        std::memcpy(p + 0x14, b, 12);
        p[0x20] = 0;            // ETraceTypeQuery::TraceTypeQuery1 = the Visibility channel
        p[0x21] = 0;            // simple collision
        p[0x38] = 0;            // no debug drawing
        p[0xD0] = 1;            // ignore the context object itself (the plane)
        LARGE_INTEGER t0, t1;
        QueryPerformanceCounter(&t0);
        g_cdo->ProcessEvent(g_fn, p);
        QueryPerformanceCounter(&t1);
        micros = g_freq.QuadPart ? double(t1.QuadPart - t0.QuadPart) * 1e6 / double(g_freq.QuadPart) : 0;
        out.hit = p[0xF8] != 0;
        if (out.hit)
        {
            std::memcpy(&out.distance, p + 0x40 + 0x08, 4);
            std::memcpy(out.point, p + 0x40 + 0x18, 12);
            std::memcpy(out.normal, p + 0x40 + 0x30, 12);
            std::memcpy(&out.actor_index, p + 0x40 + 0x64, 4);
        }
        return true;
    }
} // namespace coop_trace
