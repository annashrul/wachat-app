import 'package:flutter/material.dart';
import '../models/message.dart';

/// Ikon centang status pesan (dipakai di gelembung & daftar chat).
/// [normal] untuk pending/sent/delivered, [read] (biru) untuk sudah dibaca.
Widget statusTick(
  MessageStatus status, {
  required Color normal,
  required Color read,
  double size = 15,
}) {
  switch (status) {
    case MessageStatus.pending:
      return Icon(Icons.access_time_rounded, size: size - 2, color: normal);
    case MessageStatus.sent:
      return Icon(Icons.check_rounded, size: size, color: normal);
    case MessageStatus.delivered:
      return Icon(Icons.done_all_rounded, size: size, color: normal);
    case MessageStatus.read:
      return Icon(Icons.done_all_rounded, size: size, color: read);
  }
}
