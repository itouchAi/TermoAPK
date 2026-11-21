import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/thermostat_state.dart';
import '../services/vault_crypto_service.dart';

Future<void> showVaultCenterSheet({
  required BuildContext context,
  required LangCode lang,
  required String locationName,
  required SystemSettingsState initialSettings,
  required ValueChanged<SystemSettingsState> onUpdateSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VaultCenterModal(
      lang: lang,
      locationName: locationName,
      initialSettings: initialSettings,
      onUpdateSettings: onUpdateSettings,
    ),
  );
}

class _VaultCenterModal extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final SystemSettingsState initialSettings;
  final ValueChanged<SystemSettingsState> onUpdateSettings;

  const _VaultCenterModal({
    required this.lang,
    required this.locationName,
    required this.initialSettings,
    required this.onUpdateSettings,
  });

  @override
  State<_VaultCenterModal> createState() => _VaultCenterModalState();
}

class _VaultCenterModalState extends State<_VaultCenterModal> {
  late SystemSettingsState _settings;
  int _activeTab = 0; // 0: Şifreli Güvenlik Kasası, 1: Telegram Bildirimleri
  bool _obscureToken = true;
  bool _sendingTelegram = false;
  String? _statusMsg;
  bool _statusIsError = false;
  String? _exportedBackupJson;

  final _pinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _tgTokenCtrl = TextEditingController();
  final _tgChatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _tgTokenCtrl.text = _settings.telegramToken;
    _tgChatCtrl.text = _settings.telegramChatId;
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _newPinCtrl.dispose();
    _tgTokenCtrl.dispose();
    _tgChatCtrl.dispose();
    super.dispose();
  }

  void _haptic() {
    if (_settings.hapticEnabled) HapticFeedback.selectionClick();
  }

  void _commit(SystemSettingsState next, {String? msg, bool isError = false}) {
    setState(() {
      _settings = next;
      _statusMsg = msg;
      _statusIsError = isError;
    });
    widget.onUpdateSettings(next);
  }

  void _unlockVault() {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    final entered = _pinCtrl.text.trim();
    if (entered == _settings.vaultPin) {
      _pinCtrl.clear();
      _commit(
        _settings.copyWith(vaultUnlocked: true),
        msg: tr ? 'Şifreli kasa PIN ile açıldı.' : 'Encrypted vault unlocked.',
      );
    } else {
      setState(() {
        _statusMsg = tr ? 'Hatalı PIN kodu. (Varsayılan: 1234)' : 'Incorrect PIN. (Default: 1234)';
        _statusIsError = true;
      });
    }
  }

  void _createPinAndLock() {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    final pin = _newPinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 8) {
      setState(() {
        _statusMsg = tr ? 'PIN en az 4, en fazla 8 karakter olmalıdır.' : 'PIN must be 4–8 characters.';
        _statusIsError = true;
      });
      return;
    }
    _newPinCtrl.clear();
    _commit(
      _settings.copyWith(vaultPin: pin, vaultUnlocked: false),
      msg: tr ? 'Yeni PIN tanımlandı ve kasa kilitlendi.' : 'New PIN set and vault locked.',
    );
  }

  Future<void> _exportBackup() async {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    final backup = await VaultCryptoService.encryptBackupJson(
      settings: _settings,
      locationName: widget.locationName,
      pin: _settings.vaultPin,
    );
    await Clipboard.setData(ClipboardData(text: backup));

    String? savedPath;
    try {
      savedPath = await FilePicker.platform.saveFile(
        dialogTitle: tr ? 'Şifreli Kasa Yedeğini Kaydet' : 'Save Encrypted Vault Backup',
        fileName: 'termostat-vault-backup.json',
        bytes: Uint8List.fromList(utf8.encode(backup)),
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _exportedBackupJson = backup;
      _statusMsg = savedPath != null
          ? (tr
              ? 'AES-256-GCM şifreli yedek cihaza kaydedildi ve panoya kopyalandı.'
              : 'AES-256-GCM encrypted backup saved to device and copied.')
          : (tr
              ? 'AES-256-GCM şifreli .json yedek oluşturuldu ve panoya kopyalandı.'
              : 'AES-256-GCM encrypted .json backup generated and copied to clipboard.');
      _statusIsError = false;
    });
  }

  Future<void> _importBackup() async {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      if (picked.bytes == null) return;
      final rawJson = utf8.decode(picked.bytes!);

      final pinToTry = _pinCtrl.text.trim().isNotEmpty ? _pinCtrl.text.trim() : _settings.vaultPin;
      final restored = await VaultCryptoService.decryptBackupJson(
        rawJson: rawJson,
        pin: pinToTry,
      );
      if (!mounted) return;
      _tgTokenCtrl.text = restored.settings.telegramToken;
      _tgChatCtrl.text = restored.settings.telegramChatId;
      _commit(
        restored.settings.copyWith(vaultUnlocked: true),
        msg: tr
            ? 'Şifreli yedek başarıyla çözüldü ve tüm ayarlar geri yüklendi.'
            : 'Encrypted backup decrypted and restored successfully.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMsg = tr
            ? 'Yedek çözülemedi. Yedek şifrelenirken kullanılan PIN kodunu girin ve dosya formatını kontrol edin.'
            : 'Could not decrypt backup. Check PIN code and JSON format.';
        _statusIsError = true;
      });
    }
  }

  void _confirmResetVault() {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF14151D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr ? 'Kasayı Sıfırla?' : 'Reset Encrypted Vault?',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          tr
              ? 'Özel PIN sıfırlanacak (1234), kayıtlı Telegram anahtarları temizlenecek ve kasa kilitlenecektir.'
              : 'Custom PIN will reset to 1234, stored Telegram credentials will be wiped, and the vault will lock.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(tr ? 'Vazgeç' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.of(dCtx).pop();
              _tgTokenCtrl.clear();
              _tgChatCtrl.clear();
              _pinCtrl.clear();
              _newPinCtrl.clear();
              setState(() => _exportedBackupJson = null);
              _commit(
                _settings.copyWith(
                  vaultPin: '1234',
                  vaultUnlocked: false,
                  telegramToken: '',
                  telegramChatId: '',
                ),
                msg: tr ? 'Şifreli kasa fabrika ayarlarına sıfırlandı.' : 'Encrypted vault reset to defaults.',
              );
            },
            child: Text(tr ? 'Sıfırla' : 'Reset'),
          ),
        ],
      ),
    );
  }

  void _saveTelegramEncrypted() {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    final token = _tgTokenCtrl.text.trim();
    final chatId = _tgChatCtrl.text.trim();
    _commit(
      _settings.copyWith(telegramToken: token, telegramChatId: chatId),
      msg: tr
          ? 'Telegram Bot anahtarları AES-256 kasasına kaydedildi.'
          : 'Telegram Bot credentials saved encrypted.',
    );
  }

  Future<void> _sendTelegramTest() async {
    _haptic();
    final tr = widget.lang == LangCode.tr;
    final token = _tgTokenCtrl.text.trim();
    final chatId = _tgChatCtrl.text.trim();
    if (token.isEmpty || chatId.isEmpty) {
      setState(() {
        _statusMsg = tr
            ? 'Test göndermek için önce Bot Token ve Chat ID girin.'
            : 'Please enter both Bot Token and Chat ID first.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _sendingTelegram = true;
      _statusMsg = null;
    });

    try {
      final uri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final resp = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': chatId,
              'text': tr
                  ? '🔥 Termostat Flow Test Bildirimi (${widget.locationName}): Şifreli kasa ve Telegram köprüsü aktif!'
                  : '🔥 Termostat Flow Test Alert (${widget.locationName}): Encrypted vault & Telegram bridge active!',
            }),
          )
          .timeout(const Duration(seconds: 6));
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      if (!mounted) return;
      _commit(
        _settings.copyWith(telegramToken: token, telegramChatId: chatId),
        msg: ok
            ? (tr ? 'Telegram test bildirimi başarıyla gönderildi!' : 'Telegram test alert sent successfully!')
            : (tr
                ? 'Telegram API yanıtı: HTTP ${resp.statusCode}. Token veya Chat ID kontrol edin.'
                : 'Telegram API responded HTTP ${resp.statusCode}. Check token/Chat ID.'),
        isError: !ok,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMsg = tr
            ? 'Bağlantı kurulamadı. Bilgiler kaydedildi; internet bağlantısı olduğunda tekrar deneyin.'
            : 'Network unavailable. Credentials saved; try again when online.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _sendingTelegram = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final tr = widget.lang == LangCode.tr;

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.88),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 640 : 480),
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
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.38)),
                      ),
                      child: const Icon(Icons.enhanced_encryption_outlined, color: Color(0xFFFBBF24), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr ? 'Şifreli Kasa & Bildirim Yönetimi' : 'Encrypted Vault & Notifications',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          Text(
                            tr
                                ? 'AES-256 yerel şifreleme, PIN güvenliği ve Telegram bot bildirimleri'
                                : 'AES-256 local encryption, PIN lock & Telegram alerts',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.58)),
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

              // 2-Tab Selector Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.045),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentTabButton(
                          icon: Icons.lock_outline_rounded,
                          label: tr ? 'Şifreli Güvenlik Kasası' : 'Encrypted Vault',
                          active: _activeTab == 0,
                          accentColor: const Color(0xFFF59E0B),
                          onTap: () {
                            _haptic();
                            setState(() => _activeTab = 0);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _SegmentTabButton(
                          icon: Icons.send_outlined,
                          label: tr ? 'Telegram Bildirimleri' : 'Telegram Alerts',
                          active: _activeTab == 1,
                          accentColor: const Color(0xFF38BDF8),
                          onTap: () {
                            _haptic();
                            setState(() => _activeTab = 1);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_statusMsg != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (_statusIsError ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_statusIsError ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                            .withValues(alpha: 0.42),
                      ),
                    ),
                    child: Text(
                      _statusMsg!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _statusIsError ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 10),

              // Active Tab Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                  child: _activeTab == 0 ? _buildSecurityVaultTab(tr) : _buildTelegramTab(tr),
                ),
              ),

              // Sticky Footer
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B10),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF10B981)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tr ? 'Tüm şifreler cihazda AES-GCM ile korunur.' : 'Keys encrypted locally with AES-GCM.',
                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      child: Text(tr ? 'Tamam & Kapat' : 'Done & Close', style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _buildSecurityVaultTab(bool tr) {
    final unlocked = _settings.vaultUnlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zero-Knowledge Info Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      tr ? 'YEREL ŞİFRELEME KASASI & GÜVENLİK' : 'LOCAL ENCRYPTED VAULT',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF34D399)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AES-GCM 256-bit Aktif',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tr ? 'Sıfır Bilgi (Zero-Knowledge) Yerel Güvenlik' : 'Zero-Knowledge Local Security',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                tr
                    ? 'Tüm hedef sıcaklıklar, haftalık zamanlama takvimleri, Telegram bot anahtarları ve telemetri geçmişi cihazınızda PBKDF2 + AES-256 ile şifrelenir. Sunucuya açık metin asla gönderilmez.'
                    : 'Target temperatures, schedules, Telegram keys, and telemetry history are encrypted on-device with PBKDF2 + AES-256.',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // PIN Lock / Create PIN Section
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unlocked
                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    unlocked
                        ? (tr ? 'Yeni PIN Oluştur & Kilitle' : 'Set New PIN & Lock')
                        : (tr ? 'Kasa Kilitli · PIN ile Aç' : 'Vault Locked · Unlock with PIN'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (unlocked ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      unlocked ? (tr ? 'Kasa Açık' : 'Unlocked') : (tr ? 'Kilitli' : 'Locked'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: unlocked ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!unlocked) ...[
                Text(
                  tr ? 'Mevcut PIN kodunu girerek kasayı açın (Varsayılan: 1234)' : 'Enter current PIN (Default: 1234)',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _VaultTextField(
                        controller: _pinCtrl,
                        hint: 'PIN (1234)',
                        obscure: true,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _unlockVault,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                      icon: const Icon(Icons.lock_open_rounded, size: 16),
                      label: Text(tr ? 'Kilidi Aç' : 'Unlock'),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  tr ? '4–8 haneli yeni kasa PIN kodu belirleyip kilitleyin:' : 'Set a 4–8 digit PIN and lock vault:',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _VaultTextField(
                        controller: _newPinCtrl,
                        hint: tr ? 'Yeni PIN (ör. 4820)' : 'New PIN',
                        obscure: true,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _createPinAndLock,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                      icon: const Icon(Icons.lock_outline_rounded, size: 16),
                      label: Text(tr ? 'PIN Oluştur & Kilitle' : 'Set & Lock'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Encrypted Backup Export, Restore & Reset Vault Actions
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _exportBackup,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  foregroundColor: const Color(0xFF7DD3FC),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.download_outlined, size: 17),
                label: Text(
                  tr ? 'Yedeği İndir (.json)' : 'Export (.json)',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _importBackup,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.16),
                  foregroundColor: const Color(0xFF6EE7B7),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: Text(
                  tr ? 'Yedek Yükle' : 'Restore',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _confirmResetVault,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFCA5A5),
            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.restart_alt_rounded, size: 17),
          label: Text(
            tr ? 'Kasayı Sıfırla' : 'Reset Vault',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),

        if (_exportedBackupJson != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr ? 'Şifreli Yedek Paketi (Panoya Kopyalandı):' : 'Encrypted JSON Envelope (Copied):',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                ),
                const SizedBox(height: 4),
                Text(
                  _exportedBackupJson!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTelegramTab(bool tr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  tr ? 'TELEGRAM BOT ENTEGRASYONU & ANLIK BİLDİRİMLER' : 'TELEGRAM BOT INTEGRATION & ALERTS',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF7DD3FC)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr ? 'Tokenler Şifreli' : 'Encrypted Keys',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Text(
          tr ? 'Telegram Bot Token (@BotFather\'dan alınan API Token):' : 'Telegram Bot Token (@BotFather):',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.80)),
        ),
        const SizedBox(height: 6),
        _VaultTextField(
          controller: _tgTokenCtrl,
          hint: '1234567890:ABCdefGhIJKlmNoPQRstuVWxYZ...',
          obscure: _obscureToken,
          suffix: IconButton(
            onPressed: () => setState(() => _obscureToken = !_obscureToken),
            icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 12),

        Text(
          tr ? 'Chat ID (@userinfobot\'tan alınan kullanıcı kimliği):' : 'Chat ID (@userinfobot):',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.80)),
        ),
        const SizedBox(height: 6),
        _VaultTextField(
          controller: _tgChatCtrl,
          hint: '987654321',
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _saveTelegramEncrypted,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.enhanced_encryption_outlined, size: 17),
                label: Text(
                  tr ? 'Şifreli Olarak Kaydet' : 'Save Encrypted',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sendingTelegram ? null : _sendTelegramTest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.48)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _sendingTelegram
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.notifications_active_outlined, size: 17),
                label: Text(
                  tr ? 'Test Bildirimi Gönder' : 'Send Test Alert',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SegmentTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  const _SegmentTabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active ? accentColor.withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? accentColor.withValues(alpha: 0.55) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? accentColor : Colors.white54),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.white60,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const _VaultTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
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
        hintStyle: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.38)),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
    );
  }
}
