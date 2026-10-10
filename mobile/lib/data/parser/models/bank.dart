class Bank {
  final int id;
  final String name;
  final String shortName;
  final List<String> codes;
  final String image;
  final int? maskPattern;
  final bool? uniformMasking;
  final bool? simBased;
  final List<String>? colors;

  const Bank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.codes,
    required this.image,
    this.maskPattern,
    this.uniformMasking,
    this.simBased,
    this.colors,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'] as int,
      name: json['name'] as String,
      shortName: json['shortName'] as String,
      codes: json['codes'] != null ? List<String>.from(json['codes'] as List) : const [],
      image: json['image'] as String? ?? '',
      maskPattern: json['maskPattern'] as int?,
      uniformMasking: json['uniformMasking'] as bool?,
      simBased: json['simBased'] as bool?,
      colors: json['colors'] != null ? List<String>.from(json['colors'] as List) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'codes': codes,
      'image': image,
      'maskPattern': maskPattern,
      'uniformMasking': uniformMasking,
      'simBased': simBased,
      'colors': colors,
    };
  }
}
