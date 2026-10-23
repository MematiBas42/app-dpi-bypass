# TODO & Roadmap: Per-App DoH (DNS over HTTPS) Zygisk Entegrasyonu

## 1. Hedef ve Kapsam
- **Amaç:** VpnService (`tun0`) veya global Private DNS ayarlarını değiştirmeden, sadece `apps.list` içinde tanımlı uygulamalar (başta Discord `com.discord`) için bağımsız DoH çözümlemesi sağlamak.
- **Kısıtlar:**
  - Bankacılık ve güvenlik uygulamalarında tespit riski yaratmamak (Zero-detection).
  - WebRTC ve native C++ çağrılarını (Discord ses kanalları) eksiksiz yakalamak (Bionic libc seviyesi).
  - Süreç içine ağır TLS/crypto kütüphaneleri gömmeden hafif ve kararlı kalmak.

---

## 2. Mimari Tasarım (Dual-Core Model)

```
[Seçilen Uygulama (Zygote fork)]
              │
              ▼
    [Zygisk Engine (preAppSpecialize)]
              │
              ├── 'apps.list' içinde YOKSA ──> dlclose() (Bellekten anında boşalt, sıfır iz)
              │
              └── 'apps.list' içinde VARSA ──> postAppSpecialize()
                                                           │
                                                           ▼
                                                [libc.so DobbyHook]
                                      (getaddrinfo & android_getaddrinfo*)
                                                           │
                                                           ▼
                                                [127.0.0.1:5354 UDP Sor]
                                                   (Local DoH Daemon)
                                                           │
                                                           ▼
                                                [struct addrinfo Dönüşü]
                                                (Fallback: orig_getaddrinfo)
```

---

## 3. Yol Haritası ve Görev Listesi

### Aşama 1: Yerel DoH Daemon (Local Forwarder)
- [x] Arka planda KernelSU `service.sh` tarafından başlatılacak statik arm64 DoH forwarder ikilisini (`bin/doh_forwarder`) modüle dahil et.
- [x] Dinleme adresi: `127.0.0.1:5354` (UDP).
- [x] Upstream: Cloudflare (`https://1.1.1.1/dns-query`), Google, Quad9, AdGuard veya özel DoH.
- [x] DNS önbellekleme (cache) ve CLI test (`-test <domain>`) desteği.

### Aşama 2: Zygisk Kütüphanesi (`arm64-v8a.so` & `armeabi-v7a.so`)
- [x] `src/zygisk/` dizininde Zygisk modül yapısını kur:
  - `zygisk.hpp`: Zygisk API başlığı.
  - `main.cpp`: `preAppSpecialize` (paket filtreleme, hedef dışı için `dlclose()`).
  - `DobbyHook`: Linker bağımsız Bionic inline hook motoru entegrasyonu (Android 15–17 / API 35–37 uyumlu).
- [x] DNS kanca mantığı:
  - IP kontrolleri (gelen girdi zaten IPv4/IPv6 ise orijinal fonksiyona pasla).
  - Alan adını `127.0.0.1:5354` üzerinden UDP ile çöz.
  - Başarılı ise Bionic uyumlu `struct addrinfo` listesi oluştur ve dön.
  - Zaman aşımı veya hata durumunda orijinal libc fonksiyonuna düş (Fail-safe / fallback).
- [x] 32-bit `armeabi-v7a` mimarisi desteği (Discord Android istemcisinin 32-bit çalışması sebebiyle).

### Aşama 3: Derleme ve Dağıtım Otomasyonu
- [x] Host üzerindeki Android NDK (r29) ile CMake entegrasyonu.
- [x] `package.sh` güncellemesi: `zygisk/*.so` ve `bin/doh_forwarder` çıktılarını modül zip arşivine dahil et.
- [x] `deploy.sh` ve `customize.sh` güncellemesi: Zygisk modül yetkilerini ve dizinini yapılandır.

### Aşama 4: Test ve Doğrulama
- [x] Discord (`com.discord`, UID 10389, 32-bit) metin akışının ve görsel yüklemelerinin doğrulanması.
- [x] Discord WebRTC ses kanalı bağlantısının ("RTC Bağlandı") testi.
- [x] Seçili olmayan uygulamalarda `dlclose()` ile sıfır iz (zero-detection) doğrulaması.
- [x] WebUI v2.0 sekmeleri (Apps, Presets, Auto-Tune, DoH, Advanced) ve mobil ekran responsive testleri.
