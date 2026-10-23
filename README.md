# App DPI Bypass

<p align="center">
  <b>Türkçe</b> | <a href="README_EN.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/tiann/KernelSU"><img src="https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch%20%7C%20Magisk-blue.svg" alt="Platform"></a>
  <a href="https://github.com/bol-van/zapret"><img src="https://img.shields.io/badge/Architecture-aarch64%20%7C%20arm-green.svg" alt="Architecture"></a>
  <a href="module.prop"><img src="https://img.shields.io/badge/Version-v2.0.1-purple.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-orange.svg" alt="License"></a>
</p>

Android cihazlarda kök (root) dizin seviyesinde çalışan, **`nfqws` (zapret)** motoru ve **Zygisk + DobbyHook** tabanlı seçici Per-App DPI ve DoH (DNS over HTTPS) aşma modülü.

`VpnService` (`tun0`) arabirimi açmadan ve sistem geneli ağ ayarlarını bozmadan, **yalnızca seçtiğiniz uygulamaların** (başta Discord olmak üzere) TCP/UDP trafiğini Linux çekirdeği Netfilter (`iptables` / `NFQUEUE`) seviyesinde işler; DNS sorgularını ise Bionic libc seviyesinde yakalayarak şifreli DoH üzerinden yönlendirir.

---

## 🚀 Öne Çıkan Özellikler

### 1. Uygulama Bazlı Seçici DPI Aşma (Per-App Selective DPI)
- Linux çekirdeğinin `owner --uid-owner` filtresini kullanır.
- Sadece `apps.list` içinde belirlediğiniz uygulamaların trafiği desync işlemine girer.
- Bankacılık, kamu veya yerel ağ uygulamalarınıza dokunulmaz; sistemde VPN arabirimi açılmadığı için bankacılık uygulamalarında **"VPN Tespit Edildi" uyarısı vermez**.

### 2. Zygisk + DobbyHook ile Per-App DoH (DNS over HTTPS)
- İSS seviyesinde DNS zehirleme ve engellemelerini doğrudan uygulama sürecinde aşar.
- **Linker Bağımsız DobbyHook Mimarisi:** Android 15, 16 ve 17 (API 35-37) sürümlerindeki dinamik bağlayıcı kısıtlamalarına takılmadan doğrudan bellek adreslerini yamalar.
- **Çift Mimari Desteği (64-bit & 32-bit):** Hem 64-bit (`arm64-v8a`) hem de 32-bit (`armeabi-v7a`) Android uygulamalarını (örneğin Discord mobil istemcisi 32-bit çalışır) eksiksiz destekler.
- **Sıfır İz (Zero-Footprint):** Hedef listede olmayan uygulamalarda Zygisk kütüphanesi bellekten anında boşaltılır (`dlclose`).
- **Fail-Safe Fallback:** DoH servisine ulaşılamazsa çökmeyi önlemek için otomatik olarak sistemin orijinal DNS çözümleyicisine döner.

### 3. Gelişmiş KernelSU & APatch WebUI v2.0
- **Apps:** Cihazdaki kullanıcı ve sistem uygulamalarını listeleme, arama, popüler uygulamalar (Discord, YouTube, Instagram, X vb.) için hızlı seçim çipleri.
- **Presets:** Tek dokunuşla hazır DPI stratejileri (`discord_optimal`, `split_sni_compatible`, `fake_badsum_autottl`, `multisplit_midsni`, `disorder_sni`) ve özel yerel profiller oluşturma / panodan yapıştırma.
- **Auto-Tune:** Belirlenen hedef alan adına (`discord.com` vb.) karşı tüm desync stratejilerini otomatik test edip en hızlı çalışan stratejiyi tek tıkla uygulama.
- **DoH:** Popüler DoH sağlayıcıları (Cloudflare, Google, Quad9, AdGuard) veya özel upstream URL belirleme, tek dokunuşla DNS gecikme ve doğrulama testi.
- **Advanced:** TCP/UDP desync yöntemleri (`fake`, `split`, `disorder`, `multisplit`), split pozisyonları (`sni`, `midsni`), fooling türleri (`md5sig`, `badsum`), TTL ayarları ve serbest nfqws argümanları. Canlı CLI komut önizlemesi ve panodan komut aktarma.

### 4. Tam WebRTC ve Ses / Video Kanalı Desteği
- Standart ve alternatif TLS / HTTPS portları: `80, 443, 2053, 2083, 2087, 2096, 8443`.
- Discord ses kanalları ve WebRTC UDP portları: `50000:65535` ve `19294:19344` (`filter-l7=discord`).
- Discord üzerinde ses kanallarına sorunsuz "RTC Bağlandı" garantisi.

### 5. Sıfır VPN Yuvası & Minimum Pil Tüketimi
- Android `VpnService` yuvasını işgal etmez.
- Doğrudan çekirdek paket kuyruğuyla (NFQUEUE) çalıştığı için arka planda ekstra pil tüketimi ve ısınma yaratmaz.

---

## 📦 Dizin Yapısı

```
app-dpi-bypass/
├── bin/
│   ├── nfqws                   # aarch64 mimarisi için derlenmiş nfqws motoru
│   └── doh_forwarder           # aarch64 mimarisi için derlenmiş yerel Go DoH servisi
├── zygisk/
│   ├── arm64-v8a.so            # 64-bit Zygisk Dobby libc DNS kanca kütüphanesi
│   └── armeabi-v7a.so          # 32-bit Zygisk Dobby libc DNS kanca kütüphanesi
├── src/
│   ├── doh_forwarder/          # Yerel DoH forwarder Go kaynak kodları
│   └── zygisk/                 # Zygisk modülü ve Dobby statik kütüphaneleri C++ kaynak kodları
├── webroot/
│   └── index.html              # KernelSU / APatch yerleşik WebUI v2.0 arayüzü
├── META-INF/                   # Magisk / KernelSU modül kurulum yapısı
├── module.prop                 # Modül meta verisi
├── customize.sh                # Kurulum izin ve dizin yapılandırması
├── service.sh                  # Cihaz açılışında başlatılan arka plan servisi
├── action.sh                   # Yönetici uygulamasındaki eylem butonu tetikleyicisi
├── dpi_ctl.sh                  # Çekirdek iptables, nfqws ve DoH kontrol mekanizması
├── apps.list                   # Varsayılan hedef paket listesi
├── config.conf                 # Varsayılan modül ve DoH yapılandırma dosyası
├── package.sh                  # Modülü flashable zip olarak paketleme betiği
├── deploy.sh                   # Geliştirici ortamından cihaza otomatik dağıtım
├── TODO.md                     # Geliştirme notları
└── .gitignore
```

---

## 🛠️ Kurulum

1. Reponun **Releases** kısmından `app-dpi-bypass-v2.0.0.zip` dosyasını indirin (veya `./package.sh` ile kendiniz derleyin).
2. **KernelSU Manager**, **APatch** veya **Magisk** uygulamasını açın.
3. *Not:* Zygisk özelliğinin yönetici uygulamanızda aktif olduğundan emin olun (KernelSU için ZygiskNext veya Zygisk-on-KernelSU önerilir).
4. **Modüller** sekmesine gidin, **Depolamadan yükle** seçeneğiyle zip dosyasını flaşlayın.
5. Cihazınızı donanımsal olarak **yeniden başlatın** (Zygisk modüllerinin Zygote tarafından yüklenmesi için tam yeniden başlatma gereklidir).

---

## 📱 Kullanım

### 1. WebUI ile Yönetim (Önerilen)
- **KernelSU** veya **APatch** yöneticisini açın.
- **App DPI Bypass** modülünün yanındaki **WebUI** ikonuna dokunun.
- **Apps** sekmesinden hedef uygulamaları seçip **Save & Apply** butonuna dokunun.
- **Presets** veya **Auto-Tune** sekmesinden İSS'nize en uygun DPI stratejisini seçin.
- **DoH** sekmesinden DNS sağlayıcınızı belirleyin ve **Test Resolution** ile test edin.

### 2. Eylem (Action) Butonu
- Modül yöneticisindeki **Eylem / Action** butonuna basarak DPI ve DoH motorunu tek dokunuşla açıp kapatabilirsiniz (toggle).

### 3. Komut Satırı (CLI / Termux / Root Shell)
Cihaz üzerinde root yetkisiyle doğrudan `dpi_ctl.sh` üzerinden tüm fonksiyonları yönetebilirsiniz:

```bash
# Durum ve paket/DoH istatistiklerini görüntüle
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh status

# DPI ve DoH servislerini aç / kapat (toggle)
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh toggle

# Yeni bir paketi listeye ekle ve kuralları güncelle
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh add-app com.discord

# Paketi listeden çıkar
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh del-app com.discord

# Hazır bir strateji profili uygula
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh set-preset discord_optimal

# Otomatik strateji benchmarkı çalıştır
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh autotune discord.com

# DoH üzerinden alan adı çözümleme testi yap
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh test-dns discord.com

# Kuralları ve arka plan servislerini yeniden yükle
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh reload
```

---

## 🔨 Kaynak Koddan Derleme ve Paketleme

### 1. DoH Forwarder Derleme (Go)
```bash
cd src/doh_forwarder
GOOS=android GOARCH=arm64 go build -ldflags="-s -w" -o ../../bin/doh_forwarder .
```

### 2. Zygisk Modüllerini Derleme (Android NDK)
```bash
cd src/zygisk
# 64-bit arm64-v8a
cmake -B build-arm64 -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DCMAKE_BUILD_TYPE=Release
cmake --build build-arm64 --target app_dpi_zygisk
cp build-arm64/libapp_dpi_zygisk.so ../../zygisk/arm64-v8a.so

# 32-bit armeabi-v7a
cmake -B build-arm32 -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-26 -DCMAKE_BUILD_TYPE=Release
cmake --build build-arm32 --target app_dpi_zygisk
cp build-arm32/libapp_dpi_zygisk.so ../../zygisk/armeabi-v7a.so
```

### 3. Flashable Zip Paketleme
```bash
chmod +x package.sh
./package.sh
```
Oluşturulan paket `dist/app-dpi-bypass-v2.0.0.zip` yolunda hazır olacaktır.

---

## 📄 Lisans & Teşekkürler

- `nfqws` ikilisi ve DPI desync algoritmaları [bol-van/zapret](https://github.com/bol-van/zapret) projesine aittir (MIT Lisansı).
- Dobby kanca kütüphanesi [jmpews/Dobby](https://github.com/jmpews/Dobby) projesine aittir (Apache-2.0 Lisansı).
- WebUI, Zygisk Per-App libc hook motoru ve KernelSU seçici yönlendirme mimarisi [MematiBas42](https://github.com/MematiBas42) tarafından geliştirilmiştir.
- Bu proje [MIT Lisansı](LICENSE) altında dağıtılmaktadır.
