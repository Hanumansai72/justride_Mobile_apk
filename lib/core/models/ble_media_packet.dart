/// FF31 opcode 0x12. State: 0 unsupported, 1 permission missing,
/// 2 no session, 3 paused, 4 playing, 5 other. Actions: play/pause/next/prev/volume.
List<int> encodeMediaSnapshot(Map<Object?, Object?> snapshot) {
  List<int> text(Object? value, int max) => (value?.toString() ?? '')
      .codeUnits
      .map((c) => c >= 32 && c <= 126 ? c : 63)
      .take(max)
      .toList();
  final title = text(snapshot['title'], 40);
  final artist = text(snapshot['artist'], 32);
  return [
    0x12,
    (snapshot['state'] as num? ?? 0).toInt().clamp(0, 5),
    (snapshot['actions'] as num? ?? 0).toInt() & 31,
    (snapshot['volume'] as num? ?? 0).toInt().clamp(0, 100),
    title.length,
    ...title,
    artist.length,
    ...artist
  ];
}
