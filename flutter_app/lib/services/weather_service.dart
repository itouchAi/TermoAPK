import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/thermostat_state.dart';

class LocationCoordinates {
  final String cityKey;
  final String displayCity;
  final double latitude;
  final double longitude;

  const LocationCoordinates({
    required this.cityKey,
    required this.displayCity,
    required this.latitude,
    required this.longitude,
  });
}

class WeatherReport {
  final String locationName;
  final String cityName;
  final double currentTempC;
  final int humidityPercent;
  final double windKmh;
  final int weatherCode;
  final String conditionTr;
  final String conditionEn;
  final IconData icon;
  final List<DailyWeatherForecast> days;
  final DateTime fetchedAt;

  const WeatherReport({
    required this.locationName,
    required this.cityName,
    required this.currentTempC,
    required this.humidityPercent,
    required this.windKmh,
    required this.weatherCode,
    required this.conditionTr,
    required this.conditionEn,
    required this.icon,
    required this.days,
    required this.fetchedAt,
  });

  bool get hasRainRiskSoon => days.take(2).any((d) {
        final pct = int.tryParse(d.rainChance.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return pct >= 55;
      });

  bool get hasColdDropSoon =>
      days.take(3).any((d) => d.lowTemp <= 8) || (currentTempC - (days.isNotEmpty ? days.first.lowTemp : currentTempC)) >= 8;
}

class WeatherFetchResult {
  final WeatherReport? report;
  final String? errorTr;
  final String? errorEn;

  const WeatherFetchResult.success(WeatherReport this.report)
      : errorTr = null,
        errorEn = null;

  const WeatherFetchResult.failure({
    required String this.errorTr,
    required String this.errorEn,
  }) : report = null;

  bool get ok => report != null;
}

class WeatherService {
  WeatherService._();

  static final Map<String, WeatherReport> _cache = <String, WeatherReport>{};

  static const Map<String, LocationCoordinates> _knownCities = {
    'istanbul': LocationCoordinates(
      cityKey: 'istanbul',
      displayCity: 'İstanbul',
      latitude: 41.0082,
      longitude: 28.9784,
    ),
    'kadikoy': LocationCoordinates(
      cityKey: 'kadikoy',
      displayCity: 'Kadıköy, İstanbul',
      latitude: 40.9903,
      longitude: 29.0293,
    ),
    'izmir': LocationCoordinates(
      cityKey: 'izmir',
      displayCity: 'İzmir',
      latitude: 38.4237,
      longitude: 27.1428,
    ),
    'ankara': LocationCoordinates(
      cityKey: 'ankara',
      displayCity: 'Ankara',
      latitude: 39.9334,
      longitude: 32.8597,
    ),
  };

  static String _normalizeTurkishAscii(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('i̇', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .trim();
  }

  static LocationCoordinates coordinatesForLocation(String locationName) {
    final city = SystemSettingsState.extractCityName(locationName);
    final normCity = _normalizeTurkishAscii(city);
    final normFull = _normalizeTurkishAscii(locationName);

    for (final entry in _knownCities.entries) {
      if (normCity.contains(entry.key) || normFull.contains(entry.key)) {
        return entry.value;
      }
    }
    return _knownCities['istanbul']!;
  }

  static WeatherReport? getCached(String locationName) {
    final coords = coordinatesForLocation(locationName);
    return _cache[coords.cityKey];
  }

  static void clearCache() => _cache.clear();

  static (String conditionTr, String conditionEn, IconData icon) describeWmoCode(
    int code, {
    bool isDay = true,
  }) {
    if (code == 0) {
      return isDay
          ? ('Güneşli', 'Sunny', Icons.wb_sunny_outlined)
          : ('Açık Gece', 'Clear Night', Icons.nights_stay_outlined);
    }
    if (code == 1 || code == 2) {
      return ('Parçalı Bulutlu', 'Partly Cloudy', Icons.wb_cloudy_outlined);
    }
    if (code == 3) {
      return ('Çok Bulutlu', 'Overcast', Icons.cloud_outlined);
    }
    if (code == 45 || code == 48) {
      return ('Sisli & Puslu', 'Foggy', Icons.blur_on_rounded);
    }
    if (code == 51 || code == 53 || code == 55 || code == 56 || code == 57) {
      return ('Çisenti', 'Drizzle', Icons.water_drop_outlined);
    }
    if (code == 61 || code == 63 || code == 80 || code == 81) {
      return ('Yağmurlu', 'Rainy', Icons.water_drop_outlined);
    }
    if (code == 65 || code == 66 || code == 67 || code == 82) {
      return ('Kuvvetli Sağanak', 'Heavy Rain', Icons.water_drop_outlined);
    }
    if (code >= 71 && code <= 77 || code == 85 || code == 86) {
      return ('Karlı', 'Snowy', Icons.ac_unit_rounded);
    }
    if (code >= 95) {
      return ('Gök Gürültülü Fırtına', 'Thunderstorm', Icons.thunderstorm_outlined);
    }
    return ('Bulutlu', 'Cloudy', Icons.cloud_outlined);
  }

  static const List<String> _monthsTr = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  static const List<String> _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _weekdaysTr = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
  ];
  static const List<String> _weekdaysEn = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static String formatDateLabel(DateTime dt, LangCode lang) {
    final months = lang == LangCode.tr ? _monthsTr : _monthsEn;
    return '${dt.day} ${months[(dt.month - 1).clamp(0, 11)]}';
  }

  static Uri buildForecastUri(LocationCoordinates coords) {
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': coords.latitude.toStringAsFixed(4),
      'longitude': coords.longitude.toStringAsFixed(4),
      'current': 'temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,is_day',
      'hourly': 'temperature_2m,precipitation_probability,wind_speed_10m,weather_code',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'forecast_days': '5',
      'timezone': 'auto',
    });
  }

  static WeatherReport parseOpenMeteoJson(
    Map<String, dynamic> map, {
    required String locationName,
    LangCode lang = LangCode.tr,
    DateTime? fetchedAt,
  }) {
    final coords = coordinatesForLocation(locationName);
    final current = map['current'] is Map
        ? Map<String, dynamic>.from(map['current'] as Map)
        : <String, dynamic>{};
    final currentTemp = (current['temperature_2m'] as num?)?.toDouble();
    final currentHumidity = (current['relative_humidity_2m'] as num?)?.round();
    final currentWind = (current['wind_speed_10m'] as num?)?.toDouble();
    final currentCode = (current['weather_code'] as num?)?.toInt() ?? 0;
    final isDay = ((current['is_day'] as num?)?.toInt() ?? 1) == 1;

    if (currentTemp == null) {
      throw const FormatException('Missing current.temperature_2m in Open-Meteo response');
    }

    final currentDesc = describeWmoCode(currentCode, isDay: isDay);

    final hourly = map['hourly'] is Map
        ? Map<String, dynamic>.from(map['hourly'] as Map)
        : <String, dynamic>{};
    final hTimes = (hourly['time'] as List?) ?? const [];
    final hTemps = (hourly['temperature_2m'] as List?) ?? const [];
    final hRain = (hourly['precipitation_probability'] as List?) ?? const [];
    final hWind = (hourly['wind_speed_10m'] as List?) ?? const [];
    final hCodes = (hourly['weather_code'] as List?) ?? const [];

    final hourlyByDate = <String, List<HourlyWeatherSlot>>{};
    for (int i = 0; i < hTimes.length; i++) {
      final rawTime = hTimes[i]?.toString() ?? '';
      final tIdx = rawTime.indexOf('T');
      if (tIdx <= 0 || tIdx + 5 > rawTime.length) continue;
      final datePart = rawTime.substring(0, tIdx);
      final hhmm = rawTime.substring(tIdx + 1, tIdx + 6);
      final hourNum = int.tryParse(hhmm.substring(0, 2)) ?? 0;
      // Keep 3-hour intervals (00:00, 03:00, ..., 21:00) for clean strip legibility
      if (hourNum % 3 != 0) continue;

      final hTemp = (i < hTemps.length && hTemps[i] is num)
          ? (hTemps[i] as num).round()
          : currentTemp.round();
      final hProb = (i < hRain.length && hRain[i] is num)
          ? (hRain[i] as num).round().clamp(0, 100)
          : 0;
      final hWindVal = (i < hWind.length && hWind[i] is num)
          ? (hWind[i] as num).round()
          : (currentWind?.round() ?? 0);
      final hCode = (i < hCodes.length && hCodes[i] is num)
          ? (hCodes[i] as num).toInt()
          : currentCode;
      final desc = describeWmoCode(hCode, isDay: hourNum >= 6 && hourNum < 20);

      hourlyByDate.putIfAbsent(datePart, () => []).add(
            HourlyWeatherSlot(
              hour: hhmm,
              temp: hTemp,
              conditionTr: desc.$1,
              conditionEn: desc.$2,
              rainChance: '%$hProb',
              windKmh: '$hWindVal km/s',
              icon: desc.$3,
            ),
          );
    }

    final daily = map['daily'] is Map
        ? Map<String, dynamic>.from(map['daily'] as Map)
        : <String, dynamic>{};
    final dTimes = (daily['time'] as List?) ?? const [];
    final dCodes = (daily['weather_code'] as List?) ?? const [];
    final dMax = (daily['temperature_2m_max'] as List?) ?? const [];
    final dMin = (daily['temperature_2m_min'] as List?) ?? const [];
    final dRain = (daily['precipitation_probability_max'] as List?) ?? const [];

    final days = <DailyWeatherForecast>[];
    for (int i = 0; i < dTimes.length && i < 5; i++) {
      final dateStr = dTimes[i]?.toString() ?? '';
      final parsedDate = DateTime.tryParse(dateStr) ?? (fetchedAt ?? DateTime.now()).add(Duration(days: i));
      final code = (i < dCodes.length && dCodes[i] is num) ? (dCodes[i] as num).toInt() : currentCode;
      final high = (i < dMax.length && dMax[i] is num) ? (dMax[i] as num).round() : currentTemp.round();
      final low = (i < dMin.length && dMin[i] is num) ? (dMin[i] as num).round() : currentTemp.round();
      final rainMax = (i < dRain.length && dRain[i] is num) ? (dRain[i] as num).round().clamp(0, 100) : 0;
      final desc = describeWmoCode(code, isDay: true);

      final String dayTr;
      final String dayEn;
      if (i == 0) {
        dayTr = 'Bugün';
        dayEn = 'Today';
      } else if (i == 1) {
        dayTr = 'Yarın';
        dayEn = 'Tomorrow';
      } else {
        final wIdx = (parsedDate.weekday - 1).clamp(0, 6);
        dayTr = _weekdaysTr[wIdx];
        dayEn = _weekdaysEn[wIdx];
      }

      days.add(
        DailyWeatherForecast(
          dayTr: dayTr,
          dayEn: dayEn,
          dateLabel: formatDateLabel(parsedDate, lang),
          conditionTr: desc.$1,
          conditionEn: desc.$2,
          highTemp: high,
          lowTemp: low,
          rainChance: '%$rainMax',
          icon: desc.$3,
          hourly: hourlyByDate[dateStr] ?? const [],
        ),
      );
    }

    if (days.isEmpty) {
      throw const FormatException('Missing daily forecast array in Open-Meteo response');
    }

    return WeatherReport(
      locationName: locationName,
      cityName: coords.displayCity,
      currentTempC: double.parse(currentTemp.toStringAsFixed(1)),
      humidityPercent: (currentHumidity ?? 0).clamp(0, 100),
      windKmh: double.parse((currentWind ?? 0.0).toStringAsFixed(1)),
      weatherCode: currentCode,
      conditionTr: currentDesc.$1,
      conditionEn: currentDesc.$2,
      icon: currentDesc.$3,
      days: days,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  static Future<WeatherFetchResult> fetchForecast(
    String locationName, {
    LangCode lang = LangCode.tr,
    http.Client? client,
  }) async {
    final coords = coordinatesForLocation(locationName);
    final uri = buildForecastUri(coords);
    final activeClient = client ?? http.Client();
    final ownsClient = client == null;

    try {
      final resp = await activeClient.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map) {
          return const WeatherFetchResult.failure(
            errorTr: 'Hava durumu yanıtı okunamadı.',
            errorEn: 'Invalid weather response payload.',
          );
        }
        final report = parseOpenMeteoJson(
          Map<String, dynamic>.from(decoded),
          locationName: locationName,
          lang: lang,
        );
        _cache[coords.cityKey] = report;
        return WeatherFetchResult.success(report);
      }
      return WeatherFetchResult.failure(
        errorTr: 'Hava servisi yanıt vermedi (HTTP ${resp.statusCode}).',
        errorEn: 'Weather service returned HTTP ${resp.statusCode}.',
      );
    } catch (e) {
      return WeatherFetchResult.failure(
        errorTr: '${coords.displayCity} canlı hava raporu alınamadı (İnternet/API bağlantısını kontrol edin).',
        errorEn: 'Unable to fetch live weather for ${coords.displayCity}.',
      );
    } finally {
      if (ownsClient) {
        activeClient.close();
      }
    }
  }
}
