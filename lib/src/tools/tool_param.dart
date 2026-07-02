/// Defines the type of a [ToolParam].
enum ToolParamType { string, number, integer, boolean, array, object }

/// A single typed parameter for a [AgenticTool].
///
/// Use the named constructors instead of the raw constructor:
/// ```dart
/// ToolParam.string(description: 'City name', required: true)
/// ToolParam.number(description: 'Temperature in celsius')
/// ToolParam.boolean(description: 'Whether to include forecast')
/// ToolParam.stringEnum(['celsius', 'fahrenheit'], description: 'Unit')
/// ```
class ToolParam {
  final ToolParamType type;
  final String description;
  final bool required;
  final List<String>? enumValues;
  final ToolParam? items; // for array type
  final Map<String, ToolParam>? properties; // for object type
  final dynamic defaultValue;

  const ToolParam._({
    required this.type,
    required this.description,
    this.required = false,
    this.enumValues,
    this.items,
    this.properties,
    this.defaultValue,
  });

  // ─── Named constructors ──────────────────────────────────────────────────

  /// A text parameter. Most common type.
  ///
  /// Example: `ToolParam.string(description: 'City name', required: true)`
  factory ToolParam.string({
    required String description,
    bool required = false,
    dynamic defaultValue,
  }) =>
      ToolParam._(
        type: ToolParamType.string,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// A string parameter restricted to a fixed set of values.
  ///
  /// Example: `ToolParam.stringEnum(['celsius','fahrenheit'], description: 'Unit')`
  factory ToolParam.stringEnum(
    List<String> values, {
    required String description,
    bool required = false,
    String? defaultValue,
  }) =>
      ToolParam._(
        type: ToolParamType.string,
        description: description,
        required: required,
        enumValues: values,
        defaultValue: defaultValue,
      );

  /// A floating-point number parameter.
  factory ToolParam.number({
    required String description,
    bool required = false,
    num? defaultValue,
  }) =>
      ToolParam._(
        type: ToolParamType.number,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// A whole-number parameter.
  factory ToolParam.integer({
    required String description,
    bool required = false,
    int? defaultValue,
  }) =>
      ToolParam._(
        type: ToolParamType.integer,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// A true/false parameter.
  factory ToolParam.boolean({
    required String description,
    bool required = false,
    bool? defaultValue,
  }) =>
      ToolParam._(
        type: ToolParamType.boolean,
        description: description,
        required: required,
        defaultValue: defaultValue,
      );

  /// A list parameter where each item matches [itemType].
  factory ToolParam.array({
    required String description,
    required ToolParam items,
    bool required = false,
  }) =>
      ToolParam._(
        type: ToolParamType.array,
        description: description,
        required: required,
        items: items,
      );

  /// A nested object parameter with its own typed properties.
  factory ToolParam.object({
    required String description,
    required Map<String, ToolParam> properties,
    bool required = false,
  }) =>
      ToolParam._(
        type: ToolParamType.object,
        description: description,
        required: required,
        properties: properties,
      );

  // ─── JSON Schema serialization ───────────────────────────────────────────

  /// Alias for [toJsonSchema] — shorter name for inline use.
  Map<String, dynamic> toSchema() => toJsonSchema();

  /// Converts this param to the JSON Schema format expected by LLM APIs.
  Map<String, dynamic> toJsonSchema() {
    final schema = <String, dynamic>{
      'type': _typeString,
      'description': description,
    };
    if (enumValues != null) schema['enum'] = enumValues;
    if (defaultValue != null) schema['default'] = defaultValue;
    if (items != null) schema['items'] = items!.toJsonSchema();
    if (properties != null) {
      schema['properties'] = {
        for (final e in properties!.entries)
          e.key: e.value.toJsonSchema(),
      };
      final required = properties!.entries
          .where((e) => e.value.required)
          .map((e) => e.key)
          .toList();
      if (required.isNotEmpty) schema['required'] = required;
    }
    return schema;
  }

  String get _typeString => switch (type) {
        ToolParamType.string => 'string',
        ToolParamType.number => 'number',
        ToolParamType.integer => 'integer',
        ToolParamType.boolean => 'boolean',
        ToolParamType.array => 'array',
        ToolParamType.object => 'object',
      };
}

/// Builds the full JSON Schema `parameters` object from a map of [ToolParam]s.
///
/// Used internally by [AgenticTool.define].
Map<String, dynamic> buildParametersSchema(Map<String, ToolParam> params) {
  final required =
      params.entries.where((e) => e.value.required).map((e) => e.key).toList();
  return {
    'type': 'object',
    'properties': {
      for (final e in params.entries) e.key: e.value.toJsonSchema(),
    },
    if (required.isNotEmpty) 'required': required,
  };
}
