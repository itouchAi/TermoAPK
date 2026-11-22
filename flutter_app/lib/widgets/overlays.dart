import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/voice_speech_service.dart';

Future<void> showVoiceCommandSheet({
  required BuildContext context,
  required LangCode lang,
  required Color accentColor,
  required double currentTargetTemp,
  MascotCharacter character = MascotCharacter.ela,
  bool ttsEnabled = true,
  required ValueChanged<VoiceCommandResult> onExecute,
}) {
  final controller = TextEditingController();
  String? feedback;
  bool listening = false;
  bool speakingReply = ttsEnabled;
  var workingTarget = currentTargetTemp;

  final presets = lang == LangCode.tr
      ? [
          'Kombiyi kapat',
          '5 derece arttır',
          '2 derece azalt',
          'Eko moda geç',
          'Konfor modu',
          'Gece modu',
          'Boost modu',
          'Hava durumunu aç',
        ]
      : [
          'Turn off boiler',
          'Raise 5 degrees',
          'Lower 2 degrees',
          'Switch to Eco mode',
          'Comfort mode',
          'Night mode',
          'Boost mode',
          'Open weather',
        ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0E1118),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void submit(String text) {
            final res = ThermostatMath.parseVoiceCommand(
              text,
              currentTargetTemp: workingTarget,
            );
            final reply = lang == LangCode.tr ? res.replyTr : res.replyEn;
            setSheetState(() {
              feedback = reply;
            });
            if (res.handled) {
              if (res.newTargetTemp != null) {
                workingTarget = res.newTargetTemp!;
              }
              onExecute(res);
            }
            if (speakingReply) {
              VoiceSpeechService.speak(reply, lang: lang, character: character);
            }
            controller.clear();
          }

          Future<void> toggleMic() async {
            if (listening) {
              await VoiceSpeechService.stopListening();
              if (ctx.mounted) setSheetState(() => listening = false);
              return;
            }
            setSheetState(() {
              listening = true;
              feedback = lang == LangCode.tr
                  ? 'Dinleniyor... ("Kombiyi kapat", "5 derece arttır", "Eko mod")'
                  : 'Listening... ("Turn off boiler", "Raise 5 degrees", "Eco mode")';
            });
            final ok = await VoiceSpeechService.startListening(
              lang: lang,
              onResultText: (words) {
                if (ctx.mounted) {
                  setSheetState(() => controller.text = words);
                }
              },
              onFinalResult: (words) {
                if (ctx.mounted) {
                  setSheetState(() => listening = false);
                  submit(words);
                }
              },
              onStatusError: (err) {
                if (ctx.mounted) {
                  setSheetState(() {
                    listening = false;
                    feedback = err;
                  });
                }
              },
              onDone: () {
                if (ctx.mounted) setSheetState(() => listening = false);
              },
            );
            if (!ok && ctx.mounted) {
              setSheetState(() => listening = false);
            }
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
                            radius: 17,
                            backgroundColor: (listening ? const Color(0xFFEF4444) : accentColor)
                                .withValues(alpha: 0.22),
                            child: Icon(
                              listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                              size: 19,
                              color: listening ? const Color(0xFFF87171) : accentColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang == LangCode.tr ? 'Sesli Komut & Konuşma Asistanı' : 'Voice Command & Speech Assistant',
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              Text(
                                lang == LangCode.tr
                                    ? 'Hedef: ${workingTarget.toStringAsFixed(1)}°C · Mikrofon + Sesli Yanıt'
                                    : 'Target: ${workingTarget.toStringAsFixed(1)}°C · Mic + Voice Reply',
                                style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.56)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: lang == LangCode.tr ? 'Sesli Yanıt' : 'Voice Reply',
                            onPressed: () {
                              setSheetState(() => speakingReply = !speakingReply);
                              if (!speakingReply) VoiceSpeechService.stopSpeaking();
                            },
                            icon: Icon(
                              speakingReply ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              size: 20,
                              color: speakingReply ? const Color(0xFF34D399) : Colors.white38,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Big Press-to-Speak Microphone Banner
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: toggleMic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: listening
                            ? const Color(0xFFEF4444).withValues(alpha: 0.20)
                            : accentColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: listening
                              ? const Color(0xFFF87171)
                              : accentColor.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                            size: 24,
                            color: listening ? const Color(0xFFF87171) : accentColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  listening
                                      ? (lang == LangCode.tr ? 'Dinleniyor... Durdurmak için dokun' : 'Listening... Tap to stop')
                                      : (lang == LangCode.tr ? 'Mikrofonla Sesli Komut Ver' : 'Speak a Voice Command'),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                Text(
                                  lang == LangCode.tr
                                      ? 'Örn: "Kombiyi kapat", "5 derece arttır", "Eko / Konfor / Gece / Boost"'
                                      : 'e.g. "Turn off boiler", "Raise 5 degrees", "Eco / Comfort / Night / Boost"',
                                  style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.65)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final cmd in presets)
                        ActionChip(
                          label: Text(cmd, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
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
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.campaign_rounded, size: 16, color: Color(0xFF34D399)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(feedback!, style: const TextStyle(fontSize: 12, color: Colors.white)),
                          ),
                        ],
                      ),
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
                            hintText: lang == LangCode.tr ? 'Komut yazın (ör. 5 derece arttır)...' : 'Type command (e.g. Raise 5 degrees)...',
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
  ).whenComplete(() {
    VoiceSpeechService.stopListening();
    VoiceSpeechService.stopSpeaking();
  });
}
