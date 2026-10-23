#include <android/log.h>
#include <arpa/inet.h>
#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include <string>
#include <vector>

#include "include/zygisk.hpp"
#include "dobby.h"

#define LOG_TAG "AppDpiZygisk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

typedef int (*getaddrinfo_t)(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
typedef int (*android_getaddrinfofornetcontext_t)(const char *node, const char *service, const struct addrinfo *hints, const void *netcontext, struct addrinfo **res);
typedef int (*android_getaddrinfofornet_t)(const char *node, const char *service, const struct addrinfo *hints, unsigned netid, unsigned mark, struct addrinfo **res);

static getaddrinfo_t orig_getaddrinfo = nullptr;
static android_getaddrinfofornetcontext_t orig_android_getaddrinfofornetcontext = nullptr;
static android_getaddrinfofornet_t orig_android_getaddrinfofornet = nullptr;

static bool g_is_target = false;
static std::string g_target_pkg;

static bool is_numeric_ip(const char *node) {
    if (!node) return false;
    struct in_addr a4;
    if (inet_pton(AF_INET, node, &a4) == 1) return true;
    struct in6_addr a6;
    if (inet_pton(AF_INET6, node, &a6) == 1) return true;
    return false;
}

static int encode_dns_domain(const char *domain, uint8_t *out, int max_len) {
    int out_idx = 0;
    const char *p = domain;
    while (*p) {
        const char *next_dot = strchr(p, '.');
        int len = next_dot ? (int)(next_dot - p) : (int)strlen(p);
        if (len <= 0 || len > 63 || out_idx + 1 + len >= max_len) {
            return -1;
        }
        out[out_idx++] = (uint8_t)len;
        memcpy(out + out_idx, p, len);
        out_idx += len;
        if (!next_dot) break;
        p = next_dot + 1;
    }
    if (out_idx >= max_len) return -1;
    out[out_idx++] = 0;
    return out_idx;
}

// Query local DoH daemon at 127.0.0.1:5354
static bool query_local_doh(const char *domain, uint16_t qtype, std::vector<struct in_addr> &v4_addrs, std::vector<struct in6_addr> &v6_addrs) {
    int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return false;

    // 2.5 second timeout to safely accommodate mobile network cold handshakes
    struct timeval tv;
    tv.tv_sec = 2;
    tv.tv_usec = 500000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in saddr;
    memset(&saddr, 0, sizeof(saddr));
    saddr.sin_family = AF_INET;
    saddr.sin_port = htons(5354);
    saddr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // 127.0.0.1

    uint8_t req[512];
    memset(req, 0, sizeof(req));
    uint16_t qid = (uint16_t)(rand() & 0xFFFF);
    req[0] = (uint8_t)(qid >> 8);
    req[1] = (uint8_t)(qid & 0xFF);
    req[2] = 0x01; // RD = 1
    req[3] = 0x00;
    req[4] = 0x00; req[5] = 0x01; // QDCOUNT = 1

    int dlen = encode_dns_domain(domain, req + 12, sizeof(req) - 16);
    if (dlen < 0) {
        close(fd);
        return false;
    }
    int pos = 12 + dlen;
    req[pos++] = (uint8_t)(qtype >> 8);
    req[pos++] = (uint8_t)(qtype & 0xFF);
    req[pos++] = 0x00; // QCLASS = 1 (IN)
    req[pos++] = 0x01;

    if (sendto(fd, req, pos, 0, (struct sockaddr *)&saddr, sizeof(saddr)) <= 0) {
        close(fd);
        return false;
    }

    uint8_t resp[1500];
    ssize_t n = recv(fd, resp, sizeof(resp), 0);
    close(fd);

    if (n < 12) return false;
    uint16_t resp_id = ((uint16_t)resp[0] << 8) | resp[1];
    if (resp_id != qid) return false;

    uint8_t rcode = resp[3] & 0x0F;
    if (rcode != 0) return false;

    uint16_t qdcount = ((uint16_t)resp[4] << 8) | resp[5];
    uint16_t ancount = ((uint16_t)resp[6] << 8) | resp[7];
    if (ancount == 0) return false;

    // Skip question section
    int idx = 12;
    for (int q = 0; q < qdcount && idx < n; q++) {
        while (idx < n) {
            uint8_t len = resp[idx++];
            if (len == 0) break;
            if ((len & 0xC0) == 0xC0) {
                idx++;
                break;
            }
            idx += len;
        }
        idx += 4; // qtype + qclass
    }

    // Parse Answer records
    for (int a = 0; a < ancount && idx + 10 <= n; a++) {
        if ((resp[idx] & 0xC0) == 0xC0) {
            idx += 2;
        } else {
            while (idx < n) {
                uint8_t len = resp[idx++];
                if (len == 0) break;
                if ((len & 0xC0) == 0xC0) { idx++; break; }
                idx += len;
            }
        }
        if (idx + 10 > n) break;
        uint16_t atype = ((uint16_t)resp[idx] << 8) | resp[idx + 1];
        idx += 8; // skip atype, aclass, ttl (4 bytes)
        uint16_t rdlen = ((uint16_t)resp[idx] << 8) | resp[idx + 1];
        idx += 2;

        if (idx + rdlen > n) break;

        if (atype == 1 && rdlen == 4) { // A (IPv4)
            struct in_addr addr;
            memcpy(&addr, resp + idx, 4);
            v4_addrs.push_back(addr);
        } else if (atype == 28 && rdlen == 16) { // AAAA (IPv6)
            struct in6_addr addr6;
            memcpy(&addr6, resp + idx, 16);
            v6_addrs.push_back(addr6);
        }
        idx += rdlen;
    }

    return (!v4_addrs.empty() || !v6_addrs.empty());
}

static bool resolve_doh_and_build(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    int port = 0;
    if (service) {
        port = atoi(service);
        if (port == 0) {
            if (strcmp(service, "https") == 0) port = 443;
            else if (strcmp(service, "http") == 0) port = 80;
        }
    }

    uint16_t req_family = hints ? hints->ai_family : AF_UNSPEC;
    int req_socktype = (hints && hints->ai_socktype) ? hints->ai_socktype : SOCK_STREAM;
    int req_protocol = (hints && hints->ai_protocol) ? hints->ai_protocol : IPPROTO_TCP;

    std::vector<struct in_addr> v4_addrs;
    std::vector<struct in6_addr> v6_addrs;
    bool success = false;

    if (req_family == AF_INET) {
        success = query_local_doh(node, 1 /* A */, v4_addrs, v6_addrs);
    } else if (req_family == AF_INET6) {
        success = query_local_doh(node, 28 /* AAAA */, v4_addrs, v6_addrs);
    } else {
        success = query_local_doh(node, 1 /* A */, v4_addrs, v6_addrs);
    }

    if (!success || (v4_addrs.empty() && v6_addrs.empty())) {
        return false;
    }

    struct addrinfo *head = nullptr;
    struct addrinfo **tail = &head;

    // Note: Bionic freeaddrinfo frees ai and ai_canonname, but expects ai_addr
    // to be in the same contiguous block (ai + 1) or inside the allocated memory.
    for (const auto &ip4 : v4_addrs) {
        size_t total_size = sizeof(struct addrinfo) + sizeof(struct sockaddr_in);
        struct addrinfo *ai = (struct addrinfo *)calloc(1, total_size);
        if (!ai) continue;

        struct sockaddr_in *sa = (struct sockaddr_in *)(ai + 1);
        sa->sin_family = AF_INET;
        sa->sin_port = htons((uint16_t)port);
        sa->sin_addr = ip4;

        ai->ai_family = AF_INET;
        ai->ai_socktype = req_socktype;
        ai->ai_protocol = req_protocol;
        ai->ai_addrlen = sizeof(struct sockaddr_in);
        ai->ai_addr = (struct sockaddr *)sa;
        ai->ai_canonname = strdup(node);

        *tail = ai;
        tail = &ai->ai_next;
    }

    for (const auto &ip6 : v6_addrs) {
        size_t total_size = sizeof(struct addrinfo) + sizeof(struct sockaddr_in6);
        struct addrinfo *ai = (struct addrinfo *)calloc(1, total_size);
        if (!ai) continue;

        struct sockaddr_in6 *sa6 = (struct sockaddr_in6 *)(ai + 1);
        sa6->sin6_family = AF_INET6;
        sa6->sin6_port = htons((uint16_t)port);
        sa6->sin6_addr = ip6;

        ai->ai_family = AF_INET6;
        ai->ai_socktype = req_socktype;
        ai->ai_protocol = req_protocol;
        ai->ai_addrlen = sizeof(struct sockaddr_in6);
        ai->ai_addr = (struct sockaddr *)sa6;
        ai->ai_canonname = strdup(node);

        *tail = ai;
        tail = &ai->ai_next;
    }

    if (head != nullptr) {
        *res = head;
        return true;
    }
    return false;
}

static int my_getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res) {
    if (g_is_target && node && node[0] != '\0' && !is_numeric_ip(node)) {
        if (strcmp(node, "localhost") != 0 && strstr(node, ".local") == nullptr) {
            LOGI("Intercepted getaddrinfo for %s", node);
            if (resolve_doh_and_build(node, service, hints, res)) {
                return 0; // EAI_SUCCESS
            }
            LOGI("DoH query failed for %s, falling back to orig", node);
        }
    }
    if (orig_getaddrinfo) return orig_getaddrinfo(node, service, hints, res);
    return EAI_FAIL;
}

static int my_android_getaddrinfofornetcontext(const char *node, const char *service, const struct addrinfo *hints, const void *netcontext, struct addrinfo **res) {
    if (g_is_target && node && node[0] != '\0' && !is_numeric_ip(node)) {
        if (strcmp(node, "localhost") != 0 && strstr(node, ".local") == nullptr) {
            LOGI("Intercepted android_getaddrinfofornetcontext for %s", node);
            if (resolve_doh_and_build(node, service, hints, res)) {
                return 0; // EAI_SUCCESS
            }
            LOGI("DoH query failed for %s, falling back to orig", node);
        }
    }
    if (orig_android_getaddrinfofornetcontext) return orig_android_getaddrinfofornetcontext(node, service, hints, netcontext, res);
    return EAI_FAIL;
}

static int my_android_getaddrinfofornet(const char *node, const char *service, const struct addrinfo *hints, unsigned netid, unsigned mark, struct addrinfo **res) {
    if (g_is_target && node && node[0] != '\0' && !is_numeric_ip(node)) {
        if (strcmp(node, "localhost") != 0 && strstr(node, ".local") == nullptr) {
            LOGI("Intercepted android_getaddrinfofornet for %s", node);
            if (resolve_doh_and_build(node, service, hints, res)) {
                return 0; // EAI_SUCCESS
            }
            LOGI("DoH query failed for %s, falling back to orig", node);
        }
    }
    if (orig_android_getaddrinfofornet) return orig_android_getaddrinfofornet(node, service, hints, netid, mark, res);
    return EAI_FAIL;
}

class AppDpiDnsModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api;
        this->env = env;
        LOGI("AppDpiDnsModule onLoad successfully");
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        bool target = is_target_app(args);
        if (!target) {
            // Unload immediately for non-target processes (zero overhead & zero detection)
            api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        g_is_target = true;
        LOGI("preAppSpecialize: TARGET DETECTED: %s", g_target_pkg.c_str());
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
        if (!g_is_target) return;

        LOGI("postAppSpecialize: Initializing Dobby inline hook for %s (Dobby v%s)...", g_target_pkg.c_str(), DobbyGetVersion());

        // 1. Resolve symbols
        void *sym_gai = dlsym(RTLD_DEFAULT, "getaddrinfo");
        if (!sym_gai) sym_gai = DobbySymbolResolver("libc.so", "getaddrinfo");

        void *sym_netctx = dlsym(RTLD_DEFAULT, "android_getaddrinfofornetcontext");
        if (!sym_netctx) sym_netctx = DobbySymbolResolver("libc.so", "android_getaddrinfofornetcontext");

        void *sym_net = dlsym(RTLD_DEFAULT, "android_getaddrinfofornet");
        if (!sym_net) sym_net = DobbySymbolResolver("libc.so", "android_getaddrinfofornet");

        LOGI("Pointers: gai=%p, netctx=%p, net=%p", sym_gai, sym_netctx, sym_net);

        if (sym_gai) {
            int ret = DobbyHook(sym_gai, (dobby_dummy_func_t)my_getaddrinfo, (dobby_dummy_func_t *)&orig_getaddrinfo);
            LOGI("DobbyHook getaddrinfo -> %d (orig=%p)", ret, orig_getaddrinfo);
        }

        if (sym_netctx) {
            int ret = DobbyHook(sym_netctx, (dobby_dummy_func_t)my_android_getaddrinfofornetcontext, (dobby_dummy_func_t *)&orig_android_getaddrinfofornetcontext);
            LOGI("DobbyHook android_getaddrinfofornetcontext -> %d (orig=%p)", ret, orig_android_getaddrinfofornetcontext);
        }

        if (sym_net) {
            int ret = DobbyHook(sym_net, (dobby_dummy_func_t)my_android_getaddrinfofornet, (dobby_dummy_func_t *)&orig_android_getaddrinfofornet);
            LOGI("DobbyHook android_getaddrinfofornet -> %d (orig=%p)", ret, orig_android_getaddrinfofornet);
        }
    }

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;

    bool is_target_app(zygisk::AppSpecializeArgs *args) {
        // 1. Check if DNS is enabled in config.conf
        bool dns_enabled = true; // default true if config not yet readable
        FILE *cfg = fopen("/data/adb/app-dpi-bypass/config.conf", "r");
        if (!cfg) cfg = fopen("/data/adb/modules/app-dpi-bypass/config.conf", "r");
        if (cfg) {
            char line[256];
            bool found_flag = false;
            while (fgets(line, sizeof(line), cfg)) {
                if (strncmp(line, "DNS_ENABLED=\"0\"", 15) == 0 || strncmp(line, "DNS_ENABLED=0", 13) == 0) {
                    dns_enabled = false;
                    found_flag = true;
                    break;
                } else if (strncmp(line, "DNS_ENABLED=\"1\"", 15) == 0 || strncmp(line, "DNS_ENABLED=1", 13) == 0) {
                    dns_enabled = true;
                    found_flag = true;
                    break;
                }
            }
            fclose(cfg);
            if (found_flag && !dns_enabled) return false;
        }

        // 2. Extract package name
        std::string pkg_name;
        if (args->nice_name) {
            const char *nice = env->GetStringUTFChars(args->nice_name, nullptr);
            if (nice) {
                pkg_name = nice;
                env->ReleaseStringUTFChars(args->nice_name, nice);
            }
        }
        if (pkg_name.empty() && args->app_data_dir) {
            const char *dir = env->GetStringUTFChars(args->app_data_dir, nullptr);
            if (dir) {
                const char *last = strrchr(dir, '/');
                if (last && *(last + 1)) pkg_name = (last + 1);
                env->ReleaseStringUTFChars(args->app_data_dir, dir);
            }
        }

        if (pkg_name.empty()) return false;

        // Strip sub-process names (e.g. "com.discord:sandboxed_process0" -> "com.discord")
        size_t colon = pkg_name.find(':');
        std::string base_pkg = (colon != std::string::npos) ? pkg_name.substr(0, colon) : pkg_name;

        // 3. Match against apps.list
        FILE *fp = fopen("/data/adb/app-dpi-bypass/apps.list", "r");
        if (!fp) fp = fopen("/data/adb/modules/app-dpi-bypass/apps.list", "r");
        if (!fp) return false;

        char buf[256];
        bool matched = false;
        while (fgets(buf, sizeof(buf), fp)) {
            char *line = buf;
            while (isspace(*line)) line++;
            if (*line == '#' || *line == '\0') continue;
            char *end = line + strlen(line) - 1;
            while (end > line && isspace(*end)) *end-- = '\0';

            if (base_pkg == line) {
                matched = true;
                break;
            }
        }
        fclose(fp);

        if (matched) {
            g_target_pkg = base_pkg;
        }
        return matched;
    }
};

REGISTER_ZYGISK_MODULE(AppDpiDnsModule)
