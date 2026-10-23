# TODO: Per-App DoH (DNS over HTTPS) Zygisk Entegrasyonu

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
                                                [libc.so Inline Hook]
                                                (getaddrinfo sembolü)
                                                           │
                                                           ▼
                                                [127.0.0.1:5353 UDP Sor]
                                                   (Local DoH Daemon)
                                                           │
                                                           ▼
                                                [struct addrinfo Dönüşü]
                                                (Fallback: orig_getaddrinfo)
```

---

## 3. Yol Haritası ve Görev Listesi

### Aşama 1: Yerel DoH Daemon (Local Forwarder)
- [ ] Arka planda KernelSU `service.sh` tarafından başlatılacak statik arm64 DoH forwarder ikilisini (`bin/doh_forwarder`) modüle dahil et.
- [ ] Dinleme adresi: `127.0.0.1:5353` (UDP).
- [ ] Upstream: Cloudflare (`https://1.1.1.1/dns-query`) veya Google DoH.
- [ ] DNS önbellekleme (cache) desteği ile düşük gecikme (<1ms).

### Aşama 2: Zygisk Kütüphanesi (`arm64-v8a.so`)
- [ ] `jni/` dizininde Zygisk modül yapısını kur:
  - `zygisk.hpp`: Zygisk API v4/v5 başlığı.
  - `main.cpp`: `preAppSpecialize` (paket filtreleme, hedef dışı için `dlclose()`).
  - `dns_hook.c`: `libc.so` `getaddrinfo` kancası.
  - `shadowhook`: Bionic inline hook motoru entegrasyonu.
- [ ] `getaddrinfo` kanca mantığı:
  - IP kontrolleri (gelen girdi zaten IPv4/IPv6 ise orijinal fonksiyona pasla).
  - Alan adını `127.0.0.1:5353` üzerinden UDP ile çöz.
  - Başarılı ise Bionic uyumlu `struct addrinfo` listesi oluştur ve dön.
  - Zaman aşımı veya hata durumunda orijinal `orig_getaddrinfo` çağrısına düş (Fail-safe / fallback).

### Aşama 3: Derleme ve Dağıtım Otomasyonu
- [ ] Derleme aracı: Host üzerindeki `/opt/android-ndk` (NDK r29 aarch64) ile `ndk-build` entegrasyonu.
- [ ] `package.sh` güncellemesi: `zygisk/arm64-v8a.so` çıktısını modül zip arşivine dahil et.
- [ ] `deploy.sh` güncellemesi: Cihaza aktarımda Zygisk modül yetkilerini ve dizinini (`/data/adb/modules/app-dpi-bypass/zygisk/`) yapılandır.

### Aşama 4: Test ve Doğrulama
- [ ] Discord (`com.discord`) metin akışının ve görsel yüklemelerinin doğrulanması.
- [ ] Discord WebRTC ses/video kanalı bağlantısının ("RTC Connected") testi.
- [ ] Bankacılık uygulamalarında `dlclose()` davranışının ve tespit edilmezliğinin doğrulanması.
