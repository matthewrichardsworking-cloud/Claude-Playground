// CoopPad xinput1_3.dll: a stand-in for Windows' gamepad library, for the AC7 test copy only.
//
// The playtest bot's pilot (the CoopPilotMod Lua script) has to work the plane's controls,
// and the game takes no notice of control values a script writes into the plane (18 Oct
// 2026, workbench section 10): it reads them fresh from the keyboard and gamepad every
// frame. So the pilot works a virtual gamepad instead, the way a person would.
//
// How: the game (Ace7Game.exe, Unreal Engine 4.18) loads "XINPUT1_3.dll" and uses two of
// its functions, by number: 2 = XInputGetState (read a gamepad) and 3 = XInputSetState
// (vibration). Windows looks for a DLL in the program's own folder first, so this file,
// placed at C:\AC7-Coop-Game\xinput1_3.dll, is the one the copy loads. It passes every call
// on to the real C:\Windows\System32\xinput1_3.dll, except one thing: gamepad 1 (index 0)
// shows the virtual pad's sticks, triggers and buttons while the pilot is driving it
// (it was set within the last half second). When the pilot is not driving, a real gamepad
// in slot 1 works as normal; without one, slot 1 reports a gamepad at rest, so that the
// engine keeps polling it (Unreal only polls a slot again after a device change).
//
// The pilot sets the pad through CoopPad_Set, exported by name; the CoopPadMod UE4SS
// add-on calls it on behalf of Lua scripts. No game code is changed, and the real install
// is not touched (only the copy's folder has this file).

#include <windows.h>

// The XInput types, written out here instead of including <xinput.h>: that header declares
// the functions this file defines, with a different exception specification.
struct XINPUT_GAMEPAD { WORD wButtons; BYTE bLeftTrigger; BYTE bRightTrigger; SHORT sThumbLX; SHORT sThumbLY; SHORT sThumbRX; SHORT sThumbRY; };
struct XINPUT_STATE { DWORD dwPacketNumber; XINPUT_GAMEPAD Gamepad; };
struct XINPUT_VIBRATION { WORD wLeftMotorSpeed; WORD wRightMotorSpeed; };
struct XINPUT_CAPABILITIES { BYTE Type; BYTE SubType; WORD Flags; XINPUT_GAMEPAD Gamepad; XINPUT_VIBRATION Vibration; };
struct XINPUT_BATTERY_INFORMATION { BYTE BatteryType; BYTE BatteryLevel; };
struct XINPUT_KEYSTROKE { WORD VirtualKey; WCHAR Unicode; WORD Flags; BYTE UserIndex; BYTE HidCode; };
using PXINPUT_KEYSTROKE = XINPUT_KEYSTROKE*;
constexpr BYTE XINPUT_DEVTYPE_GAMEPAD = 0x01;
constexpr BYTE XINPUT_DEVSUBTYPE_GAMEPAD = 0x01;

#include <cstdio>
#include <cstring>
#include <intrin.h>

namespace
{
    // ---- the real library, loaded on first use (not in DllMain: loader lock) ------------
    using GetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
    using SetStateFn = DWORD(WINAPI*)(DWORD, XINPUT_VIBRATION*);
    using GetCapsFn = DWORD(WINAPI*)(DWORD, DWORD, XINPUT_CAPABILITIES*);
    using EnableFn = void(WINAPI*)(BOOL);
    using GetDSoundFn = DWORD(WINAPI*)(DWORD, GUID*, GUID*);
    using GetBatteryFn = DWORD(WINAPI*)(DWORD, BYTE, XINPUT_BATTERY_INFORMATION*);
    using GetKeystrokeFn = DWORD(WINAPI*)(DWORD, DWORD, PXINPUT_KEYSTROKE);
    using Ord100Fn = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
    using Ord101Fn = DWORD(WINAPI*)(DWORD, DWORD, void*);
    using Ord102Fn = DWORD(WINAPI*)(DWORD);
    using Ord103Fn = DWORD(WINAPI*)(DWORD);

    HMODULE g_real = nullptr;
    INIT_ONCE g_once = INIT_ONCE_STATIC_INIT;

    BOOL CALLBACK load_real(PINIT_ONCE, PVOID, PVOID*)
    {
        wchar_t path[MAX_PATH];
        UINT n = GetSystemDirectoryW(path, MAX_PATH);
        if (n == 0 || n > MAX_PATH - 20) return TRUE;
        wcscat_s(path, L"\\xinput1_3.dll");
        g_real = LoadLibraryW(path);
        return TRUE;
    }

    FARPROC real(const char* name_or_ordinal)
    {
        InitOnceExecuteOnce(&g_once, load_real, nullptr, nullptr);
        return g_real ? GetProcAddress(g_real, name_or_ordinal) : nullptr;
    }

    // ---- the virtual pad -------------------------------------------------------------
    SRWLOCK g_lock = SRWLOCK_INIT;
    XINPUT_GAMEPAD g_pad{};
    ULONGLONG g_set_at = 0;          // GetTickCount64 of the last CoopPad_Set
    DWORD g_packet = 1;
    volatile LONG64 g_polls = 0, g_virtual_polls = 0, g_sets = 0;
    volatile LONG64 g_index_polls[4] = {0, 0, 0, 0}, g_caps_calls = 0, g_setstate_calls = 0, g_ex_calls = 0;

    // Where the reads come from (the first four different callers), for the log.
    void* g_callers[4] = {nullptr, nullptr, nullptr, nullptr};
    volatile LONG g_ncallers = 0;
    void note_caller(void* ra)
    {
        LONG n = g_ncallers;
        for (LONG i = 0; i < n && i < 4; ++i) if (g_callers[i] == ra) return;
        if (n < 4 && InterlockedCompareExchange(&g_ncallers, n + 1, n) == n) g_callers[n] = ra;
    }
    void describe(void* addr, char* out, int size)
    {
        HMODULE m = nullptr;
        char name[MAX_PATH] = "?";
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               static_cast<LPCSTR>(addr), &m) && m)
        {
            GetModuleFileNameA(m, name, MAX_PATH);
            const char* base = strrchr(name, 0x5C);   // the last backslash
            _snprintf_s(out, size, _TRUNCATE, "%s+0x%llx", base ? base + 1 : name,
                        static_cast<unsigned long long>(static_cast<char*>(addr) - reinterpret_cast<char*>(m)));
            return;
        }
        _snprintf_s(out, size, _TRUNCATE, "%p", addr);
    }
    constexpr ULONGLONG DRIVING_MS = 500;

    SHORT stick(float v)
    {
        if (v != v) v = 0;           // NaN
        if (v > 1) v = 1;
        if (v < -1) v = -1;
        return static_cast<SHORT>(v >= 0 ? v * 32767.0f : v * 32768.0f);
    }

    BYTE trigger(float v)
    {
        if (v != v) v = 0;
        if (v > 1) v = 1;
        if (v < 0) v = 0;
        return static_cast<BYTE>(v * 255.0f + 0.5f);
    }

    bool driving_copy(XINPUT_GAMEPAD& out)
    {
        AcquireSRWLockShared(&g_lock);
        bool on = g_set_at != 0 && GetTickCount64() - g_set_at < DRIVING_MS;
        out = g_pad;
        ReleaseSRWLockShared(&g_lock);
        return on;
    }
}

extern "C"
{
    // ---- XInput (the game's two, and the rest for completeness) ------------------------
    DWORD WINAPI XInputGetState(DWORD index, XINPUT_STATE* state)
    {
        InterlockedIncrement64(&g_polls);
        if (index < 4) InterlockedIncrement64(&g_index_polls[index]);
        note_caller(_ReturnAddress());
        auto fn = reinterpret_cast<GetStateFn>(real("XInputGetState"));
        if (index == 0 && state)
        {
            XINPUT_GAMEPAD pad;
            if (driving_copy(pad))
            {
                InterlockedIncrement64(&g_virtual_polls);
                state->dwPacketNumber = g_packet;
                state->Gamepad = pad;
                return ERROR_SUCCESS;
            }
            if (fn && fn(index, state) == ERROR_SUCCESS) return ERROR_SUCCESS;   // a real pad in slot 1
            ZeroMemory(state, sizeof(*state));                                   // a pad at rest
            state->dwPacketNumber = g_packet;
            return ERROR_SUCCESS;
        }
        return fn ? fn(index, state) : ERROR_DEVICE_NOT_CONNECTED;
    }

    DWORD WINAPI XInputSetState(DWORD index, XINPUT_VIBRATION* vib)
    {
        InterlockedIncrement64(&g_setstate_calls);
        auto fn = reinterpret_cast<SetStateFn>(real("XInputSetState"));
        DWORD r = fn ? fn(index, vib) : ERROR_DEVICE_NOT_CONNECTED;
        return index == 0 ? ERROR_SUCCESS : r;   // slot 1 always "has" a pad now
    }

    DWORD WINAPI XInputGetCapabilities(DWORD index, DWORD flags, XINPUT_CAPABILITIES* caps)
    {
        InterlockedIncrement64(&g_caps_calls);
        auto fn = reinterpret_cast<GetCapsFn>(real("XInputGetCapabilities"));
        DWORD r = fn ? fn(index, flags, caps) : ERROR_DEVICE_NOT_CONNECTED;
        if (index == 0 && r != ERROR_SUCCESS && caps)
        {
            ZeroMemory(caps, sizeof(*caps));
            caps->Type = XINPUT_DEVTYPE_GAMEPAD;
            caps->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
            caps->Gamepad.wButtons = 0xF3FF;
            caps->Gamepad.bLeftTrigger = caps->Gamepad.bRightTrigger = 0xFF;
            caps->Gamepad.sThumbLX = caps->Gamepad.sThumbLY = caps->Gamepad.sThumbRX = caps->Gamepad.sThumbRY = static_cast<SHORT>(0xFFC0);
            return ERROR_SUCCESS;
        }
        return r;
    }

    void WINAPI XInputEnable(BOOL enable)
    {
        if (auto fn = reinterpret_cast<EnableFn>(real("XInputEnable"))) fn(enable);
    }

    DWORD WINAPI XInputGetDSoundAudioDeviceGuids(DWORD index, GUID* render, GUID* capture)
    {
        auto fn = reinterpret_cast<GetDSoundFn>(real("XInputGetDSoundAudioDeviceGuids"));
        return fn ? fn(index, render, capture) : ERROR_DEVICE_NOT_CONNECTED;
    }

    DWORD WINAPI XInputGetBatteryInformation(DWORD index, BYTE type, XINPUT_BATTERY_INFORMATION* info)
    {
        auto fn = reinterpret_cast<GetBatteryFn>(real("XInputGetBatteryInformation"));
        return fn ? fn(index, type, info) : ERROR_DEVICE_NOT_CONNECTED;
    }

    DWORD WINAPI XInputGetKeystroke(DWORD index, DWORD reserved, PXINPUT_KEYSTROKE ks)
    {
        auto fn = reinterpret_cast<GetKeystrokeFn>(real("XInputGetKeystroke"));
        return fn ? fn(index, reserved, ks) : ERROR_DEVICE_NOT_CONNECTED;
    }

    // The unnamed ones (100 = XInputGetStateEx, 101-103 = guide button and power off).
    DWORD WINAPI CoopPad_Ord100(DWORD index, XINPUT_STATE* state)
    {
        InterlockedIncrement64(&g_ex_calls);
        auto fn = reinterpret_cast<Ord100Fn>(real(MAKEINTRESOURCEA(100)));
        if (index == 0) return XInputGetState(index, state);
        return fn ? fn(index, state) : ERROR_DEVICE_NOT_CONNECTED;
    }
    DWORD WINAPI CoopPad_Ord101(DWORD index, DWORD flags, void* overlapped)
    {
        auto fn = reinterpret_cast<Ord101Fn>(real(MAKEINTRESOURCEA(101)));
        return fn ? fn(index, flags, overlapped) : ERROR_DEVICE_NOT_CONNECTED;
    }
    DWORD WINAPI CoopPad_Ord102(DWORD index)
    {
        auto fn = reinterpret_cast<Ord102Fn>(real(MAKEINTRESOURCEA(102)));
        return fn ? fn(index) : ERROR_DEVICE_NOT_CONNECTED;
    }
    DWORD WINAPI CoopPad_Ord103(DWORD index)
    {
        auto fn = reinterpret_cast<Ord103Fn>(real(MAKEINTRESOURCEA(103)));
        return fn ? fn(index) : ERROR_DEVICE_NOT_CONNECTED;
    }

    // ---- for the pilot ---------------------------------------------------------------
    // Sticks -1..1 (left x = right, y = up), triggers 0..1, buttons = XINPUT_GAMEPAD_* bits.
    __declspec(dllexport) void __cdecl CoopPad_Set(float lx, float ly, float rx, float ry, float lt, float rt, unsigned buttons)
    {
        XINPUT_GAMEPAD p{};
        p.sThumbLX = stick(lx);
        p.sThumbLY = stick(ly);
        p.sThumbRX = stick(rx);
        p.sThumbRY = stick(ry);
        p.bLeftTrigger = trigger(lt);
        p.bRightTrigger = trigger(rt);
        p.wButtons = static_cast<WORD>(buttons);
        AcquireSRWLockExclusive(&g_lock);
        if (memcmp(&p, &g_pad, sizeof(p)) != 0) ++g_packet;
        g_pad = p;
        g_set_at = GetTickCount64();
        ReleaseSRWLockExclusive(&g_lock);
        InterlockedIncrement64(&g_sets);
    }

    // Lets go of the pad at once (instead of after half a second).
    __declspec(dllexport) void __cdecl CoopPad_Release()
    {
        AcquireSRWLockExclusive(&g_lock);
        g_pad = XINPUT_GAMEPAD{};
        g_set_at = 0;
        ++g_packet;
        ReleaseSRWLockExclusive(&g_lock);
    }

    // One line for the log: how often the game polled, how often it saw the virtual pad.
    __declspec(dllexport) int __cdecl CoopPad_Stats(char* buf, int size)
    {
        XINPUT_GAMEPAD p;
        bool on = driving_copy(p);
        char callers[4][160] = {"", "", "", ""};
        for (LONG i = 0; i < g_ncallers && i < 4; ++i) describe(g_callers[i], callers[i], sizeof(callers[i]));
        return _snprintf_s(buf, size, _TRUNCATE,
                           "CoopPad xinput1_3: real library %s, game polls %lld (pads 1-4: %lld %lld %lld %lld; GetStateEx %lld, GetCapabilities %lld, SetState %lld), polls that saw the virtual pad %lld, sets %lld, driving %s (lx %d ly %d rx %d ry %d lt %u rt %u buttons 0x%04x); callers %s %s %s %s",
                           g_real ? "loaded" : "not loaded yet", g_polls, g_index_polls[0], g_index_polls[1], g_index_polls[2], g_index_polls[3],
                           g_ex_calls, g_caps_calls, g_setstate_calls, g_virtual_polls, g_sets, on ? "yes" : "no",
                           p.sThumbLX, p.sThumbLY, p.sThumbRX, p.sThumbRY, p.bLeftTrigger, p.bRightTrigger, p.wButtons,
                           callers[0], callers[1], callers[2], callers[3]);
    }
}

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) { return TRUE; }
