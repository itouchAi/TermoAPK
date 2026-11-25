import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';
import '../services/firebase_sync_service.dart';
import '../widgets/tactile_button.dart';

Future<void> showGoogleHomeSheet({
  required BuildContext context,
  required LangCode lang,
  required double roomTemp,
  required double targetTemp,
  required BoilerTelemetry boiler,
  required SystemSettingsState initialSettings,
  required ValueChanged<SystemSettingsState> onUpdateSettings,
  required ValueChanged<double> onApplyTargetTemp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GoogleHomeModal(
      lang: lang,
      roomTemp: roomTemp,
      targetTemp: targetTemp,
      boiler: boiler,
      initialSettings: initialSettings,
      onUpdateSettings: onUpdateSettings,
      onApplyTargetTemp: onApplyTargetTemp,
    ),
  );
}

class _GoogleHomeModal extends StatefulWidget {
  final LangCode lang;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final SystemSettingsState initialSettings;
  final ValueChanged<SystemSettingsState> onUpdateSettings;
  final ValueChanged<double> onApplyTargetTemp;

  const _GoogleHomeModal({
    required this.lang,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.initialSettings,
    required this.onUpdateSettings,
    required this.onApplyTargetTemp,
  });

  @override
  State<_GoogleHomeModal> createState() => _GoogleHomeModalState();
}

class _GoogleHomeModalState extends State<_GoogleHomeModal> {
  late SystemSettingsState _settings;
  late double _liveTarget;
  late BoilerTelemetry _liveBoiler;
  String? _assistantReply;
  String? _syncStatus;
  bool _syncError = false;
  bool _syncing = false;
  bool _copiedCode = false;

  static const _rooms = ['Salon', 'Oturma Odası', 'Yatak Odası', 'Mutfak'];

  static const _cloudFunctionSnippet = '''const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.smartHomeFulfillment = functions.https.onRequest(async (req, res) => {
  const { inputs = [], requestId } = req.body;
  const ref = admin.database().ref("kombi");
  const snap = await ref.once("value");
  const state = snap.val() || { targetTemp: 22.5, roomTemp: 21.8 };

  for (const input of inputs) {
    if (input.intent === "action.devices.SYNC") {
      return res.json({
        requestId,
        payload: {
          agentUserId: "termostat-user-01",
          devices: [{
            id: "kombi-main",
            type: "action.devices.types.THERMOSTAT",
            traits: ["action.devices.traits.TemperatureSetting"],
            name: { name: "Termostat Kombi" },
            attributes: { availableThermostatModes: ["heat", "eco", "off"] }
          }]
        }
      });
    }
    if (input.intent === "action.devices.EXECUTE") {
      const cmd = input.payload.commands[0].execution[0];
      if (cmd.command === "action.devices.commands.ThermostatTemperatureSetpoint") {
        await ref.update({ targetTemp: cmd.params.thermostatTemperatureSetpoint });
      }
    }
  }
  res.json({ requestId, payload: { online: true, thermostatTemperatureAmbient: state.roomTemp } });
});''';

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _liveTarget = widget.targetTemp;
    _liveBoiler = widget.boiler;
  }

  void _haptic() {
    if (_settings.hapticEnabled) HapticFeedback.selectionClick();
  }

  Future<void> _pushToFirebase({bool silent = false}) async {
    if (_syncing) return;
    if (!silent) {
      setState(() {
        _syncing = true;
        _syncStatus = null;
      });
    }
    final res = await FirebaseSyncService.pushState(
      baseUrl: _settings.firebaseRtdbUrl,
      apiKey: _settings.firebaseApiKey,
      nodePath: _settings.firebaseNodePath,
      roomName: _settings.googleHomeRoom,
      espDeviceId: _settings.espDeviceId,
      roomTemp: widget.roomTemp,
      targetTemp: _liveTarget,
      boiler: _liveBoiler,
    );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncStatus = widget.lang == LangCode.tr ? res.messageTr : res.messageEn;
      _syncError = !res.ok;
    });
  }

  Future<void> _pullFromFirebase() async {
    if (_syncing) return;
    _haptic();
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    final res = await FirebaseSyncService.pullState(
      baseUrl: _settings.firebaseRtdbUrl,
      apiKey: _settings.firebaseApiKey,
      nodePath: _settings.firebaseNodePath,
    );
    if (!mounted) return;
    if (res.ok && res.remoteTargetTemp != null) {
      widget.onApplyTargetTemp(res.remoteTargetTemp!);
      _liveTarget = res.remoteTargetTemp!;
      _liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTarget);
    }
    setState(() {
      _syncing = false;
      _syncStatus = widget.lang == LangCode.tr ? res.messageTr : res.messageEn;
      _syncError = !res.ok;
    });
  }

  void _toggleLink(bool value) {
    _haptic();
    final next = _settings.copyWith(googleHomeLinked: value);
    setState(() => _settings = next);
    widget.onUpdateSettings(next);
    if (value) {
      _pushToFirebase();
    }
  }

  void _selectRoom(String room) {
    _haptic();
    final next = _settings.copyWith(googleHomeRoom: room);
    setState(() => _settings = next);
    widget.onUpdateSettings(next);
    if (_settings.googleHomeLinked) {
      _pushToFirebase(silent: true);
    }
  }

  void _runSimCommand(int index) {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    if (index == 0) {
      widget.onApplyTargetTemp(23.5);
      setState(() {
        _liveTarget = 23.5;
        _liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, 23.5);
        _assistantReply = tr
            ? 'Google Asistan: "Tamam, ${_settings.googleHomeRoom} termostatı 23.5°C olarak ayarlandı."'
            : 'Google Assistant: "Got it, setting ${_settings.googleHomeRoom} thermostat to 23.5°C."';
      });
      if (_settings.googleHomeLinked) _pushToFirebase(silent: true);
    } else if (index == 1) {
      widget.onApplyTargetTemp(20.0);
      setState(() {
        _liveTarget = 20.0;
        _liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, 20.0);
        _assistantReply = tr
            ? 'Google Asistan: "Kombi Eko moduna (20.0°C) geçirildi."'
            : 'Google Assistant: "Thermostat switched to Eco mode (20.0°C)."';
      });
      if (_settings.googleHomeLinked) _pushToFirebase(silent: true);
    } else {
      setState(() {
        _assistantReply = tr
            ? 'Google Asistan: "${_settings.googleHomeRoom} şu an ${widget.roomTemp.toStringAsFixed(1)}°C, hedef ${_liveTarget.toStringAsFixed(1)}°C."'
            : 'Google Assistant: "${_settings.googleHomeRoom} is currently ${widget.roomTemp.toStringAsFixed(1)}°C, set to ${_liveTarget.toStringAsFixed(1)}°C."';
      });
    }
  }

  Future<void> _copyCode() async {
    _haptic();
    await Clipboard.setData(const ClipboardData(text: _cloudFunctionSnippet));
    if (!mounted) return;
    setState(() => _copiedCode = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedCode = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final tr = widget.lang == LangCode.tr;
    final liveBoiler = _liveBoiler;

    final simCommands = [
      tr
          ? '"Hey Google, oturma odasını 23.5 derece yap"'
          : '"Hey Google, set living room to 23.5 degrees"',
      tr
          ? '"Hey Google, kombiyi Eko moda al"'
          : '"Hey Google, set boiler to Eco mode"',
      tr
          ? '"Hey Google, oda sıcaklığı kaç?"'
          : '"Hey Google, what is the room temperature?"',
    ];

    final setupSteps = [
      (
        '1',
        tr ? 'Google Actions Console' : 'Google Actions Console',
        tr
            ? 'console.actions.google.com adresinden yeni bir "Smart Home" projesi oluşturun.'
            : 'Create a new "Smart Home" project at console.actions.google.com.',
      ),
      (
        '2',
        tr ? 'Fulfillment Webhook (Haberleşme Köprüsü)' : 'Fulfillment Webhook',
        tr
            ? 'Google Asistan komutlarını Firebase RTDB adresinize yönlendirmek için aşağıdaki hazır Cloud Function kodunu deploy edin.'
            : 'Deploy the Cloud Function snippet below so Assistant intents sync with your Firebase RTDB.',
      ),
      (
        '3',
        tr ? 'Google Home Uygulaması' : 'Google Home App',
        tr
            ? 'Telefonunuzda Google Home uygulamasını açın, "Cihaz Ekle > Google ile Çalışır" menüsünden projenizi seçin.'
            : 'Open Google Home app, go to "Add Device > Works with Google" and link your project.',
      ),
    ];

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.90),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 680 : 480),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E15).withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.78), blurRadius: 36, offset: const Offset(0, -10)),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.38)),
                      ),
                      child: const Icon(Icons.home_outlined, color: Color(0xFF38BDF8), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Google Home & Asistan',
                                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tr ? 'Google ile Uyumlu' : 'Works with Google',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            tr
                                ? 'Firebase üzerinden Google Asistan ile sesli kontrol entegrasyonu'
                                : 'Google Assistant voice sync via Firebase Realtime DB',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.58)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TactilePress(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF7DD3FC), size: 19),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    // Firebase Bridge Banner + Room Selection
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: _settings.googleHomeLinked ? 0.12 : 0.05),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _settings.googleHomeLinked
                              ? const Color(0xFF10B981).withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _settings.googleHomeLinked
                                          ? (tr ? 'Firebase Realtime DB Köprüsü Devrede' : 'Firebase RTDB Bridge Active')
                                          : (tr ? 'Firebase Realtime DB Köprüsü Hazır' : 'Firebase RTDB Bridge Standby'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _settings.googleHomeLinked ? const Color(0xFF6EE7B7) : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'URL: ${_settings.firebaseRtdbUrl}',
                                      style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.62)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _settings.googleHomeLinked,
                                activeThumbColor: const Color(0xFF10B981),
                                onChanged: _toggleLink,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Text(
                                  '${tr ? 'Oda' : 'Room'}: ',
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65)),
                                ),
                                for (final r in _rooms) ...[
                                  const SizedBox(width: 6),
                                  TactilePress(
                                    child: GestureDetector(
                                      onTap: () => _selectRoom(r),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _settings.googleHomeRoom == r
                                              ? const Color(0xFF38BDF8).withValues(alpha: 0.25)
                                              : Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _settings.googleHomeRoom == r
                                                ? const Color(0xFF38BDF8)
                                                : Colors.white.withValues(alpha: 0.10),
                                          ),
                                        ),
                                        child: Text(
                                          r,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TactilePress.card(
                                  enabled: !_syncing,
                                  child: OutlinedButton.icon(
                                    onPressed: _syncing ? null : () => _pushToFirebase(),
                                    icon: Icon(_syncing ? Icons.sync_rounded : Icons.cloud_upload_outlined, size: 15),
                                    label: Text(
                                      tr ? 'Firebase\'e Yaz (Test)' : 'Push to RTDB',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF6EE7B7),
                                      side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TactilePress.card(
                                  enabled: !_syncing,
                                  child: OutlinedButton.icon(
                                    onPressed: _syncing ? null : _pullFromFirebase,
                                    icon: const Icon(Icons.cloud_download_outlined, size: 15),
                                    label: Text(
                                      tr ? 'Firebase\'den Çek' : 'Pull from RTDB',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF7DD3FC),
                                      side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_syncStatus != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _syncStatus!,
                              style: TextStyle(
                                fontSize: 11,
                                color: _syncError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Google Home Device Profile (2x2 Grid)
                    Text(
                      tr ? 'Google Home Cihaz Profili (Akıllı Termostat)' : 'Google Home Device Profile (Smart Thermostat)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 2.45,
                      children: [
                        _ProfileTile(label: tr ? 'Cihaz Tipi' : 'Device Type', value: 'THERMOSTAT'),
                        _ProfileTile(
                          label: tr ? 'Canlı Oda Sıcaklığı' : 'Ambient Temp',
                          value: '${widget.roomTemp.toStringAsFixed(1)}°C',
                        ),
                        _ProfileTile(
                          label: tr ? 'Hedef Sıcaklık' : 'Target Setpoint',
                          value: '${_liveTarget.toStringAsFixed(1)}°C',
                          valueColor: const Color(0xFFF59E0B),
                        ),
                        _ProfileTile(
                          label: tr ? 'Kombi Yanma Durumu' : 'Boiler State',
                          value: liveBoiler.isHeating
                              ? (tr ? 'Aktif Ateşleme 🔥' : 'Active Flame 🔥')
                              : (tr ? 'Beklemede ❄️' : 'Standby ❄️'),
                          valueColor: liveBoiler.isHeating ? const Color(0xFFF97316) : const Color(0xFF38BDF8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Google Assistant Command Simulator
                    Text(
                      tr ? 'Google Asistan Komut Simülatörü' : 'Google Assistant Command Simulator',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr
                          ? 'Google Home cihazınızdan söylenmiş gibi aşağıdaki komutları test edebilirsiniz:'
                          : 'Test assistant commands as if spoken to your Google Home speaker:',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.60)),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < simCommands.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.record_voice_over_outlined, size: 16, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                simCommands[i],
                                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TactilePress(
                              child: FilledButton(
                                onPressed: () => _runSimCommand(i),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Text(tr ? 'Test Et' : 'Test', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_assistantReply != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.40)),
                        ),
                        child: Text(
                          _assistantReply!,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFA7F3D0)),
                        ),
                      ),

                    const SizedBox(height: 6),

                    // 3-Step Setup Guide
                    Text(
                      tr ? 'Google Home\'a Bağlama Adımları (3 Basit Adım)' : '3-Step Setup Guide',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    for (final step in setupSteps)
                      Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0284C7)),
                              child: Text(step.$1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(step.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text(step.$3, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65), height: 1.35)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Ready Firebase Cloud Functions Code
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr ? 'Hazır Firebase Cloud Functions Kodu:' : 'Ready Firebase Cloud Functions Code:',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                        ),
                        TactilePress(
                          child: OutlinedButton.icon(
                            onPressed: _copyCode,
                            icon: Icon(_copiedCode ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                            label: Text(_copiedCode ? (tr ? 'Kopyalandı' : 'Copied') : (tr ? 'Kodu Kopyala' : 'Copy Code'), style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _copiedCode ? const Color(0xFF6EE7B7) : const Color(0xFF7DD3FC),
                              side: BorderSide(color: (_copiedCode ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.45)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: const SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          _cloudFunctionSnippet,
                          style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFFBAE6FD), height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Footer
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B10),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TactilePress(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                        ),
                        child: Text(tr ? 'Tamam' : 'Done', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ProfileTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
