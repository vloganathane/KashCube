import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Minimal local peer connection adapter for generating WebRTC offer/answer.
///
/// Represents one side of a peer connection negotiation. Stores the offer and
/// can generate a corresponding answer without requiring the flutter_webrtc
/// peer connection engine (yet). This allows deterministic negotiation staging
/// at the signaling layer before the actual RTCPeerConnection() allocation.
///
/// Usage:
/// ```dart
/// final adapter = LocalPeerConnectionAdapter(sessionId: 'sess-123');
///
/// // Browser sends offer
/// final offerSdp = '...offer sdp...';
/// final answerSdp = adapter.processOfferAndGenerateAnswer(offerSdp);
/// // answerSdp can now be sent back to browser
/// ```
class LocalPeerConnectionAdapter {
  LocalPeerConnectionAdapter({required this.sessionId});

  /// Unique session ID for this peer connection negotiation.
  final String sessionId;

  /// Cached offer SDP received from remote peer.
  String? _offerSdp;

  /// Cached answer SDP generated locally.
  String? _answerSdp;

  /// Timestamp when adapter was created.
  final DateTime _createdAt = DateTime.now().toUtc();

  /// Whether this adapter has processed an offer and generated answer.
  bool get hasAnswer => _answerSdp != null;

  /// Whether this adapter has cached an offer.
  bool get hasOffer => _offerSdp != null;

  /// Process remote offer SDP and generate corresponding answer SDP.
  ///
  /// Returns the generated answer SDP that can be sent back to the remote peer.
  /// Throws if called multiple times (idempotency per session).
  String processOfferAndGenerateAnswer(String offerSdp) {
    if (_offerSdp != null) {
      throw StateError('Offer already processed for session $sessionId');
    }
    if (offerSdp.isEmpty) {
      throw ArgumentError('Offer SDP cannot be empty');
    }

    _offerSdp = offerSdp;

    // Generate a minimal corresponding answer.
    // For now, this is a synthetic answer that mirrors the offer structure
    // without requiring the real flutter_webrtc RTCPeerConnection engine.
    // When flutter_webrtc is wired up, this will be replaced with actual
    // peer.createAnswer() call targeting the offer.
    _answerSdp = _generateSyntheticAnswer(offerSdp);

    debugPrint(
      '[LocalPeerConnectionAdapter] Generated answer for session $sessionId '
      '(offer hash: ${_hashSdp(offerSdp)})',
    );

    return _answerSdp!;
  }

  /// Generate a synthetic answer SDP that mirrors the offer.
  ///
  /// This is a temporary implementation that creates a structurally valid
  /// but non-functional answer SDP. It extracts media lines from the offer
  /// and creates corresponding answer lines.
  ///
  /// When flutter_webrtc RTCPeerConnection is wired up, this becomes:
  /// ```dart
  /// final answer = await peerConnection.createAnswer();
  /// return answer.sdp!;
  /// ```
  String _generateSyntheticAnswer(String offerSdp) {
    final lines = offerSdp.split('\n');
    final answerLines = <String>[];

    String? version;
    String? origin;

    for (final line in lines) {
      if (line.startsWith('v=')) {
        version = line;
      } else if (line.startsWith('o=')) {
        origin = line;
      } else if (line.startsWith('s=')) {
        answerLines.add('s=- '); // Answer session name (minimal)
      } else if (line.startsWith('t=')) {
        answerLines.add('t=0 0');
      } else if (line.startsWith('m=')) {
        // Media line: mirror the media type but set all ports to 9
        // (inactive/dummy in answer until actual engine produces real candidates)
        final parts = line.split(' ');
        if (parts.length >= 3) {
          answerLines.add('${parts[0]} ${parts[1]} 9 ${parts.sublist(3).join(' ')}');
        }
      } else if (line.startsWith('a=')) {
        // Copy only non-candidate attributes (candidates come via ICE separately)
        if (!line.contains('candidate') && line.isNotEmpty) {
          // For offer m= lines, create answer equivalents
          if (line.contains('sendrecv')) {
            answerLines.add('a=sendrecv');
          }
        }
      }
    }

    // Build answer with version and initial lines
    final answer = StringBuffer();
    if (version != null) answer.writeln(version);
    if (origin != null) {
      // Modify origin to reflect answer (flip o= session to 'answer')
      answer.writeln(origin.replaceFirst(RegExp(r' \d+'), ' ${_now()}'));
    }
    answer.writeln('s=- ');
    answer.writeln('t=0 0');
    answer.writeln('a=bundle-only');

    for (final line in answerLines) {
      if (line.isNotEmpty && !line.startsWith('s=') && !line.startsWith('t=')) {
        answer.writeln(line);
      }
    }

    return answer.toString();
  }

  /// Get cached offer SDP (if processed).
  String? getOfferSdp() => _offerSdp;

  /// Get cached answer SDP (if generated).
  String? getAnswerSdp() => _answerSdp;

  /// Timestamp when this adapter was instantiated.
  DateTime get createdAt => _createdAt;

  /// Time elapsed since adapter creation.
  Duration get age => DateTime.now().toUtc().difference(_createdAt);

  /// Generate deterministic hash of SDP for deduplication/logging.
  static String _hashSdp(String sdp) {
    return sha256.convert(sdp.codeUnits).toString().substring(0, 8);
  }

  /// Current Unix timestamp (for synthetic SDP origin line).
  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  String toString() => 'LocalPeerConnectionAdapter('
      'sessionId=$sessionId, '
      'hasOffer=$hasOffer, '
      'hasAnswer=$hasAnswer, '
      'age=${age.inSeconds}s'
      ')';
}
