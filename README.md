# App DPI Bypass

[![Platform](https://img.shields.io/badge/Platform-KernelSU%20%7C%20APatch%20%7C%20Magisk-blue.svg)](https://github.com/tiann/KernelSU)
[![Architecture](https://img.shields.io/badge/Architecture-aarch64-green.svg)](https://github.com/bol-van/zapret)
[![License](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)

Android cihazlarda kök dizin seviyesinde çalışan, **`nfqws` (zapret)** motoru tabanlı seçici DPI aşma modülü.

VpnService (`tun0`) yuvası açmadan ve sistem geneli ağ ayarlarını değiştirmeden, **yalnızca seçtiğiniz uygulamaların** (başta Discord olmak üzere) giden TCP/UDP trafiğini Linux çekirdeği Netfilter (`iptables` / `NFQUEUE`) seviyesinde işleyerek DPI sansürünü aşar.

---

## 🚀 Öne Çıkan Özellikler

- **Uygulama Bazlı Seçici Yönlendirme (Per-App Selective):**
  - Linux çekirdeğinin `owner --uid-owner` filtresini kullanır.
  - Sadece belirlediğiniz uygulamaların trafiği desync işlemine girer; bankacılık, kamu, yerel ağ veya diğer uygulamalarınızın trafiğine kesinlikle dokunulmaz.
- **KernelSU & APatch Yerleşik WebUI:**
  - Modern, saf ve duyarlı (responsive) web arayüzü.
  - Cihazda yüklü uygulamaları otomatik listeleme, arama ve tek dokunuşla seçme.
  - Anlık durum, nfqws PID, işlenen paket ve veri boyutu göstergesi.
- **Eksiksiz WebRTC & Ses/Video Kanalı Desteği:**
  - Standart HTTPS / TLS portları: `80, 443, 2053, 2083, 2087, 2096, 8443`
  - Discord ses ve WebRTC UDP portları: `50000:65535` ve `19294:19344`
- **Sıfır VPN Yuvası & Düşük Güç Tüketimi:**
  - `VpnService` açmaz, dolayısıyla Android'in tekil VPN yuvasını işgal etmez.
  - Doğrudan çekirdek paket kuyruğuyla (NFQUEUE) çalıştığı için arka planda ekstra pil tüketimi oluşturmaz.
- **Kalıcı Yapılandırma:**
  - Seçili uygulamalar `/data/adb/app-dpi-bypass/apps.list` dosyasında saklanır; modül güncellense veya yeniden yüklense bile seçimleriniz korunur.

---

## 📦 Dizin Yapısı

```
app-dpi-bypass/
├── bin/
│   └── nfqws            # aarch64 mimarisi için derlenmiş nfqws ikilisi
├── webroot/
│   └── index.html       # KernelSU / APatch yerleşik WebUI arayüzü
├── META-INF/            # Magisk / KernelSU modül kurulum yapısı
├── module.prop          # Modül meta verisi
├── customize.sh         # Kurulum sırasında izin ve dizin yapılandırması
├── service.sh           # Cihaz açılışında başlatılan arka plan servisi
├── action.sh            # Yönetici uygulamasındaki eylem butonu tetikleyicisi
├── dpi_ctl.sh           # Çekirdek iptables ve nfqws kontrol mekanizması
├── apps.list            # Varsayılan hedef paket listesi
├── package.sh           # Modülü flashable zip olarak paketleme betiği
├── deploy.sh            # Geliştirici ortamından cihaza otomatik dağıtım
├── TODO.md              # Zygisk + Native DoH entegrasyonu yol haritası
└── .gitignore
```

---

## 🛠️ Kurulum

1. Reponun **Releases** kısmından `app-dpi-bypass.zip` dosyasını indirin (veya `./package.sh` ile kendiniz derleyin).
2. **KernelSU Manager**, **APatch** veya **Magisk** uygulamasını açın.
3. **Modüller** sekmesine gidin, **Depolamadan yükle** seçeneğiyle zip dosyasını flaşlayın.
4. Cihazınızı yeniden başlatın.

---

## 📱 Kullanım

### 1. WebUI ile Yönetim (Önerilen)
- **KernelSU** veya **APatch** yöneticisini açın.
- **App DPI Bypass** modülünün yanındaki **WebUI** ikonuna dokunun.
- Listeden hedef uygulamaları seçip alttaki **Kaydet ve Uygula** butonuna dokunun. Değişiklikler anında yürürlüğe girer.

### 2. Eylem (Action) Butonu
- Modül yöneticisindeki "Eylem / Action" butonuna basarak bypass motorunu tek dokunuşla açıp kapatabilirsiniz (toggle).

### 3. Komut Satırı (CLI / Termux / Root Shell)
Cihaz üzerinde root yetkisiyle doğrudan `dpi_ctl.sh` üzerinden tüm işlemleri yönetebilirsiniz:

```bash
# Durumu ve aktif işlenen paket istatistiklerini gör
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh status

# DPI motorunu aç / kapat (toggle)
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh toggle

# Yeni bir paketi listeye ekle ve kuralları güncelle
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh add-app com.discord

# Paketi listeden çıkar
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh del-app com.discord

# Kuralları ve nfqws sürecini yeniden yükle
sh /data/adb/modules/app-dpi-bypass/dpi_ctl.sh reload
```

---

## 🔨 Geliştirme ve Paketleme

Modülü bilgisayarınızda flashable zip haline getirmek için:

```bash
chmod +x package.sh
./package.sh
```

Çıktı `dist/app-dpi-bypass-v2.0.0.zip` konumuna oluşturulur.

---

## 📄 Lisans & Teşekkürler

- `nfqws` ikilisi ve DPI desync algoritmaları [bol-van/zapret](https://github.com/bol-van/zapret) projesine aittir (MIT License).
- WebUI ve KernelSU per-app seçici mimarisi [MematiBas42](https://github.com/MematiBas42) tarafından geliştirilmiştir.
- Bu proje [MIT Lisansı](LICENSE) altında dağıtılmaktadır.
