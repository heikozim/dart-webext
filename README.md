# dart-webext

A shared Dart library for building browser extensions. It puts the
extension APIs of Chrome and Firefox behind one backend interface, so
extension logic is written once, tested without a browser against a
fake, and compiled per target with dart2js.

Formerly `dart-heikozim`; renamed 2026-09-02, same history and tags.

## Modules

- `browserkit` -- the backend seam. One interface, three
  implementations: `browserkit_chrome.dart`, `browserkit_firefox.dart`
  (hand-bound against pinned Firefox schemas), and
  `browserkit_fake.dart` for browserless tests.
- `netkit` -- header classification and Cloudflare detection.
- `statekit` -- per-tab capture state.
- `fmtkit` -- formatting; absence is a value, nothing throws.

Each library file names the seam it belongs to and the decision behind
it; the architecture notes and the ADRs are kept with the development
repository.

## Building

Dart SDK >= 3.5 (developed with 3.13.2). The library ships no
compiled artifacts; consumers compile it into their own output.

    dart pub get
    dart analyze

The test suite and the browser proof harness are kept with the
development repository, not here.

## Development

Development happens in a private repository; this public repository
carries the tagged release states.

## License

BSD-3-Clause; the full text is in `LICENSE`. Every source file
carries an `SPDX-License-Identifier: BSD-3-Clause` line.

The library depends on `chrome_extension` (BSD-2-Clause) and
`package:web` (BSD-3-Clause) from pub.dev; nothing is vendored into
this tree.

Copyright (C) 2026 Heiko Zimmermann <addon@heiko-zimmermann.com>
