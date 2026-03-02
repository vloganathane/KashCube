/// Builds RFC 6350 vCard 3.0 strings from app data.
/// No network calls — pure string construction on-device.
library;

import '../../data/models/business.dart';
import '../../data/models/party.dart';

/// Generic vCard builder. All fields are optional except [name].
String buildVCard({
  required String name,
  String? org,
  String? title,
  String? phone,
  String? email,
  String? address,
  String? gstin,
  String? website,
  String? whatsapp,
  String? linkedin,
  String? instagram,
}) {
  final buf = StringBuffer()
    ..writeln('BEGIN:VCARD')
    ..writeln('VERSION:3.0')
    ..writeln('FN:$name');

  if (org != null && org.isNotEmpty) buf.writeln('ORG:$org');
  if (title != null && title.isNotEmpty) buf.writeln('TITLE:$title');
  if (phone != null && phone.isNotEmpty) {
    final e164 = _toE164(phone);
    buf.writeln('TEL;TYPE=CELL:$e164');
  }
  if (email != null && email.isNotEmpty) buf.writeln('EMAIL:$email');
  if (address != null && address.isNotEmpty) {
    buf.writeln('ADR;TYPE=WORK:;;$address;;;;IN');
  }
  if (website != null && website.isNotEmpty) buf.writeln('URL:$website');

  // WhatsApp — non-standard but widely parsed by Android/iOS
  if (whatsapp != null && whatsapp.isNotEmpty) {
    final wa = _toE164(whatsapp);
    buf.writeln('X-WHATSAPP:$wa');
  }
  if (linkedin != null && linkedin.isNotEmpty) {
    buf.writeln('X-SOCIALPROFILE;TYPE=linkedin:$linkedin');
  }
  if (instagram != null && instagram.isNotEmpty) {
    buf.writeln('X-SOCIALPROFILE;TYPE=instagram:$instagram');
  }

  // GSTIN embedded in NOTE (no standard vCard field)
  final notes = <String>[
    if (gstin != null && gstin.isNotEmpty) 'GSTIN: $gstin',
  ];
  if (notes.isNotEmpty) buf.writeln('NOTE:${notes.join(' | ')}');

  buf.write('END:VCARD');
  return buf.toString();
}

/// Build a vCard from a [Party].
String vCardFromParty(Party party) {
  final addr = [
    if (party.address != null) party.address,
    if (party.city != null) party.city,
    if (party.state != null) party.state,
    if (party.pincode != null) party.pincode,
  ].whereType<String>().join(', ');

  return buildVCard(
    name: party.name,
    phone: party.phoneNumber,
    email: party.email,
    address: addr.isEmpty ? null : addr,
    gstin: party.gstin,
    website: party.website,
    whatsapp: party.whatsapp,
    linkedin: party.linkedin,
    instagram: party.instagram,
  );
}

/// Build a vCard from a [Business] profile.
String vCardFromBusiness(Business biz) {
  final addr = [
    if (biz.address != null) biz.address,
    if (biz.city != null) biz.city,
    if (biz.state != null) biz.state,
    if (biz.pincode != null) biz.pincode,
  ].whereType<String>().join(', ');

  return buildVCard(
    name: biz.ownerName?.isNotEmpty == true ? biz.ownerName! : biz.name,
    org: biz.name,
    phone: biz.phone,
    email: biz.email,
    address: addr.isEmpty ? null : addr,
    gstin: biz.gstNo,
    website: biz.website,
    whatsapp: biz.whatsapp,
    linkedin: biz.linkedin,
    instagram: biz.instagram,
  );
}

/// Build a vCard from flat personal-card settings values.
String vCardFromPersonalSettings({
  required String? name,
  String? phone,
  String? email,
  String? website,
  String? whatsapp,
  String? linkedin,
  String? instagram,
}) {
  return buildVCard(
    name: (name != null && name.isNotEmpty) ? name : 'My Card',
    phone: phone,
    email: email,
    website: website,
    whatsapp: whatsapp,
    linkedin: linkedin,
    instagram: instagram,
  );
}

/// Parse a raw vCard string into a flat map of known fields.
/// Used by the QR scanner to pre-fill the Add Contact form.
Map<String, String?> parseVCard(String raw) {
  final result = <String, String?>{};
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    void setValue(String key, String val) {
      if (val.isNotEmpty) result[key] = val;
    }

    if (trimmed.startsWith('FN:')) {
      setValue('name', trimmed.substring(3));
    } else if (trimmed.startsWith('ORG:')) {
      setValue('org', trimmed.substring(4));
    } else if (trimmed.startsWith('TITLE:')) {
      setValue('title', trimmed.substring(6));
    } else if (trimmed.startsWith('TEL')) {
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx != -1) {
        final raw = trimmed.substring(colonIdx + 1).trim();
        setValue('phone', _stripE164(raw));
      }
    } else if (trimmed.startsWith('EMAIL')) {
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx != -1) setValue('email', trimmed.substring(colonIdx + 1).trim());
    } else if (trimmed.startsWith('ADR')) {
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx != -1) {
        // ADR format: ;;street;city;state;postal;country
        final parts = trimmed.substring(colonIdx + 1).split(';');
        if (parts.length > 2) setValue('address', parts[2].trim());
        if (parts.length > 3) setValue('city', parts[3].trim());
        if (parts.length > 4) setValue('state', parts[4].trim());
        if (parts.length > 5) setValue('pincode', parts[5].trim());
      }
    } else if (trimmed.startsWith('URL:')) {
      setValue('website', trimmed.substring(4));
    } else if (trimmed.startsWith('X-WHATSAPP:')) {
      setValue('whatsapp', _stripE164(trimmed.substring(11)));
    } else if (trimmed.startsWith('X-SOCIALPROFILE;TYPE=linkedin:')) {
      setValue('linkedin', trimmed.substring(30));
    } else if (trimmed.startsWith('X-SOCIALPROFILE;TYPE=instagram:')) {
      setValue('instagram', trimmed.substring(31));
    } else if (trimmed.startsWith('NOTE:')) {
      final note = trimmed.substring(5);
      // Extract GSTIN from NOTE if present
      final gstinMatch = RegExp(r'GSTIN:\s*([A-Z0-9]{15})').firstMatch(note);
      if (gstinMatch != null) setValue('gstin', gstinMatch.group(1)!);
    }
  }
  return result;
}

// ── Internal helpers ──────────────────────────────────────────────────────────

String _toE164(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length == 10) return '+91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
  if (digits.startsWith('91') && digits.length > 10) return '+$digits';
  return '+$digits';
}

String _stripE164(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
  if (digits.length == 10) return digits;
  return phone;
}
