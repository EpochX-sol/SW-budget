import 'regex_template.dart';

/// Represents a versioned bundle of regex templates signed with Ed25519.
class TemplateBundle {
  final int bundleVersion;
  final List<RegexTemplate> templates;
  final String? signature;
  final String? publicKey;

  const TemplateBundle({
    required this.bundleVersion,
    required this.templates,
    this.signature,
    this.publicKey,
  });

  factory TemplateBundle.fromJson(Map<String, dynamic> json) => TemplateBundle(
        bundleVersion: json['bundle_version'] as int? ?? json['version'] as int? ?? 1,
        templates: (json['templates'] as List<dynamic>)
            .map((e) => RegexTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
        signature: json['signature'] as String?,
        publicKey: json['public_key'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'bundle_version': bundleVersion,
        'templates': templates.map((t) => t.toJson()).toList(),
        if (signature != null) 'signature': signature,
        if (publicKey != null) 'public_key': publicKey,
      };
}
