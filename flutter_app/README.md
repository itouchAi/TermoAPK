# Termostat Flow (Saf Flutter Android APK)

WebView veya HTML/CSS içermeyen, **%100 Dart + Impeller/Skia GLSL FragmentShader** tabanlı mobil termostat uygulamasıdır.

## Mimari
- `shaders/flow_tab_bar.frag`: `FlutterFragCoord()` tabanlı sıvı cam Flow Tab Bar ve bütünleşik FBM atmosfer arka plan shader'ı.
- `lib/widgets/flow_tab_bar.dart`: `FragmentProgram` + `CustomPainter` + `PathMetric` çizim animasyonlu 4 sekmeli (`Termo.`, `Hava`, `Rapor`, `Prog.`) alt gezinme barı.
- `lib/widgets/rotary_dial.dart`: `CustomPainter` + `GestureDetector` ile parmakla döndürülebilen döner kadran ve `±0.5°C` adım butonları.
- `lib/screens/thermostat_screen.dart`: `OrientationBuilder` ve `LayoutBuilder` ile dikey (Portrait) ve yatay (Landscape) modlara dinamik uyum sağlayan ana kontrol ekranı.

## Android APK Oluşturma
Bilgisayarınızda Flutter SDK kurulu olan klasörde:
```bash
cd flutter_app
flutter create . --platforms=android
flutter pub get
flutter build apk --release
```
Çıktı APK dosyası `build/app/outputs/flutter-apk/app-release.apk` konumunda oluşturulur.
