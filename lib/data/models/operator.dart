/// An application operator (staff member who uses the app).
/// Distinct from [Customer]s, who are the people being enrolled.
class Operator {
  const Operator({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.organization,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? organization;
  final DateTime createdAt;

  Operator copyWith({String? fullName, String? phone, String? organization}) =>
      Operator(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email,
        phone: phone ?? this.phone,
        organization: organization ?? this.organization,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'organization': organization,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Operator.fromJson(Map<String, dynamic> j) => Operator(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String? ?? '',
        organization: j['organization'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
