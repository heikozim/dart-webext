// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The language-neutral model both surface parsers produce and the
/// comparison consumes.
///
/// Types here carry raw type expressions as strings, exactly as they
/// appear in the parsed source. Normalizing and comparing those
/// expressions is the comparison's job, not the parsers'.
library;

/// One parameter of a function or of an event callback.
class ParameterSpec {
  /// Creates a parameter with the raw [type] expression of its source.
  const ParameterSpec(this.name, this.type, {this.optional = false});

  /// The parameter name as declared.
  final String name;

  /// The raw type expression as it appears in the source, without an
  /// optionality marker (the marker is [optional]).
  final String type;

  /// Whether a caller may omit the parameter. On the Dart side this is
  /// a nullable positional parameter, on the TypeScript side a `?`
  /// marker or a `| undefined` union member.
  final bool optional;

  @override
  String toString() => '$name: $type${optional ? '?' : ''}';
}

/// One callable signature: parameters plus return type.
class FunctionSignature {
  /// Creates a signature from parsed [parameters] and a raw [returnType].
  const FunctionSignature(this.parameters, this.returnType);

  /// The parameters in declaration order.
  final List<ParameterSpec> parameters;

  /// The raw return type expression.
  final String returnType;

  @override
  String toString() => '(${parameters.join(', ')}) -> $returnType';
}

/// A function member of a namespace, with one signature per overload.
///
/// The Dart side always has exactly one overload; the TypeScript side
/// may declare several.
class FunctionMember {
  /// Creates a function member named [name] with its [overloads].
  const FunctionMember(this.name, this.overloads);

  /// The member name, camelCase on both sides.
  final String name;

  /// All declared signatures, in declaration order, never empty.
  final List<FunctionSignature> overloads;
}

/// An event member of a namespace.
class EventMember {
  /// Creates an event member.
  const EventMember(
    this.name,
    this.callbackParameters, {
    this.registrationParameters = const [],
    this.unresolvedCallbackType,
  });

  /// The event name (`onSomething`).
  final String name;

  /// The parameters of the listener callback.
  ///
  /// The Dart side wraps the payload into a single `EventStream` type
  /// argument, so it contributes at most one entry (an empty list for a
  /// `void` payload) whose name is empty. The TypeScript side carries
  /// the callback parameter list verbatim.
  final List<ParameterSpec> callbackParameters;

  /// Parameters the listener registration takes beyond the callback
  /// itself, for example webRequest's `filter` and `extraInfoSpec`.
  /// Empty for plain events.
  final List<ParameterSpec> registrationParameters;

  /// Set when the TypeScript side declares the listener through a named
  /// type instead of an inline callback signature (for example
  /// `Events.Event<OnMessageListener>`). [callbackParameters] is then
  /// empty and the comparison resolves or rejects the name itself.
  final String? unresolvedCallbackType;
}

/// One field of a dictionary-like type.
class DictionaryField {
  /// Creates a field with the raw [type] expression of its source.
  const DictionaryField(this.name, this.type, {this.optional = false});

  /// The field name as declared.
  final String name;

  /// The raw type expression, without an optionality marker.
  final String type;

  /// Whether the field may be absent (nullable on the Dart side, `?`
  /// or `| undefined` on the TypeScript side).
  final bool optional;
}

/// A named object type referenced from signatures: a Dart class or a
/// TypeScript interface.
class Dictionary {
  /// Creates a dictionary type description.
  const Dictionary(
    this.name,
    this.fields, {
    this.methodNames = const {},
    this.extendedTypes = const [],
    this.hasIndexSignature = false,
  });

  /// The type name on its own side.
  final String name;

  /// The data fields in declaration order.
  final List<DictionaryField> fields;

  /// Names of method members. Methods on referenced object types are
  /// compared by name only, so their signatures are not kept.
  final Set<String> methodNames;

  /// Names of extended types whose fields count as inherited
  /// (TypeScript `extends`; unused on the Dart side).
  final List<String> extendedTypes;

  /// Whether the type declares an index signature
  /// (`[key: string]: ...`, TypeScript only).
  final bool hasIndexSignature;
}

/// A closed set of string values: a Dart enum with string values or a
/// TypeScript alias for a union of string literals.
class EnumDefinition {
  /// Creates an enum description with its wire [values].
  const EnumDefinition(this.name, this.values);

  /// The type name on its own side.
  final String name;

  /// The wire values (the strings that travel), not the identifiers.
  final Set<String> values;
}

/// Everything one parser extracted from one namespace source file.
class NamespaceSurface {
  /// Creates a parsed namespace surface.
  const NamespaceSurface({
    required this.namespace,
    required this.functions,
    required this.events,
    required this.propertyNames,
    required this.dictionaries,
    required this.enums,
    this.typeAliases = const {},
  });

  /// The namespace name in API notation (`webRequest`, not `web_request`).
  final String namespace;

  /// The namespace's functions.
  final List<FunctionMember> functions;

  /// The namespace's events.
  final List<EventMember> events;

  /// Names of property members. Properties and constants are outside
  /// the report's scope but are recorded so their existence is visible.
  final List<String> propertyNames;

  /// Named object types declared in this namespace, by name.
  final Map<String, Dictionary> dictionaries;

  /// Closed string sets declared in this namespace, by name.
  final Map<String, EnumDefinition> enums;

  /// Plain type aliases (`typedef X = ...` and non-union `type X = ...`),
  /// mapping the alias name to its raw right-hand side.
  final Map<String, String> typeAliases;
}

/// All parsed namespaces of one side, with cross-namespace type lookup.
///
/// Signatures reference types from sibling namespaces (the Dart
/// `action` file uses `Tab` from `tabs`), so type resolution searches
/// every parsed namespace.
class SurfaceCatalog {
  /// Creates a catalog over [namespaces].
  SurfaceCatalog(this.namespaces);

  /// The parsed namespaces.
  final List<NamespaceSurface> namespaces;

  /// Finds the namespace parsed as [name], or null.
  NamespaceSurface? namespace(String name) {
    for (final surface in namespaces) {
      if (surface.namespace == name) {
        return surface;
      }
    }
    return null;
  }

  /// Resolves a dictionary by [name] across all namespaces, or null.
  Dictionary? dictionary(String name) {
    for (final surface in namespaces) {
      final found = surface.dictionaries[name];
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Resolves an enum by [name] across all namespaces, or null.
  EnumDefinition? enumDefinition(String name) {
    for (final surface in namespaces) {
      final found = surface.enums[name];
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Resolves a plain type alias by [name] across all namespaces, or null.
  String? typeAlias(String name) {
    for (final surface in namespaces) {
      final found = surface.typeAliases[name];
      if (found != null) {
        return found;
      }
    }
    return null;
  }
}
