import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abstraction for sending WhatsApp, SMS, and Email reminders via OS deep links.
///
/// All communication happens locally — no network calls, no data transmission.
/// This service only constructs deep-link URIs and hands them to the OS.
class CommunicationService {
  CommunicationService._();
  static final CommunicationService instance = CommunicationService._();

  // ── WhatsApp ─────────────────────────────────────────────────────────────

  /// Open WhatsApp with [message] pre-filled for [phone].
  ///
  /// Automatically prefixes with `91` if the number doesn't already start
  /// with a country code.
  Future<bool> sendWhatsApp(String phone, String message) async {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\+]'), '');
    final formatted = (cleaned.startsWith('91') && cleaned.length >= 12)
        ? cleaned
        : '91$cleaned';
    final url =
        'https://wa.me/$formatted?text=${Uri.encodeComponent(message)}';
    return _launch(url);
  }

  // ── SMS ──────────────────────────────────────────────────────────────────

  /// Open the SMS app with [message] pre-filled for [phone].
  Future<bool> sendSMS(String phone, String message) async {
    final cleaned = phone.replaceAll(RegExp(r'[\s\+]'), '');
    final url = 'sms:+91$cleaned?body=${Uri.encodeComponent(message)}';
    return _launch(url);
  }

  // ── Email ────────────────────────────────────────────────────────────────

  /// Open the email app with [subject] and [body] pre-filled for [email].
  Future<bool> sendEmail(
      String email, String subject, String body) async {
    final url =
        'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
    return _launch(url);
  }

  // ── Private helper ───────────────────────────────────────────────────────

  Future<bool> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('CommunicationService: cannot launch $url — $e');
    }
    return false;
  }
}
