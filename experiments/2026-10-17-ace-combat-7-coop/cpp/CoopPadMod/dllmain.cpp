// CoopPadMod: a UE4SS C++ add-on that lets Lua scripts work a virtual gamepad.
//
// The game ignores control values a script writes into the plane (workbench section 10),
// so the playtest bot's pilot works a gamepad instead. The gamepad itself is the stand-in
// xinput1_3.dll in the copy's folder (cpp\CoopPad); this add-on finds it inside the game
// process and registers these functions in every Lua mod UE4SS starts:
//
//   CoopPad_Set(lx, ly, rx, ry, lt, rt, buttons)
//                     sticks -1..1 (x = right, y = up), triggers 0..1, buttons = the
//                     XINPUT_GAMEPAD_* bits; keeps the pad in that position until the next
//                     call (the pad lets go by itself half a second after the last call)
//   CoopPad_Release() lets go of the pad at once
//   CoopPad_Status()  -> string: whether the stand-in is loaded and how often the game polled it
//   CoopPad_Foreground() -> boolean: whether the game window is the one in front (the game
//                     pauses itself when it is not)
//   CoopKeys_Set("W,A") holds exactly these keyboard keys (every other key this add-on
//                     pressed is let go); CoopKeys_Set("") lets go of all of them
//   CoopKeys_Status() -> string: which keys are held, how many presses were sent
//
// Why keys too (18 Oct 2026): Steam's overlay sits between the game and any gamepad
// library and answers the game's gamepad reads itself, so the virtual gamepad never reaches
// the game. Keyboard keys do (the take-off on W worked). The keys are sent from inside the
// game process with SendInput, only while the game window is in front: a key is never
// pressed while another window is in front, and everything is let go when the game loses
// the front or when the scripts stop calling CoopKeys_Set for 0.3 s.
//
// Built against RE-UE4SS commit 48e7edfe (the version in the game copy); see cpp\README.md.

#include <windows.h>
#include <psapi.h>

#include <atomic>
#include <mutex>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>

#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

#pragma comment(lib, "psapi.lib")

using namespace RC;

#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)

namespace
{
    using SetFn = void(__cdecl*)(float, float, float, float, float, float, unsigned);
    using ReleaseFn = void(__cdecl*)();
    using StatsFn = int(__cdecl*)(char*, int);

    SetFn g_set = nullptr;
    ReleaseFn g_release = nullptr;
    StatsFn g_stats = nullptr;
    std::wstring g_where = L"not found";

    // The stand-in is the loaded module that exports CoopPad_Set (Windows' own xinput1_3.dll,
    // which the stand-in loads too, has the same name, so the export decides).
    auto find_pad() -> bool
    {
        if (g_set) return true;
        HMODULE mods[1024];
        DWORD needed = 0;
        if (!EnumProcessModules(GetCurrentProcess(), mods, sizeof(mods), &needed)) return false;
        for (DWORD i = 0; i < needed / sizeof(HMODULE) && i < 1024; ++i)
        {
            auto set = reinterpret_cast<SetFn>(GetProcAddress(mods[i], "CoopPad_Set"));
            if (!set) continue;
            g_set = set;
            g_release = reinterpret_cast<ReleaseFn>(GetProcAddress(mods[i], "CoopPad_Release"));
            g_stats = reinterpret_cast<StatsFn>(GetProcAddress(mods[i], "CoopPad_Stats"));
            wchar_t path[MAX_PATH];
            if (GetModuleFileNameW(mods[i], path, MAX_PATH)) g_where = path;
            return true;
        }
        return false;
    }

    // Lua's own C functions are inside UE4SS.dll but not exported, so the arguments are
    // read with LuaMadeSimple's exported helpers (each get_number takes the first one off).
    auto clear(const LuaMadeSimple::Lua& lua) -> void
    {
        while (lua.get_stack_size() > 0) lua.discard_value();
    }

    auto lua_set(const LuaMadeSimple::Lua& lua) -> int
    {
        double v[7] = {0, 0, 0, 0, 0, 0, 0};
        for (int i = 0; i < 7 && lua.get_stack_size() > 0; ++i)
        {
            if (lua.is_number()) v[i] = lua.get_number();
            else lua.discard_value();
        }
        clear(lua);
        bool ok = find_pad();
        if (ok)
        {
            g_set(static_cast<float>(v[0]), static_cast<float>(v[1]), static_cast<float>(v[2]), static_cast<float>(v[3]),
                  static_cast<float>(v[4]), static_cast<float>(v[5]), static_cast<unsigned>(v[6]));
        }
        lua.set_bool(ok);
        return 1;
    }

    auto lua_release(const LuaMadeSimple::Lua& lua) -> int
    {
        clear(lua);
        if (find_pad() && g_release) g_release();
        return 0;
    }

    auto lua_status(const LuaMadeSimple::Lua& lua) -> int
    {
        clear(lua);
        if (!find_pad() || !g_stats)
        {
            lua.set_string("CoopPad: the stand-in xinput1_3.dll is not loaded in this game (is it in the game folder?)");
            return 1;
        }
        char buf[1024];
        g_stats(buf, sizeof(buf));
        std::string where(g_where.begin(), g_where.end());
        lua.set_string(std::string(buf) + " [" + where + "]");
        return 1;
    }

    // ---- keyboard ------------------------------------------------------------------
    auto game_in_front() -> bool
    {
        DWORD pid = 0;
        HWND fg = GetForegroundWindow();
        if (fg) GetWindowThreadProcessId(fg, &pid);
        return pid == GetCurrentProcessId();
    }

    const std::unordered_map<std::string, WORD> g_vk = {
        {"A", 'A'}, {"B", 'B'}, {"C", 'C'}, {"D", 'D'}, {"E", 'E'}, {"F", 'F'}, {"G", 'G'}, {"H", 'H'}, {"I", 'I'},
        {"J", 'J'}, {"K", 'K'}, {"L", 'L'}, {"M", 'M'}, {"N", 'N'}, {"O", 'O'}, {"P", 'P'}, {"Q", 'Q'}, {"R", 'R'},
        {"S", 'S'}, {"T", 'T'}, {"U", 'U'}, {"V", 'V'}, {"W", 'W'}, {"X", 'X'}, {"Y", 'Y'}, {"Z", 'Z'},
        {"0", '0'}, {"1", '1'}, {"2", '2'}, {"3", '3'}, {"4", '4'}, {"5", '5'}, {"6", '6'}, {"7", '7'}, {"8", '8'}, {"9", '9'},
        {"Space", VK_SPACE}, {"Enter", VK_RETURN}, {"Escape", VK_ESCAPE}, {"Tab", VK_TAB}, {"Backspace", VK_BACK},
        {"Up", VK_UP}, {"Down", VK_DOWN}, {"Left", VK_LEFT}, {"Right", VK_RIGHT},
        {"Shift", VK_LSHIFT}, {"Ctrl", VK_LCONTROL}, {"Alt", VK_LMENU}, {"RShift", VK_RSHIFT}, {"RCtrl", VK_RCONTROL},
        {"Num0", VK_NUMPAD0}, {"Num1", VK_NUMPAD1}, {"Num2", VK_NUMPAD2}, {"Num3", VK_NUMPAD3}, {"Num4", VK_NUMPAD4},
        {"Num5", VK_NUMPAD5}, {"Num6", VK_NUMPAD6}, {"Num7", VK_NUMPAD7}, {"Num8", VK_NUMPAD8}, {"Num9", VK_NUMPAD9},
        {"F1", VK_F1}, {"F2", VK_F2}, {"F3", VK_F3}, {"F4", VK_F4}, {"F5", VK_F5}, {"F6", VK_F6},
        {"Home", VK_HOME}, {"End", VK_END}, {"PageUp", VK_PRIOR}, {"PageDown", VK_NEXT}, {"Insert", VK_INSERT}, {"Delete", VK_DELETE},
    };

    std::mutex g_keys_mutex;
    std::set<WORD> g_held;                 // keys this add-on has pressed and not let go
    ULONGLONG g_keys_set_at = 0;
    std::atomic<long long> g_presses{0}, g_lets_go{0}, g_refused{0};
    std::string g_keys_note = "no keys yet";
    std::thread g_watchdog;
    std::atomic<bool> g_stop_watchdog{false};

    auto send_key(WORD vk, bool down) -> void
    {
        INPUT in{};
        in.type = INPUT_KEYBOARD;
        in.ki.wScan = static_cast<WORD>(MapVirtualKeyW(vk, MAPVK_VK_TO_VSC));
        in.ki.dwFlags = KEYEVENTF_SCANCODE | (down ? 0 : KEYEVENTF_KEYUP);
        switch (vk)
        {
        case VK_UP: case VK_DOWN: case VK_LEFT: case VK_RIGHT: case VK_HOME: case VK_END: case VK_PRIOR: case VK_NEXT:
        case VK_INSERT: case VK_DELETE: case VK_RCONTROL:
            in.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
            break;
        default:
            break;
        }
        SendInput(1, &in, sizeof(in));
    }

    // Caller holds g_keys_mutex.
    auto let_go_all_locked() -> void
    {
        for (WORD vk : g_held) { send_key(vk, false); ++g_lets_go; }
        g_held.clear();
    }

    auto lua_keys_set(const LuaMadeSimple::Lua& lua) -> int
    {
        std::string list;
        if (lua.get_stack_size() > 0 && lua.is_string()) list = std::string(lua.get_string());
        clear(lua);
        std::set<WORD> want;
        std::string unknown;
        size_t start = 0;
        while (start <= list.size())
        {
            size_t comma = list.find(',', start);
            std::string name = list.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
            if (!name.empty())
            {
                auto it = g_vk.find(name);
                if (it != g_vk.end()) want.insert(it->second);
                else unknown += (unknown.empty() ? "" : ",") + name;
            }
            if (comma == std::string::npos) break;
            start = comma + 1;
        }
        std::lock_guard<std::mutex> lock(g_keys_mutex);
        g_keys_set_at = GetTickCount64();
        if (!game_in_front())
        {
            // never press anything into another window; let go of what is held
            if (!want.empty()) ++g_refused;
            let_go_all_locked();
            g_keys_note = "game not in front: keys let go";
            lua.set_bool(false);
            return 1;
        }
        for (auto it = g_held.begin(); it != g_held.end();)
        {
            if (!want.count(*it)) { send_key(*it, false); ++g_lets_go; it = g_held.erase(it); }
            else ++it;
        }
        for (WORD vk : want)
        {
            if (!g_held.count(vk)) { send_key(vk, true); ++g_presses; g_held.insert(vk); }
        }
        g_keys_note = unknown.empty() ? "ok" : "unknown key names: " + unknown;
        lua.set_bool(unknown.empty());
        return 1;
    }

    auto lua_keys_status(const LuaMadeSimple::Lua& lua) -> int
    {
        clear(lua);
        std::lock_guard<std::mutex> lock(g_keys_mutex);
        std::string held;
        for (WORD vk : g_held)
        {
            for (const auto& [name, code] : g_vk) if (code == vk) { held += (held.empty() ? "" : ",") + name; break; }
        }
        lua.set_string("CoopKeys: holding [" + held + "], " + std::to_string(g_presses.load()) + " presses, " +
                       std::to_string(g_lets_go.load()) + " lets-go, " + std::to_string(g_refused.load()) +
                       " refused (game not in front); last: " + g_keys_note);
        return 1;
    }

    auto watchdog_main() -> void
    {
        while (!g_stop_watchdog)
        {
            Sleep(50);
            std::lock_guard<std::mutex> lock(g_keys_mutex);
            if (g_held.empty()) continue;
            if (GetTickCount64() - g_keys_set_at > 300 || !game_in_front())
            {
                let_go_all_locked();
                g_keys_note = "let go by the watchdog (no call for 0.3 s, or the game lost the front)";
            }
        }
    }

    auto lua_foreground(const LuaMadeSimple::Lua& lua) -> int
    {
        clear(lua);
        lua.set_bool(game_in_front());
        return 1;
    }
} // namespace

class CoopPadMod : public CppUserModBase
{
  public:
    CoopPadMod() : CppUserModBase()
    {
        ModName = STR("CoopPadMod");
        ModVersion = STR("0.1");
        ModDescription = STR("Virtual gamepad and keyboard for Lua mods: the playtest bot's hands");
        ModAuthors = STR("AC7-Coop workbench");
        g_stop_watchdog = false;
        g_watchdog = std::thread(watchdog_main);
        bool found = find_pad();
        Output::send<LogLevel::Verbose>(STR("[CoopPadMod] started (built {} {}): stand-in gamepad {} {}\n"),
                                        WIDEN(__DATE__), WIDEN(__TIME__), found ? STR("found at") : STR("not found"), g_where);
    }

    ~CoopPadMod() override
    {
        if (g_release) g_release();
        g_stop_watchdog = true;
        if (g_watchdog.joinable()) g_watchdog.join();
        std::lock_guard<std::mutex> lock(g_keys_mutex);
        let_go_all_locked();
    }

    auto on_lua_start(StringViewType mod_name,
                      LuaMadeSimple::Lua& lua,
                      LuaMadeSimple::Lua& main_lua,
                      LuaMadeSimple::Lua& async_lua,
                      LuaMadeSimple::Lua* hook_lua) -> void override
    {
        lua.register_function("CoopPad_Set", lua_set);
        lua.register_function("CoopPad_Release", lua_release);
        lua.register_function("CoopPad_Status", lua_status);
        lua.register_function("CoopPad_Foreground", lua_foreground);
        lua.register_function("CoopKeys_Set", lua_keys_set);
        lua.register_function("CoopKeys_Status", lua_keys_status);
    }
};

#define COOP_PAD_MOD_API __declspec(dllexport)
extern "C"
{
    COOP_PAD_MOD_API CppUserModBase* start_mod()
    {
        return new CoopPadMod();
    }

    COOP_PAD_MOD_API void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
