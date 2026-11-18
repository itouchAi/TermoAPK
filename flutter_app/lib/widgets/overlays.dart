import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

Future<void> showVoiceCommandSheet({
  required BuildContext context,
  required LangCode lang,
  required Color accentColor,
  required ValueChanged<VoiceCommandResult> onExecute,
}) {
  final controller = TextEditingController();
  String? feedback;

  final presets = lang == LangCode.tr
      ? ['Sıcaklığı 24 derece yap', 'Eko moda geç', 'Gece modu', 'Hava durumunu aç']
      : ['Set temperature to 24°', 'Switch to Eco mode', 'Comfort mode', 'Open weather'];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111218),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void submit(String text) {
            final res = ThermostatMath.parseVoiceCommand(text);
            setSheetState(() {
              feedback = lang == LangCode.tr ? res.replyTr : res.replyEn;
            });
            if (res.handled) onExecute(res);
            controller.clear();
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: accentColor.withValues(alpha: 0.2),
                            child: Icon(Icons.mic_none_rounded, size: 18, color: accentColor),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            lang == LangCode.tr ? 'Sesli Komut Asistanı' : 'Voice Command Assistant',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cmd in presets)
                        ActionChip(
                          label: Text(cmd, style: const TextStyle(fontSize: 12, color: Colors.white)),
                          backgroundColor: Colors.white.withValues(alpha: 0.07),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                          onPressed: () => submit(cmd),
                        ),
                    ],
                  ),
                  if (feedback != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(feedback!, style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: lang == LangCode.tr ? 'Örn: 23.5 derece yap...' : 'e.g. Set 23.5°...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                          ),
                          onSubmitted: submit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => submit(controller.text),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          minimumSize: const Size(74, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(lang == LangCode.tr ? 'Uygula' : 'Run'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
