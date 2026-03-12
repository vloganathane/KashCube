/// The single `my_identity` row — the permanent identity of this KashCube install.
class MyIdentity {
  const MyIdentity({
    required this.id,
    required this.identityId,
    required this.displayName,
    this.avatarSeed,
    required this.publicKey,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String identityId;   // permanent UUID
  final String displayName;  // user-chosen name
  final String? avatarSeed;  // optional seed for generated avatar
  final String publicKey;    // Ed25519 public key (base64)
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MyIdentity.fromMap(Map<String, dynamic> map) => MyIdentity(
        id:          map['id'] as int,
        identityId:  map['identity_id'] as String,
        displayName: map['display_name'] as String,
        avatarSeed:  map['avatar_seed'] as String?,
        publicKey:   map['public_key'] as String,
        createdAt:   DateTime.parse(map['created_at'] as String),
        updatedAt:   DateTime.parse(map['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id':           id,
        'identity_id':  identityId,
        'display_name': displayName,
        if (avatarSeed != null) 'avatar_seed': avatarSeed,
        'public_key':   publicKey,
        'created_at':   createdAt.toIso8601String(),
        'updated_at':   updatedAt.toIso8601String(),
      };

  MyIdentity copyWith({String? displayName, String? avatarSeed, String? publicKey}) =>
      MyIdentity(
        id:          id,
        identityId:  identityId,
        displayName: displayName ?? this.displayName,
        avatarSeed:  avatarSeed ?? this.avatarSeed,
        publicKey:   publicKey ?? this.publicKey,
        createdAt:   createdAt,
        updatedAt:   DateTime.now(),
      );
}
