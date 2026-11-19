import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';

Future<void> showSystemSettingsSheet({
  required BuildContext context,
  required LangCode lang,
  required String locationName,
  required Color accentColor,
  required SystemSettingsState initialSettings,
  required ValueChanged<LangCode> onChangeLang,
  required ValueChanged<String> onChangeLocation,
  required ValueChanged<SystemSettingsState> onSaveSettings,
  required VoidCallback onOpenAmbient,
  required VoidCallback onResetTelemetryHistory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SystemSettingsModal(
      lang: lang,
      locationName: locationName,
      accentColor: accentColor,
      initialSettings: initialSettings,
      onChangeLang: onChangeLang,
      onChangeLocation: onChangeLocation,
      onSaveSettings: onSaveSettings,
      onOpenAmbient: onOpenAmbient,
      onResetTelemetryHistory: onResetTelemetryHistory,
    ),
  );
}

class _SystemSettingsModal extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final Color accentColor;
  final SystemSettingsState initialSettings;
  final ValueChanged<LangCode> onChangeLang;
  final ValueChanged<String> onChangeLocation;
  final ValueChanged<SystemSettingsState> onSaveSettings;
  final VoidCallback onOpenAmbient;
  final VoidCallback onResetTelemetryHistory;

  const _SystemSettingsModal({
    required this.lang,
    required this.locationName,
    required this.accentColor,
    required this.initialSettings,
    required this.onChangeLang,
    required this.onChangeLocation,
    required this.onSaveSettings,
    required this.onOpenAmbient,
    required this.onResetTelemetryHistory,
  });

  @override
  State<_SystemSettingsModal> createState() => _SystemSettingsModalState();
}

class _SystemSettingsModalState extends State<_SystemSettingsModal> {
  late SystemSettingsState _draft;
  late LangCode _lang;
  late String _location;
  bool _editOrderMode = false;
  SettingsItemId? _expandedId;
  String? _statusBanner;

  final _pinInputCtrl = TextEditingController();
  final _tgTokenCtrl = TextEditingController();
  final _tgChatCtrl = TextEditingController();
  final _firebaseUrlCtrl = TextEditingController();
  final _espIdCtrl = TextEditingController();

  static const _locations = ['Ev · İstanbul', 'Yazlık · İzmir', 'Ofis · Ankara'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
    _lang = widget.lang;
    _location = widget.locationName;
    _tgTokenCtrl.text = _draft.telegramToken;
    _tgChatCtrl.text = _draft.telegramChatId;
    _firebaseUrlCtrl.text = _draft.firebaseRtdbUrl;
    _espIdCtrl.text = _draft.espDeviceId;
  }

  @override
  void dispose() {
    _pinInputCtrl.dispose();
    _tgTokenCtrl.dispose();
    _tgChatCtrl.dispose();
    _firebaseUrlCtrl.dispose();
    _espIdCtrl.dispose();
    super.dispose();
  }

  void _hapticTap() {
    if (_draft.hapticEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  void _moveItem(int oldIdx, int newIdx) {
    _hapticTap();
    setState(() {
      final list = List<SettingsItemId>.from(_draft.menuOrder);
      final item = list.removeAt(oldIdx);
      list.insert(newIdx.clamp(0, list.length), item);
      _draft = _draft.copyWith(menuOrder: list);
    });
  }

  void _shiftItem(int idx, int delta) {
    final target = idx + delta;
    if (target < 0 || target >= _draft.menuOrder.length) return;
    _hapticTap();
    setState(() {
      final list = List<SettingsItemId>.from(_draft.menuOrder);
      final item = list.removeAt(idx);
      list.insert(target, item);
      _draft = _draft.copyWith(menuOrder: list);
    });
  }

  void _toggleExpand(SettingsItemId id) {
    _hapticTap();
    setState(() {
      _expandedId = _expandedId == id ? null : id;
    });
  }

  void _confirmResetHistory() {
    _hapticTap();
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF14151D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _lang == LangCode.tr ? 'Geçmiş Verileri Sıfırla?' : 'Reset History Data?',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          _lang == LangCode.tr
              ? 'Hafızadaki tüm geçmiş tüketim, sıcaklık kayıtları ve fatura telemetrisi sıfırlanacak.'
              : 'All stored usage logs, hourly temperature records, and billing telemetry will be cleared.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(_lang == LangCode.tr ? 'Vazgeç' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.of(dCtx).pop();
              widget.onResetTelemetryHistory();
              setState(() {
                _draft = _draft.copyWith(espLogs: const []);
                _statusBanner = _lang == LangCode.tr
                    ? 'Tüm geçmiş tüketim ve telemetri kayıtları sıfırlandı.'
                    : 'All usage history and telemetry cleared.';
              });
            },
            child: Text(_lang == LangCode.tr ? 'Sıfırla' : 'Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.90),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 680 : 480),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E14).withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.75), blurRadius: 36, offset: const Offset(0, -10)),
            ],
          ),
          child: Column(
            children: [
              // Sticky Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.cloud_outlined, color: Color(0xFFFBBF24), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lang == LangCode.tr ? 'Ayarlar & Sistem Tercihleri' : 'Settings & System Preferences',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          Text(
                            _lang == LangCode.tr
                                ? 'Bulut bağlantısı, şifreli kasa ve veri yönetimi'
                                : 'Cloud sync, encrypted vault & device preferences',
                            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFFBBF24), size: 19),
                    ),
                  ],
                ),
              ),

              // Reorder & Edit Bar + Location / Language Quick Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.amber.shade400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lang == LangCode.tr
                                  ? 'Menüleri sürükle veya oklarla sırala'
                                  : 'Drag or use arrows to reorder',
                              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              _hapticTap();
                              setState(() {
                                _draft = _draft.copyWith(menuOrder: SystemSettingsState.defaultMenuOrder);
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: Text(_lang == LangCode.tr ? 'Sıfırla' : 'Reset', style: const TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            onPressed: () {
                              _hapticTap();
                              setState(() => _editOrderMode = !_editOrderMode);
                            },
                            icon: Icon(_editOrderMode ? Icons.check_rounded : Icons.edit_outlined, size: 13),
                            label: Text(
                              _editOrderMode
                                  ? (_lang == LangCode.tr ? 'Bitti' : 'Done')
                                  : (_lang == LangCode.tr ? 'Düzenle' : 'Edit'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFBBF24),
                              backgroundColor: _editOrderMode
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                                  : Colors.transparent,
                              side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_statusBanner != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                        ),
                        child: Text(_statusBanner!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFA7F3D0))),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Scrollable / Reorderable 11 Settings Cards + Device Profile Strip
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  buildDefaultDragHandles: false,
                  onReorderItem: _moveItem,
                  header: _buildLocationLanguageBar(),
                  itemCount: _draft.menuOrder.length,
                  itemBuilder: (context, idx) {
                    final id = _draft.menuOrder[idx];
                    return Padding(
                      key: ValueKey(id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildSettingCard(id, idx),
                    );
                  },
                ),
              ),

              // Sticky Bottom Action Bar
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B10),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: Text(_lang == LangCode.tr ? 'Kapat' : 'Close'),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        ),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFEA580C).withValues(alpha: 0.40), blurRadius: 16),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: () {
                          _hapticTap();
                          final updated = _draft.copyWith(
                            telegramToken: _tgTokenCtrl.text.trim(),
                            telegramChatId: _tgChatCtrl.text.trim(),
                            firebaseRtdbUrl: _firebaseUrlCtrl.text.trim(),
                            espDeviceId: _espIdCtrl.text.trim(),
                          );
                          widget.onChangeLang(_lang);
                          widget.onChangeLocation(_location);
                          widget.onSaveSettings(updated);
                          Navigator.of(context).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          _lang == LangCode.tr ? 'Ayarları Kaydet' : 'Save Settings',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                        ),
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

  Widget _buildLocationLanguageBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _lang == LangCode.tr ? 'Cihaz Konumu & Arayüz Dili' : 'Location & Language',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)),
              ),
              Row(
                children: [
                  for (final code in LangCode.values) ...[
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: Text(code.name.toUpperCase(), style: const TextStyle(fontSize: 11)),
                      selected: _lang == code,
                      visualDensity: VisualDensity.compact,
                      selectedColor: widget.accentColor.withValues(alpha: 0.35),
                      onSelected: (_) {
                        _hapticTap();
                        setState(() => _lang = code);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < _locations.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _location = _locations[i]);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _location == _locations[i]
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: _location == _locations[i]
                              ? Colors.white.withValues(alpha: 0.30)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        _locations[i],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(SettingsItemId id, int index) {
    final isExpanded = _expandedId == id;
    final meta = _describeItem(id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded
              ? meta.iconColor.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleExpand(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  if (_editOrderMode) ...[
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.drag_handle_rounded, color: Colors.white.withValues(alpha: 0.55), size: 20),
                      ),
                    ),
                  ],
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: meta.iconColor.withValues(alpha: 0.12),
                      border: Border.all(color: meta.iconColor.withValues(alpha: 0.30)),
                    ),
                    child: Icon(meta.icon, color: meta.iconColor, size: 19),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                meta.title,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              meta.tag,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: meta.iconColor.withValues(alpha: 0.90)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta.subtitle,
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_editOrderMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: index > 0 ? () => _shiftItem(index, -1) : null,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          onPressed: index < _draft.menuOrder.length - 1 ? () => _shiftItem(index, 1) : null,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    )
                  else ...[
                    meta.trailingAction,
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                      size: 19,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expandable Sub-Panel Body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 14, color: Colors.white.withValues(alpha: 0.08)),
                  _buildExpandedPanel(id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _CardMeta _describeItem(SettingsItemId id) {
    final tr = _lang == LangCode.tr;
    switch (id) {
      case SettingsItemId.vault:
        return _CardMeta(
          icon: Icons.lock_outline_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Şifreli Kasa & Bildirimler' : 'Encrypted Vault & Alerts',
          tag: 'AES-256',
          subtitle: tr ? 'PIN korumalı kasa kilidi ve Telegram bot bildirimleri' : 'PIN vault lock and Telegram bot alerts',
          trailingAction: _ActionPill(
            label: _draft.vaultUnlocked ? (tr ? 'Açık ✓' : 'Open ✓') : (tr ? 'Aç →' : 'Open →'),
            active: _draft.vaultUnlocked,
            color: const Color(0xFFF59E0B),
            onTap: () => _toggleExpand(id),
          ),
        );
      case SettingsItemId.googleHome:
        return _CardMeta(
          icon: Icons.home_outlined,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Google Home & Asistan' : 'Google Home & Assistant',
          tag: tr ? 'Google ile Uyumlu' : 'Works with Google',
          subtitle: tr ? 'Firebase üzerinden Google Asistan sesli kontrol' : 'Google Assistant voice sync via Firebase',
          trailingAction: _ActionPill(
            label: _draft.googleHomeLinked ? (tr ? 'Bağlı ✓' : 'Linked ✓') : (tr ? 'Yönet →' : 'Manage →'),
            active: _draft.googleHomeLinked,
            color: const Color(0xFF38BDF8),
            onTap: () => _toggleExpand(id),
          ),
        );
      case SettingsItemId.smartDisplay:
        return _CardMeta(
          icon: Icons.tv_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: 'Smart Display & Ambiyans',
          tag: 'Tablet / PC',
          subtitle: tr ? 'Masaüstü veya duvarda canlı saat ve ambiyans ekranı' : 'Wall-mount clock & ambient display',
          trailingAction: _ActionPill(
            label: _draft.smartDisplayEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.smartDisplayEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(smartDisplayEnabled: !_draft.smartDisplayEnabled));
            },
          ),
        );
      case SettingsItemId.notifications:
        return _CardMeta(
          icon: Icons.notifications_none_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Bildirim Ayarları & Otomasyon' : 'Notifications & Automation',
          tag: tr ? '3 Saatlik & Acil' : '3h & Critical',
          subtitle: tr ? '3 saatlik durum özeti ve kritik kombi emniyet uyarıları' : '3-hour summary and critical safety alerts',
          trailingAction: _ActionPill(
            label: _draft.notifications3hEnabled ? (tr ? 'Devrede' : 'Active') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.notifications3hEnabled,
            color: const Color(0xFFF59E0B),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(notifications3hEnabled: !_draft.notifications3hEnabled));
            },
          ),
        );
      case SettingsItemId.haptic:
        return _CardMeta(
          icon: Icons.vibration_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Haptik Titreşim & Dokunma' : 'Haptic Touch Feedback',
          tag: tr ? 'Titreşim' : 'Haptic',
          subtitle: tr ? 'Tüm butonlar, kadran ve Flow Bar için titreşim' : 'Tactile feedback on dial, buttons and Flow Bar',
          trailingAction: _ActionPill(
            label: _draft.hapticEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.hapticEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              setState(() => _draft = _draft.copyWith(hapticEnabled: !_draft.hapticEnabled));
              if (_draft.hapticEnabled) HapticFeedback.mediumImpact();
            },
          ),
        );
      case SettingsItemId.bootCeremony:
        return _CardMeta(
          icon: Icons.local_fire_department_outlined,
          iconColor: const Color(0xFFF97316),
          title: tr ? 'Açılış Seremonisi (Boot Efekti)' : 'Boot Ceremony Animation',
          tag: 'Boot',
          subtitle: tr ? 'Uygulama açılırken akıllı termostat kalibrasyonu' : 'Smart calibration animation on launch',
          trailingAction: _ActionPill(
            label: _draft.bootCeremonyEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.bootCeremonyEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(bootCeremonyEnabled: !_draft.bootCeremonyEnabled));
            },
          ),
        );
      case SettingsItemId.termoBot:
        return _CardMeta(
          icon: Icons.smart_toy_outlined,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Sanal Asistan & Ekran Koruyucu' : 'Virtual Assistant Screensaver',
          tag: 'TermoBot',
          subtitle: tr ? 'Boşta kalınca yürüyen ve 3 döngü sonra uyuyan maskot' : 'Idle mascot companion & sleep mode',
          trailingAction: _ActionPill(
            label: _draft.termoBotEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.termoBotEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(termoBotEnabled: !_draft.termoBotEnabled));
            },
          ),
        );
      case SettingsItemId.aiPhoneCall:
        return _CardMeta(
          icon: Icons.phone_in_talk_outlined,
          iconColor: const Color(0xFF10B981),
          title: tr ? 'AI Sesli Telefon Araması (Asistan)' : 'AI Voice Call Assistant',
          tag: '${_draft.aiCallRingSeconds} sn',
          subtitle: tr ? 'Kombi ateşlendiğinde arar, sesli bilgi verir' : 'Calls on boiler ignition, alerts if missed',
          trailingAction: _ActionPill(
            label: _draft.aiPhoneCallEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.aiPhoneCallEnabled,
            color: const Color(0xFF10B981),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(aiPhoneCallEnabled: !_draft.aiPhoneCallEnabled));
            },
          ),
        );
      case SettingsItemId.espLog:
        return _CardMeta(
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'ESP Donanım Günlüğü & Raporlama' : 'ESP Hardware & Offline Logs',
          tag: 'ESP32 / WDT',
          subtitle: tr ? 'Çevrimdışı yanma süreleri ve kilitlenme logları' : 'Offline burn cycles & watchdog logs',
          trailingAction: _ActionPill(
            label: _draft.espOnline ? (tr ? 'Çevrimiçi' : 'Online') : (tr ? 'Çevrimdışı' : 'Offline'),
            active: _draft.espOnline,
            color: _draft.espOnline ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            onTap: () => _toggleExpand(id),
          ),
        );
      case SettingsItemId.cloudSync:
        return _CardMeta(
          icon: Icons.sync_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Bulut Senkronizasyon & Veritabanı' : 'Cloud Sync & Database',
          tag: 'Firebase RTDB',
          subtitle: tr ? 'Firebase gerçek zamanlı veri senkronizasyonu' : 'Firebase realtime telemetry sync',
          trailingAction: _ActionPill(
            label: _draft.cloudSyncEnabled ? (tr ? 'Bağlı' : 'Synced') : (tr ? 'Çevrimdışı' : 'Offline'),
            active: _draft.cloudSyncEnabled,
            color: _draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(cloudSyncEnabled: !_draft.cloudSyncEnabled));
            },
          ),
        );
      case SettingsItemId.resetHistory:
        return _CardMeta(
          icon: Icons.delete_sweep_outlined,
          iconColor: const Color(0xFFF87171),
          title: tr ? 'Geçmiş Verileri & Kayıtları Sıfırla' : 'Reset History & Usage Logs',
          tag: tr ? 'Sıfırlama' : 'Reset',
          subtitle: tr ? 'Sıcaklık saatlik kayıtları ve fatura telemetrisi' : 'Hourly heat records and billing telemetry',
          trailingAction: _ActionPill(
            label: tr ? 'Sıfırla' : 'Reset',
            active: false,
            color: const Color(0xFFEF4444),
            onTap: _confirmResetHistory,
          ),
        );
    }
  }

  Widget _buildExpandedPanel(SettingsItemId id) {
    final tr = _lang == LangCode.tr;
    switch (id) {
      case SettingsItemId.vault:
        if (!_draft.vaultUnlocked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr ? 'Kasa PIN kodunu girin (Varsayılan: 1234)' : 'Enter vault PIN (Default: 1234)',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.70)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DarkTextField(
                      controller: _pinInputCtrl,
                      hint: 'PIN',
                      obscure: true,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      _hapticTap();
                      if (_pinInputCtrl.text.trim() == _draft.vaultPin) {
                        setState(() {
                          _draft = _draft.copyWith(vaultUnlocked: true);
                          _statusBanner = tr ? 'Şifreli kasa açıldı.' : 'Vault unlocked.';
                        });
                      } else {
                        setState(() => _statusBanner = tr ? 'Hatalı PIN kodu.' : 'Incorrect PIN.');
                      }
                    },
                    child: Text(tr ? 'Kilidi Aç' : 'Unlock'),
                  ),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkTextField(controller: _tgTokenCtrl, hint: 'Telegram Bot Token'),
            const SizedBox(height: 8),
            _DarkTextField(controller: _tgChatCtrl, hint: 'Telegram Chat ID'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => setState(() => _draft = _draft.copyWith(vaultUnlocked: false)),
                  child: Text(tr ? 'Kasayı Kilitle' : 'Lock Vault'),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    _hapticTap();
                    setState(() {
                      _statusBanner = _tgTokenCtrl.text.trim().isEmpty
                          ? (tr ? 'Önce Bot Token girin.' : 'Enter Bot Token first.')
                          : (tr ? 'Telegram test bildirimi kuyruğa alındı.' : 'Telegram test alert queued.');
                    });
                  },
                  child: Text(tr ? 'Test Bildirimi' : 'Test Alert'),
                ),
              ],
            ),
          ],
        );

      case SettingsItemId.googleHome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.googleHomeLinked,
              title: Text(
                tr ? 'Google Home Sesli Köprü' : 'Google Home Voice Bridge',
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
              subtitle: Text(
                '${tr ? 'Oda' : 'Room'}: ${_draft.googleHomeRoom}',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
              ),
              onChanged: (v) {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(googleHomeLinked: v));
              },
            ),
          ],
        );

      case SettingsItemId.smartDisplay:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                tr ? 'Saat ve sıcaklık tam ekran ambiyansını aç' : 'Launch fullscreen ambient clock & temperature',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.70)),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenAmbient();
              },
              child: Text(tr ? 'Şimdi Aç' : 'Open Now'),
            ),
          ],
        );

      case SettingsItemId.notifications:
        return Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.notifications3hEnabled,
              title: Text(tr ? '3 Saatlik Tüketim Özeti' : '3-Hour Usage Summary', style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              onChanged: (v) {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(notifications3hEnabled: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.emergencyBoilerAlerts,
              title: Text(tr ? 'Kritik Basınç & Aşırı Isınma Uyarısı' : 'Critical Pressure & Overheat Alert', style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              onChanged: (v) {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(emergencyBoilerAlerts: v));
              },
            ),
          ],
        );

      case SettingsItemId.haptic:
      case SettingsItemId.bootCeremony:
      case SettingsItemId.termoBot:
        return Text(
          tr
              ? 'Üstteki hızlı anahtar ile özelliği dilediğiniz zaman açıp kapatabilir, Ayarları Kaydet ile cihaza yazabilirsiniz.'
              : 'Use the toggle above and tap Save Settings to store this preference on device.',
          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
        );

      case SettingsItemId.aiPhoneCall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr ? 'Çalma Süresi' : 'Ring Duration', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Text('${_draft.aiCallRingSeconds} sn', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
              ],
            ),
            Slider(
              value: _draft.aiCallRingSeconds.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => setState(() => _draft = _draft.copyWith(aiCallRingSeconds: v.round())),
            ),
          ],
        );

      case SettingsItemId.espLog:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkTextField(controller: _espIdCtrl, hint: 'ESP32 Cihaz Kimliği'),
            const SizedBox(height: 8),
            if (_draft.espLogs.isEmpty)
              Text(tr ? 'Kayıtlı donanım günlüğü yok.' : 'No hardware logs stored.', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.50)))
            else
              for (final log in _draft.espLogs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(log.timestamp, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${log.event} · ${log.detail}',
                          style: TextStyle(fontSize: 11, color: log.isWarning ? Colors.amber.shade300 : Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );

      case SettingsItemId.cloudSync:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkTextField(controller: _firebaseUrlCtrl, hint: 'Firebase RTDB URL'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.cloudSyncEnabled,
              title: Text(tr ? 'Gerçek Zamanlı Bulut Senkronizasyonu' : 'Realtime Cloud Sync', style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              onChanged: (v) {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(cloudSyncEnabled: v));
              },
            ),
          ],
        );

      case SettingsItemId.resetHistory:
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.25), foregroundColor: const Color(0xFFFCA5A5)),
          onPressed: _confirmResetHistory,
          icon: const Icon(Icons.delete_forever_outlined, size: 17),
          label: Text(tr ? 'Tüm Tüketim & Telemetriyi Sıfırla' : 'Clear All Usage & Telemetry'),
        );
    }
  }
}

class _CardMeta {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String tag;
  final String subtitle;
  final Widget trailingAction;

  const _CardMeta({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.tag,
    required this.subtitle,
    required this.trailingAction,
  });
}

class _ActionPill extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: active
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.72)])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: active ? color : Colors.white.withValues(alpha: 0.14)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.40)),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
    );
  }
}
