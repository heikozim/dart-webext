// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Membership in Cloudflare's published address ranges.
library;

import 'cloudflare_ranges.dart';
import 'ip_address.dart';

/// Whether [address] lies inside Cloudflare's published ranges.
///
/// In the header inspector this is the CONFIRMING signal; the `server`
/// header is the primary one.
/// A stale compiled-in list therefore costs a confirmation mark, never a
/// false negative. The lists in `cloudflare_ranges.dart` carry their
/// source and fetch date; `tool/generate_cloudflare_ranges.dart`
/// regenerates them.
bool isCloudflareAddress(IpAddress address) => switch (address) {
      final IpV4Address v4 =>
        cloudflareRangesV4.any((range) => range.contains(v4)),
      final IpV6Address v6 =>
        cloudflareRangesV6.any((range) => range.contains(v6)),
    };
