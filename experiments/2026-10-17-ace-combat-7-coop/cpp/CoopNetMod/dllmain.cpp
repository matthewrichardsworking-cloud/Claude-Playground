// CoopNetMod: a UE4SS C++ add-on that gives Lua mods a network socket.
//
// UE4SS's Lua has no sockets, and the co-op plan needs a live feed of the other player's
// plane. This add-on opens a UDP socket on 127.0.0.1 port 27777 when it starts, receives
// packets on its own thread, remembers the newest ones, and registers these functions in
// every Lua mod UE4SS starts:
//
//   CoopNet_Count()        -> integer: packets received since the add-on started
//   CoopNet_Latest()       -> line, seq, age_ms  (or nil when nothing has arrived yet)
//                             line   = the packet text without its trailing newline
//                             seq    = the packet's number (1 for the first packet)
//                             age_ms = milliseconds since it arrived
//   CoopNet_Since(seq)     -> the oldest remembered packet newer than seq, as
//                             line, seq, age_ms, or nil when there is none. Call it in a
//                             loop to drain every packet a Lua script has not seen yet.
//   CoopNet_Status()       -> string: what the socket is doing, for the log
//
// A packet is one text line: time,x,y,z,pitch,yaw,roll (see tools\coop-net-sender.py).
// The add-on never sends anything and only listens on the local machine (127.0.0.1).
//
// Built against RE-UE4SS commit 48e7edfe (the version in the game copy); see cpp\README.md.

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

#pragma comment(lib, "ws2_32.lib")

using namespace RC;

// __DATE__ and __TIME__ are narrow string literals; UE4SS logs wide strings.
#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)

namespace
{
    constexpr const char* LISTEN_ADDRESS = "127.0.0.1";
    constexpr uint16_t LISTEN_PORT = 27777;
    constexpr size_t REMEMBERED_PACKETS = 64;

    using Clock = std::chrono::steady_clock;

    struct Packet
    {
        std::string line;
        uint64_t seq{};
        Clock::time_point arrived{};
    };

    // Shared between the receiver thread and the Lua functions (which run on UE4SS's
    // Lua threads or the game thread). Everything below is guarded by g_mutex except
    // the atomics.
    std::mutex g_mutex;
    std::deque<Packet> g_recent;      // oldest first, newest last
    uint64_t g_seq = 0;
    std::atomic<uint64_t> g_count{0};
    std::atomic<uint64_t> g_bytes{0};
    std::string g_status = "not started";

    std::atomic<bool> g_stop{false};
    SOCKET g_socket = INVALID_SOCKET;
    std::thread g_thread;
    bool g_winsock_started = false;

    auto set_status(std::string s) -> void
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_status = std::move(s);
    }

    auto age_ms(Clock::time_point t) -> double
    {
        return std::chrono::duration<double, std::milli>(Clock::now() - t).count();
    }

    auto receiver_main() -> void
    {
        char buf[2048];
        while (!g_stop)
        {
            sockaddr_in from{};
            int from_len = sizeof(from);
            int n = recvfrom(g_socket, buf, static_cast<int>(sizeof(buf)) - 1, 0, reinterpret_cast<sockaddr*>(&from), &from_len);
            if (n == SOCKET_ERROR)
            {
                int err = WSAGetLastError();
                if (err == WSAETIMEDOUT) continue;   // the 250 ms receive timeout: just check g_stop again
                if (g_stop) break;
                if (err == WSAEMSGSIZE) continue;    // a packet bigger than the buffer: dropped
                set_status("receive error " + std::to_string(err));
                Sleep(50);
                continue;
            }
            while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) --n;
            Packet p{std::string(buf, static_cast<size_t>(n)), 0, Clock::now()};
            std::lock_guard<std::mutex> lock(g_mutex);
            p.seq = ++g_seq;
            g_count = g_seq;
            g_bytes += static_cast<uint64_t>(n);
            g_recent.push_back(std::move(p));
            if (g_recent.size() > REMEMBERED_PACKETS) g_recent.pop_front();
        }
    }

    auto start_receiver() -> bool
    {
        WSADATA wsa{};
        int r = WSAStartup(MAKEWORD(2, 2), &wsa);
        if (r != 0)
        {
            set_status("WSAStartup failed: " + std::to_string(r));
            return false;
        }
        g_winsock_started = true;

        g_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (g_socket == INVALID_SOCKET)
        {
            set_status("socket() failed: " + std::to_string(WSAGetLastError()));
            return false;
        }
        // Only this process may own the port; a leftover socket from a previous load of
        // this DLL (UE4SS reloads C++ mods on Ctrl+P) is closed in the destructor first.
        BOOL exclusive = TRUE;
        setsockopt(g_socket, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
        DWORD timeout_ms = 250;
        setsockopt(g_socket, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));
        int rcvbuf = 1 << 20;
        setsockopt(g_socket, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char*>(&rcvbuf), sizeof(rcvbuf));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(LISTEN_PORT);
        inet_pton(AF_INET, LISTEN_ADDRESS, &addr.sin_addr);
        int bound = SOCKET_ERROR;
        for (int attempt = 0; attempt < 10 && bound == SOCKET_ERROR; ++attempt)
        {
            bound = bind(g_socket, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
            if (bound == SOCKET_ERROR) Sleep(100);
        }
        if (bound == SOCKET_ERROR)
        {
            set_status("bind to " + std::string(LISTEN_ADDRESS) + ":" + std::to_string(LISTEN_PORT) + " failed: " + std::to_string(WSAGetLastError()));
            closesocket(g_socket);
            g_socket = INVALID_SOCKET;
            return false;
        }
        g_stop = false;
        g_thread = std::thread(receiver_main);
        set_status("listening on " + std::string(LISTEN_ADDRESS) + ":" + std::to_string(LISTEN_PORT));
        return true;
    }

    auto stop_receiver() -> void
    {
        g_stop = true;
        if (g_socket != INVALID_SOCKET)
        {
            closesocket(g_socket);   // also wakes the receiver out of recvfrom
            g_socket = INVALID_SOCKET;
        }
        if (g_thread.joinable()) g_thread.join();
        if (g_winsock_started)
        {
            WSACleanup();
            g_winsock_started = false;
        }
        set_status("stopped");
    }

    // ---- the Lua side -------------------------------------------------------------
    // LuaMadeSimple functions take plain function pointers, so these cannot capture.

    auto push_packet(const LuaMadeSimple::Lua& lua, const Packet& p) -> int
    {
        lua.set_string(p.line);
        lua.set_integer(static_cast<int64_t>(p.seq));
        lua.set_number(age_ms(p.arrived));
        return 3;
    }

    auto lua_count(const LuaMadeSimple::Lua& lua) -> int
    {
        lua.set_integer(static_cast<int64_t>(g_count.load()));
        return 1;
    }

    auto lua_latest(const LuaMadeSimple::Lua& lua) -> int
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_recent.empty())
        {
            lua.set_nil();
            return 1;
        }
        return push_packet(lua, g_recent.back());
    }

    auto lua_since(const LuaMadeSimple::Lua& lua) -> int
    {
        int64_t after = 0;
        if (lua.get_stack_size() >= 1 && lua.is_integer())
        {
            after = lua.get_integer();
        }
        else if (lua.get_stack_size() >= 1 && lua.is_number())
        {
            after = static_cast<int64_t>(lua.get_number());
        }
        std::lock_guard<std::mutex> lock(g_mutex);
        for (const auto& p : g_recent)
        {
            if (static_cast<int64_t>(p.seq) > after) return push_packet(lua, p);
        }
        lua.set_nil();
        return 1;
    }

    auto lua_status(const LuaMadeSimple::Lua& lua) -> int
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        lua.set_string(g_status + ", " + std::to_string(g_count.load()) + " packets, " + std::to_string(g_bytes.load()) + " bytes");
        return 1;
    }

    auto register_in(LuaMadeSimple::Lua& lua) -> void
    {
        lua.register_function("CoopNet_Count", lua_count);
        lua.register_function("CoopNet_Latest", lua_latest);
        lua.register_function("CoopNet_Since", lua_since);
        lua.register_function("CoopNet_Status", lua_status);
    }
} // namespace

class CoopNetMod : public CppUserModBase
{
  public:
    CoopNetMod() : CppUserModBase()
    {
        ModName = STR("CoopNetMod");
        ModVersion = STR("0.1");
        ModDescription = STR("UDP socket for Lua mods: the live position feed for AC7 co-op");
        ModAuthors = STR("AC7-Coop workbench");

        bool ok = start_receiver();
        std::string status;
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            status = g_status;
        }
        Output::send<LogLevel::Verbose>(STR("[CoopNetMod] started (built {} {}): {}\n"),
                                        WIDEN(__DATE__), WIDEN(__TIME__), std::wstring(status.begin(), status.end()));
        if (!ok)
        {
            Output::send<LogLevel::Warning>(STR("[CoopNetMod] the socket is not open; CoopNet_Status() in Lua has the reason\n"));
        }
    }

    ~CoopNetMod() override
    {
        stop_receiver();
        Output::send<LogLevel::Verbose>(STR("[CoopNetMod] stopped after {} packets\n"), g_count.load());
    }

    // UE4SS calls this for every Lua mod it starts; the functions are made global in that
    // mod's Lua. main_lua, async_lua and hook_lua are threads of the same Lua state, so
    // registering in 'lua' is enough for all of them.
    auto on_lua_start(StringViewType mod_name,
                      LuaMadeSimple::Lua& lua,
                      LuaMadeSimple::Lua& main_lua,
                      LuaMadeSimple::Lua& async_lua,
                      LuaMadeSimple::Lua* hook_lua) -> void override
    {
        register_in(lua);
        Output::send<LogLevel::Verbose>(STR("[CoopNetMod] CoopNet_* functions registered for Lua mod '{}'\n"), mod_name);
    }
};

#define COOP_NET_MOD_API __declspec(dllexport)
extern "C"
{
    COOP_NET_MOD_API CppUserModBase* start_mod()
    {
        return new CoopNetMod();
    }

    COOP_NET_MOD_API void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
