part of '../settings_sheet.dart';

extension _CloudEspSettingsBuilders on _SystemSettingsModalState {
  Widget _buildEspLogPanel(bool tr) {
    final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
    final filteredEspLogs = EspLogService.filterLogs(
      _draft.espLogs,
      category: _espLogFilter,
    );
    final warningEvents = EspLogService.countWatchdogEvents(_draft.espLogs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SettingsInfoBadge(
              text: _draft.espOnline
                  ? (tr
                      ? 'Çevrimiçi${_draft.espLastPingAt.isNotEmpty ? ' · ${_draft.espLastPingAt}' : ''}'
                      : 'Online${_draft.espLastPingAt.isNotEmpty ? ' · ${_draft.espLastPingAt}' : ''}')
                  : (tr ? 'Çevrimdışı' : 'Offline'),
              color: _draft.espOnline ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            ),
            SettingsInfoBadge(
              text: tr
                  ? 'WDT: ${_draft.espWdtResetCount} (${warningEvents} uyarı)'
                  : 'WDT: ${_draft.espWdtResetCount} (${warningEvents} alerts)',
              color: const Color(0xFFFBBF24),
            ),
            SettingsInfoBadge(
              text: tr
                  ? 'Yanma: ${_draft.espOfflineBurnMinutes} dk'
                  : 'Burn: ${_draft.espOfflineBurnMinutes} min',
              color: const Color(0xFFF97316),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SettingsDarkTextField(
                controller: _espIdCtrl,
                hint: tr ? 'ESP32 Cihaz Kimliği (ör. ESP32-KOMBI-01)' : 'ESP32 Device ID',
              ),
            ),
            const SizedBox(width: 8),
            TactilePress(
              enabled: !_espPingBusy,
              child: FilledButton.icon(
                onPressed: _espPingBusy ? null : _runEspConnectionTest,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24).withValues(alpha: 0.22),
                  foregroundColor: const Color(0xFFFDE68A),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: const Color(0xFFFBBF24).withValues(alpha: 0.45)),
                  ),
                ),
                icon: _espPingBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFDE68A)),
                      )
                    : const Icon(Icons.wifi_tethering_rounded, size: 16),
                label: Text(
                  tr ? 'Ping' : 'Ping',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (_espPingStatus != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: (_espPingOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_espPingOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _espPingStatus!,
              style: TextStyle(
                fontSize: 11,
                color: _espPingOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'WDT Kilitlenme İzleme' : 'WDT Lockup Watchdog',
                value: _draft.espWdtEnabled,
                activeColor: const Color(0xFFFBBF24),
                onTap: () {
                  _hapticTap();
                  final next = _draft.copyWith(espWdtEnabled: !_draft.espWdtEnabled);
                  _updateState(() => _draft = next);
                  widget.onSaveSettings(next);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'NVS Çevrimdışı Tampon' : 'NVS Offline Buffer',
                value: _draft.espOfflineBufferEnabled,
                activeColor: const Color(0xFF10B981),
                onTap: () {
                  _hapticTap();
                  final next = _draft.copyWith(
                    espOfflineBufferEnabled: !_draft.espOfflineBufferEnabled,
                  );
                  _updateState(() => _draft = next);
                  widget.onSaveSettings(next);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TactilePress(
              child: ActionChip(
                avatar: const Icon(Icons.add_chart_rounded, size: 14, color: Color(0xFF38BDF8)),
                label: Text(
                  tr ? 'Anlık Kayıt Al' : 'Log Snapshot',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                onPressed: () {
                  _hapticTap();
                  final nowLabel = NotificationService.formatNowTime();
                  final devId = _espIdCtrl.text.trim().isEmpty
                      ? _draft.espDeviceId
                      : _espIdCtrl.text.trim();
                  final pressurePart = (widget.sensors.isConnected && widget.sensors.waterPressureBar != null)
                      ? ' · ${widget.sensors.waterPressureBar!.toStringAsFixed(1)} Bar'
                      : '';
                  final entry = EspLogEntry(
                    timestamp: nowLabel,
                    event: liveBoiler.isHeating
                        ? (tr ? 'Modülasyon %${liveBoiler.flamePercent}' : 'Modulation %${liveBoiler.flamePercent}')
                        : (tr ? 'Bekleme Telemetrisi' : 'Standby Telemetry'),
                    detail:
                        '$devId · ${widget.roomTemp.toStringAsFixed(1)}°C → ${_liveTargetTemp.toStringAsFixed(1)}°C$pressurePart',
                    category: liveBoiler.isHeating ? EspLogCategory.burner : EspLogCategory.system,
                  );
                  final next = _draft.copyWith(
                    espDeviceId: devId,
                    espLogs: EspLogService.appendLog(_draft.espLogs, entry),
                  );
                  _updateState(() {
                    _draft = next;
                    _espPingOk = true;
                    _espPingStatus = tr
                        ? 'Anlık telemetri kaydı NVS günlüğüne eklendi ($nowLabel).'
                        : 'Live telemetry snapshot appended ($nowLabel).';
                  });
                  widget.onSaveSettings(next);
                },
              ),
            ),
            TactilePress(
              child: ActionChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFBBF24)),
                label: Text(
                  tr ? 'WDT Testi' : 'WDT Test',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                onPressed: () {
                  _hapticTap();
                  final nowLabel = NotificationService.formatNowTime();
                  final devId = _espIdCtrl.text.trim().isEmpty
                      ? _draft.espDeviceId
                      : _espIdCtrl.text.trim();
                  final entry = EspLogEntry(
                    timestamp: nowLabel,
                    event: tr ? 'WDT Tetikleme Testi' : 'WDT Reset Self-Test',
                    detail: tr
                        ? '$devId · Çekirdek güvenli kurtarma doğrulandı'
                        : '$devId · Core recovery verified',
                    isWarning: true,
                    category: EspLogCategory.watchdog,
                  );
                  final next = _draft.copyWith(
                    espDeviceId: devId,
                    espWdtResetCount: _draft.espWdtResetCount + 1,
                    espLogs: EspLogService.appendLog(_draft.espLogs, entry),
                  );
                  _updateState(() {
                    _draft = next;
                    _espPingOk = true;
                    _espPingStatus = tr
                        ? 'WDT kurtarma testi kaydedildi (#${next.espWdtResetCount}).'
                        : 'WDT recovery test logged (#${next.espWdtResetCount}).';
                  });
                  widget.onSaveSettings(next);
                },
              ),
            ),
            TactilePress(
              child: ActionChip(
                avatar: const Icon(Icons.copy_all_rounded, size: 14, color: Color(0xFF10B981)),
                label: Text(
                  tr ? 'Raporu Kopyala' : 'Copy Report',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                onPressed: () async {
                  _hapticTap();
                  final report = EspLogService.exportLogsReport(
                    settings: _draft.copyWith(
                      espDeviceId: _espIdCtrl.text.trim().isEmpty
                          ? _draft.espDeviceId
                          : _espIdCtrl.text.trim(),
                    ),
                    roomTemp: widget.roomTemp,
                    targetTemp: _liveTargetTemp,
                    boiler: liveBoiler,
                    sensors: widget.sensors,
                    lang: _lang,
                  );
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!mounted) return;
                  _updateState(() {
                    _espPingOk = true;
                    _espPingStatus = tr
                        ? 'ESP32 donanım raporu panoya kopyalandı (${_draft.espLogs.length} kayıt).'
                        : 'ESP32 hardware report copied (${_draft.espLogs.length} logs).';
                  });
                },
              ),
            ),
            if (_draft.espLogs.isNotEmpty)
              TactilePress(
                child: ActionChip(
                  avatar: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFF87171)),
                  label: Text(
                    tr ? 'Temizle' : 'Clear',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                  onPressed: () {
                    _hapticTap();
                    final next = _draft.copyWith(
                      espLogs: const [],
                      espOfflineBurnMinutes: 0,
                      espWdtResetCount: 0,
                    );
                    _updateState(() {
                      _draft = next;
                      _espPingOk = true;
                      _espPingStatus = tr
                          ? 'ESP32 donanım günlüğü ve sayaçlar temizlendi.'
                          : 'ESP32 hardware logs and counters cleared.';
                    });
                    widget.onSaveSettings(next);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filterOpt in <(EspLogCategory?, String)>[
                (null, tr ? 'Tümü (${_draft.espLogs.length})' : 'All (${_draft.espLogs.length})'),
                (EspLogCategory.burner, tr ? 'Yanma' : 'Burner'),
                (EspLogCategory.watchdog, tr ? 'WDT / Uyarı' : 'WDT / Alert'),
                (EspLogCategory.sync, tr ? 'Bulut' : 'Cloud'),
              ]) ...[
                TactilePress(
                  child: ChoiceChip(
                    label: Text(filterOpt.$2, style: const TextStyle(fontSize: 10.5)),
                    selected: _espLogFilter == filterOpt.$1,
                    selectedColor: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    labelStyle: TextStyle(
                      color: _espLogFilter == filterOpt.$1 ? const Color(0xFFFDE68A) : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _espLogFilter == filterOpt.$1
                          ? const Color(0xFFFBBF24).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                    onSelected: (_) {
                      _hapticTap();
                      _updateState(() => _espLogFilter = filterOpt.$1);
                    },
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (filteredEspLogs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              tr ? 'Bu filtrede kayıtlı ESP32 donanım günlüğü yok.' : 'No ESP32 hardware logs match this filter.',
              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
            ),
          )
        else
          for (final log in filteredEspLogs) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: log.isWarning
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: log.isWarning
                      ? const Color(0xFFFBBF24).withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.09),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      log.category == EspLogCategory.burner
                          ? Icons.local_fire_department_rounded
                          : log.category == EspLogCategory.watchdog
                              ? Icons.warning_amber_rounded
                              : log.category == EspLogCategory.sync
                                  ? Icons.cloud_done_outlined
                                  : Icons.memory_rounded,
                      size: 15,
                      color: log.isWarning
                          ? const Color(0xFFFBBF24)
                          : log.category == EspLogCategory.burner
                              ? const Color(0xFFFB923C)
                              : log.category == EspLogCategory.sync
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                log.event,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: log.isWarning ? Colors.amber.shade200 : Colors.white,
                                ),
                              ),
                            ),
                            if (log.durationSeconds > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF97316).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  EspLogService.formatDurationBadge(log.durationSeconds, _lang),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFDBA74),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              log.timestamp,
                              style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.detail,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildCloudSyncPanel(bool tr) {
    final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
    final activeNode = FirebaseSyncService.sanitizeNodePath(
      _firebaseNodeCtrl.text.trim().isEmpty ? _draft.firebaseNodePath : _firebaseNodeCtrl.text.trim(),
    );
    final urlValid = FirebaseSyncService.validateRtdbUrl(
      _firebaseUrlCtrl.text.trim().isEmpty ? _draft.firebaseRtdbUrl : _firebaseUrlCtrl.text.trim(),
    );
    final statusText = _cloudSyncStatus ??
        (_draft.cloudLastSyncMessage.isNotEmpty ? _draft.cloudLastSyncMessage : null);
    final statusIsOk = _cloudSyncStatus != null ? _cloudSyncOk : _draft.cloudLastSyncOk;
    final payloadPreview = FirebaseSyncService.buildPayloadPreviewJson(
      roomName: _draft.googleHomeRoom,
      espDeviceId: _espIdCtrl.text.trim().isEmpty ? _draft.espDeviceId : _espIdCtrl.text.trim(),
      targetTemp: _liveTargetTemp,
      boiler: liveBoiler,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  tr ? 'Bulut Senkronizasyon Durumu:' : 'Cloud Sync Status:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (_draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  _draft.cloudSyncEnabled
                      ? (tr ? '• Bağlı (Bulut Aktif)' : '• Connected (Cloud)')
                      : (tr ? '• Çevrimdışı (Yerel Mod)' : '• Offline (Local Mode)'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _draft.cloudSyncEnabled ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.storage_rounded, size: 15, color: Color(0xFF38BDF8)),
            const SizedBox(width: 6),
            Text(
              'Firebase Database URL:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.90)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsDarkTextField(
          controller: _firebaseUrlCtrl,
          hint: 'https://kombi-kontrol-babd5-default-rtdb.firebaseio.com',
          keyboardType: TextInputType.url,
          textColor: const Color(0xFFFCD34D),
          monospace: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.vpn_key_outlined, size: 15, color: Color(0xFFFBBF24)),
            const SizedBox(width: 6),
            Text(
              'Firebase Web API Key:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.90)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsDarkTextField(
          controller: _firebaseApiKeyCtrl,
          hint: tr ? 'Firebase Web API Key veya RTDB Gizli Anahtarı girin' : 'Enter Firebase Web API Key',
          obscure: true,
          textColor: const Color(0xFFFCD34D),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SettingsDarkTextField(
                controller: _firebaseNodeCtrl,
                hint: tr ? 'RTDB Düğüm Yolu (kombi)' : 'RTDB Node Path (kombi)',
              ),
            ),
            const SizedBox(width: 8),
            SettingsInfoBadge(
              text: '/$activeNode.json',
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(width: 6),
            SettingsInfoBadge(
              text: urlValid
                  ? (tr ? 'URL Geçerli' : 'Valid')
                  : (tr ? 'URL Geçersiz' : 'Invalid'),
              color: urlValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'Gerçek Zamanlı Sync' : 'Realtime Sync',
                value: _draft.cloudSyncEnabled,
                activeColor: const Color(0xFF38BDF8),
                onTap: () {
                  _hapticTap();
                  final next = _draft.copyWith(cloudSyncEnabled: !_draft.cloudSyncEnabled);
                  _updateState(() => _draft = next);
                  widget.onSaveSettings(next);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'Uzaktan Hedefi Çek' : 'Auto-Pull Target',
                value: _draft.cloudAutoPullEnabled,
                activeColor: const Color(0xFF10B981),
                onTap: () {
                  _hapticTap();
                  final next = _draft.copyWith(
                    cloudAutoPullEnabled: !_draft.cloudAutoPullEnabled,
                  );
                  _updateState(() => _draft = next);
                  widget.onSaveSettings(next);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          tr ? 'Otomatik Senkronizasyon Periyodu' : 'Auto Sync Interval',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in <(int, String)>[
                (0, tr ? 'Manuel' : 'Manual'),
                (15, tr ? '15 sn' : '15s'),
                (30, tr ? '30 sn' : '30s'),
                (60, tr ? '60 sn' : '60s'),
                (180, tr ? '3 dk' : '3m'),
              ]) ...[
                TactilePress(
                  child: ChoiceChip(
                    label: Text(opt.$2, style: const TextStyle(fontSize: 10.5)),
                    selected: _draft.cloudSyncIntervalSeconds == opt.$1,
                    selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    labelStyle: TextStyle(
                      color: _draft.cloudSyncIntervalSeconds == opt.$1 ? const Color(0xFFBAE6FD) : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _draft.cloudSyncIntervalSeconds == opt.$1
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                    onSelected: (_) {
                      _hapticTap();
                      final next = _draft.copyWith(cloudSyncIntervalSeconds: opt.$1);
                      _updateState(() => _draft = next);
                      widget.onSaveSettings(next);
                    },
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TactilePress(
                enabled: !_cloudSyncBusy,
                child: OutlinedButton.icon(
                  onPressed: _cloudSyncBusy ? null : () => _runCloudPush(pullInstead: false),
                  icon: _cloudSyncBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6EE7B7)),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text(
                    tr ? 'Buluta Gönder' : 'Push to RTDB',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6EE7B7),
                    side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TactilePress(
                enabled: !_cloudSyncBusy,
                child: OutlinedButton.icon(
                  onPressed: _cloudSyncBusy ? null : () => _runCloudPush(pullInstead: true),
                  icon: const Icon(Icons.cloud_download_outlined, size: 16),
                  label: Text(
                    tr ? 'Buluttan Çek' : 'Pull from RTDB',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7DD3FC),
                    side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (statusText != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: (statusIsOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (statusIsOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                color: statusIsOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TactilePress(
              child: ActionChip(
                avatar: Icon(
                  _showCloudPayloadPreview ? Icons.code_off_rounded : Icons.data_object_rounded,
                  size: 14,
                  color: const Color(0xFF38BDF8),
                ),
                label: Text(
                  _showCloudPayloadPreview
                      ? (tr ? 'JSON Önizlemeyi Gizle' : 'Hide JSON Preview')
                      : (tr ? 'Canlı JSON Önizleme' : 'Live JSON Preview'),
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                onPressed: () {
                  _hapticTap();
                  _updateState(() => _showCloudPayloadPreview = !_showCloudPayloadPreview);
                },
              ),
            ),
            TactilePress(
              child: ActionChip(
                avatar: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF10B981)),
                label: Text(
                  tr ? 'JSON Kopyala' : 'Copy JSON',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                onPressed: () async {
                  _hapticTap();
                  await Clipboard.setData(ClipboardData(text: payloadPreview));
                  if (!mounted) return;
                  _updateState(() {
                    _cloudSyncOk = true;
                    _cloudSyncStatus = tr
                        ? '/$activeNode.json telemetri yükü panoya kopyalandı.'
                        : '/$activeNode.json telemetry payload copied.';
                  });
                },
              ),
            ),
          ],
        ),
        if (_showCloudPayloadPreview) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                payloadPreview,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: Color(0xFFBAE6FD),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
