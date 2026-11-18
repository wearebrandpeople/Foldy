# Klasör Panosu

Finder’da açılan klasörleri menü çubuğundan tekrar açmak için yerel macOS uygulaması.

**Sürüm:** 0.4.1 · **Platform:** macOS 13+, Apple Silicon için yerel derleme.

## Özellikler

- Son ziyaret edilen 100 klasör, ad/yol araması ve tek tıkla açma.
- Kalıcı sabitleme; raptiye yalnızca satırın üzerine gelindiğinde görünür.
- Satır hover vurgusu ve daha soluk klasör yolu.
- macOS’un yerel kaydırmalı “Sil” eylemi; yalnızca geçmiş kaydı kaldırılır.
- Oturum açılışında başlatma desteği.

## Derleme

Xcode Command Line Tools ve Swift gerektirir:

```sh
bash build.sh
open 'Klasör Panosu.app'
```

Derleme geçmiş modeli testlerini de çalıştırır. Çıktı yerel ad-hoc imzalıdır;
Apple Developer dağıtım imzası veya notarizasyon içermez.

## Kurulum ve otomatik başlatma

Uygulamayı `/Applications` klasörüne kopyalayıp bir kez açın. Ardından:

```sh
'/Applications/Klasör Panosu.app/Contents/MacOS/KlasorPanosu' --enable-login
```

İlk klasör kaydında Finder otomasyon izni istenebilir. Başlangıç kaydı
Sistem Ayarları > Genel > Giriş Öğeleri bölümünden yönetilebilir.

## Veriler ve sınırlar

Geçmiş yalnızca `~/Library/Application Support/KlasorPanosu/history.json`
dosyasında saklanır. Uygulama veri göndermez. Finder öndeyken etkin pencere
1,5 saniyede bir okunur; çok hızlı geçilen klasörler atlanabilir. Önceki
ziyaretler alınmaz. Fiziksel klasör olmayan arama görünümleri kaydedilmeyebilir.
Yerel kaydırma trackpad/Magic Mouse yatay kaydırma hareketini kullanır.

## Proje düzeni

- `Source/main.swift`: uygulama ve geçmiş modeli testleri.
- `build.sh`: derleme, uygulama paketi, yerel imza ve testler.
- `CHANGELOG.md`: sürüm notları.

## Doğrulama

0.4.1 derlemesi ve geçmiş modeli testleri geçti; kurulu uygulamanın çalıştığı
ve otomatik başlangıç kaydının etkin olduğu doğrulandı. Son hover değişikliğinin
canlı görsel kontrolü ve gerçek oturum kapatma/açma testi yapılmadı.
