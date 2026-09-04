// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Internet addresses as pure values: parsing, version classification,
/// ranges in CIDR form and the non-public ranges a development machine
/// sits in.
///
/// Everything here is a pure function over strings and small integers.
/// Failure is an absent value, not a `Result`: the only failure these
/// functions know is "the input is not a well-formed address" (ADR-006).
///
/// Range membership compares octet by octet and group by group. No wide
/// integer arithmetic, so the code behaves identically on the VM and
/// compiled to JavaScript, where integers are doubles.
library;

/// An internet address, parsed and validated.
///
/// Obtain one through [tryParse]; the two concrete shapes are
/// [IpV4Address] and [IpV6Address], and a switch over them is exhaustive.
sealed class IpAddress {
  /// Const constructor for the two variants.
  const IpAddress();

  /// Parses [text] as an IPv4 or IPv6 address.
  ///
  /// IPv4 is four decimal octets, each 0 to 255, without leading zeros.
  /// IPv6 accepts the full and the `::`-compressed form, upper or lower
  /// case hex, and a trailing dotted quad (`::ffff:192.0.2.1`). Zone
  /// identifiers (`%eth0`), CIDR suffixes and surrounding whitespace are
  /// rejected.
  ///
  /// Returns null when [text] is neither. There is no reason to report
  /// beyond "not an address", so the absent value is the whole story
  /// (ADR-006).
  static IpAddress? tryParse(String text) => text.contains(':')
      ? IpV6Address._tryParse(text)
      : IpV4Address._tryParse(text);

  /// The version mark the tooltip shows: `v4` or `v6`.
  String get versionLabel;

  /// Whether the address is not publicly routable.
  ///
  /// True for the private networks of RFC 1918 (`10/8`, `172.16/12`,
  /// `192.168/16`), loopback (`127/8`, `::1`), link-local (`169.254/16`,
  /// `fe80::/10`), carrier grade NAT (`100.64/10`, RFC 6598) and IPv6
  /// unique local addresses (`fc00::/7`, RFC 4193). Deliberately broader
  /// than the "RFC 1918" the specification names: a development machine
  /// behind carrier grade NAT must not be reported as a foreign address.
  bool get isNonPublic;
}

/// An IPv4 address as four octets.
final class IpV4Address extends IpAddress {
  IpV4Address._(this.octets);

  /// The four octets, most significant first, each 0 to 255.
  /// Unmodifiable.
  final List<int> octets;

  @override
  String get versionLabel => 'v4';

  @override
  bool get isNonPublic => _nonPublicV4.any((range) => range.contains(this));

  /// The dotted decimal form.
  @override
  String toString() => octets.join('.');

  static IpV4Address? _tryParse(String text) {
    final parts = text.split('.');
    if (parts.length != 4) {
      return null;
    }
    final octets = <int>[];
    for (final part in parts) {
      final value = _decimalOctet(part);
      if (value == null) {
        return null;
      }
      octets.add(value);
    }
    return IpV4Address._(List<int>.unmodifiable(octets));
  }

  static int? _decimalOctet(String part) {
    if (part.isEmpty || part.length > 3) {
      return null;
    }
    // "01" is ambiguous (historically octal), so a leading zero is only
    // the octet "0" itself.
    if (part.length > 1 && part.startsWith('0')) {
      return null;
    }
    var value = 0;
    for (final unit in part.codeUnits) {
      if (unit < 0x30 || unit > 0x39) {
        return null;
      }
      value = value * 10 + (unit - 0x30);
    }
    if (value > 255) {
      return null;
    }
    return value;
  }
}

/// An IPv6 address as eight 16-bit groups.
final class IpV6Address extends IpAddress {
  IpV6Address._(this.groups);

  /// The eight 16-bit groups, most significant first, each 0 to 0xffff.
  /// Unmodifiable.
  final List<int> groups;

  @override
  String get versionLabel => 'v6';

  @override
  bool get isNonPublic => _nonPublicV6.any((range) => range.contains(this));

  /// The uncompressed lower case hex form, for diagnostics. Not the
  /// RFC 5952 canonical text; no consumer needs one.
  @override
  String toString() => groups.map((group) => group.toRadixString(16)).join(':');

  static IpV6Address? _tryParse(String text) {
    final compressionStart = text.indexOf('::');
    if (compressionStart != text.lastIndexOf('::')) {
      return null;
    }

    var headParts = const <String>[];
    var tailParts = const <String>[];
    if (compressionStart >= 0) {
      final head = text.substring(0, compressionStart);
      final tail = text.substring(compressionStart + 2);
      headParts = head.isEmpty ? const [] : head.split(':');
      tailParts = tail.isEmpty ? const [] : tail.split(':');
    } else {
      headParts = text.split(':');
    }

    // A dotted quad may close the address: the last part of the tail, or
    // of the head when there is no compression.
    var trailing = compressionStart >= 0 ? tailParts : headParts;
    final dottedGroups = <int>[];
    if (trailing.isNotEmpty && trailing.last.contains('.')) {
      final quad = IpV4Address._tryParse(trailing.last);
      if (quad == null) {
        return null;
      }
      dottedGroups
        ..add(quad.octets[0] * 256 + quad.octets[1])
        ..add(quad.octets[2] * 256 + quad.octets[3]);
      trailing = trailing.sublist(0, trailing.length - 1);
    }
    if (compressionStart >= 0) {
      tailParts = trailing;
    } else {
      headParts = trailing;
    }

    final headGroups = _hexGroups(headParts);
    final tailGroups = _hexGroups(tailParts);
    if (headGroups == null || tailGroups == null) {
      return null;
    }

    final named = headGroups.length + tailGroups.length + dottedGroups.length;
    if (compressionStart >= 0) {
      // The compression stands for at least one zero group.
      if (named > 7) {
        return null;
      }
    } else if (named != 8) {
      return null;
    }

    final zeroCount = compressionStart >= 0 ? 8 - named : 0;
    return IpV6Address._(
      List<int>.unmodifiable(<int>[
        ...headGroups,
        ...List<int>.filled(zeroCount, 0),
        ...tailGroups,
        ...dottedGroups,
      ]),
    );
  }

  static List<int>? _hexGroups(List<String> parts) {
    final groups = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 4) {
        return null;
      }
      var value = 0;
      for (final unit in part.codeUnits) {
        final digit = _hexDigit(unit);
        if (digit == null) {
          return null;
        }
        value = value * 16 + digit;
      }
      groups.add(value);
    }
    return groups;
  }

  static int? _hexDigit(int unit) {
    if (unit >= 0x30 && unit <= 0x39) {
      return unit - 0x30;
    }
    if (unit >= 0x61 && unit <= 0x66) {
      return unit - 0x61 + 10;
    }
    if (unit >= 0x41 && unit <= 0x46) {
      return unit - 0x41 + 10;
    }
    return null;
  }
}

/// An IPv4 range in CIDR form: a network address and a prefix length.
///
/// Constructed const, octet by octet, so that the compiled-in range lists
/// (`cloudflare_ranges.dart`, and the non-public ranges in this file) are
/// checked when they are written: an out-of-range octet or prefix fails
/// the const evaluation instead of surviving until a lookup.
final class CidrV4 {
  /// Describes the range `octet1.octet2.octet3.octet4/prefixLength`.
  const CidrV4(
    this.octet1,
    this.octet2,
    this.octet3,
    this.octet4,
    this.prefixLength,
  )   : assert(octet1 >= 0 && octet1 <= 255, 'octet1 out of range'),
        assert(octet2 >= 0 && octet2 <= 255, 'octet2 out of range'),
        assert(octet3 >= 0 && octet3 <= 255, 'octet3 out of range'),
        assert(octet4 >= 0 && octet4 <= 255, 'octet4 out of range'),
        assert(
          prefixLength >= 0 && prefixLength <= 32,
          'prefix length out of range',
        );

  /// The most significant octet of the network address.
  final int octet1;

  /// The second octet of the network address.
  final int octet2;

  /// The third octet of the network address.
  final int octet3;

  /// The least significant octet of the network address.
  final int octet4;

  /// The number of leading bits that select the range.
  final int prefixLength;

  /// Whether [address] lies inside this range.
  bool contains(IpV4Address address) => _prefixMatches(
        network: <int>[octet1, octet2, octet3, octet4],
        address: address.octets,
        bitsPerUnit: 8,
        prefixLength: prefixLength,
      );

  @override
  String toString() => '$octet1.$octet2.$octet3.$octet4/$prefixLength';
}

/// An IPv6 range in CIDR form: a network address and a prefix length.
///
/// Same construction discipline as [CidrV4]: const, group by group, so a
/// bad compiled-in entry fails when it is written.
final class CidrV6 {
  /// Describes the range whose network address is the eight groups, most
  /// significant first, with [prefixLength] leading bits selecting it.
  const CidrV6(
    this.group1,
    this.group2,
    this.group3,
    this.group4,
    this.group5,
    this.group6,
    this.group7,
    this.group8,
    this.prefixLength,
  )   : assert(group1 >= 0 && group1 <= 0xffff, 'group1 out of range'),
        assert(group2 >= 0 && group2 <= 0xffff, 'group2 out of range'),
        assert(group3 >= 0 && group3 <= 0xffff, 'group3 out of range'),
        assert(group4 >= 0 && group4 <= 0xffff, 'group4 out of range'),
        assert(group5 >= 0 && group5 <= 0xffff, 'group5 out of range'),
        assert(group6 >= 0 && group6 <= 0xffff, 'group6 out of range'),
        assert(group7 >= 0 && group7 <= 0xffff, 'group7 out of range'),
        assert(group8 >= 0 && group8 <= 0xffff, 'group8 out of range'),
        assert(
          prefixLength >= 0 && prefixLength <= 128,
          'prefix length out of range',
        );

  /// The most significant 16-bit group of the network address.
  final int group1;

  /// The second group of the network address.
  final int group2;

  /// The third group of the network address.
  final int group3;

  /// The fourth group of the network address.
  final int group4;

  /// The fifth group of the network address.
  final int group5;

  /// The sixth group of the network address.
  final int group6;

  /// The seventh group of the network address.
  final int group7;

  /// The least significant group of the network address.
  final int group8;

  /// The number of leading bits that select the range.
  final int prefixLength;

  /// Whether [address] lies inside this range.
  bool contains(IpV6Address address) => _prefixMatches(
        network: <int>[
          group1,
          group2,
          group3,
          group4,
          group5,
          group6,
          group7,
          group8,
        ],
        address: address.groups,
        bitsPerUnit: 16,
        prefixLength: prefixLength,
      );

  @override
  String toString() {
    final groups = <int>[
      group1,
      group2,
      group3,
      group4,
      group5,
      group6,
      group7,
      group8,
    ].map((group) => group.toRadixString(16)).join(':');
    return '$groups/$prefixLength';
  }
}

/// Whether the first [prefixLength] bits of [address] equal those of
/// [network], compared unit by unit with [bitsPerUnit] bits each.
bool _prefixMatches({
  required List<int> network,
  required List<int> address,
  required int bitsPerUnit,
  required int prefixLength,
}) {
  var remaining = prefixLength;
  for (var index = 0; index < network.length; index += 1) {
    if (remaining <= 0) {
      return true;
    }
    final bits = remaining < bitsPerUnit ? remaining : bitsPerUnit;
    final shift = bitsPerUnit - bits;
    if (network[index] >> shift != address[index] >> shift) {
      return false;
    }
    remaining -= bits;
  }
  return true;
}

// The ranges behind IpAddress.isNonPublic. The selection is the one the
// header inspector needs, and deliberately broader -- see the getter's doc.
const List<CidrV4> _nonPublicV4 = [
  CidrV4(10, 0, 0, 0, 8), // private networks, RFC 1918
  CidrV4(172, 16, 0, 0, 12), // private networks, RFC 1918
  CidrV4(192, 168, 0, 0, 16), // private networks, RFC 1918
  CidrV4(127, 0, 0, 0, 8), // loopback, RFC 1122
  CidrV4(169, 254, 0, 0, 16), // link-local, RFC 3927
  CidrV4(100, 64, 0, 0, 10), // carrier grade NAT, RFC 6598
];

const List<CidrV6> _nonPublicV6 = [
  CidrV6(0, 0, 0, 0, 0, 0, 0, 1, 128), // loopback ::1, RFC 4291
  CidrV6(0xfe80, 0, 0, 0, 0, 0, 0, 0, 10), // link-local, RFC 4291
  CidrV6(0xfc00, 0, 0, 0, 0, 0, 0, 0, 7), // unique local, RFC 4193
];
