<img src="assets/icon.svg" width="64" height="64" alt="">

# OpenSwipe

A macOS app that switches apps and windows with trackpad swipes. A three-finger horizontal swipe opens an app switcher like Cmd-Tab; a four-finger swipe opens a switcher for the active app's windows. The switcher follows your fingers, and lifting them switches.

**Status:** early development. The three-finger App Switcher and the four-finger Window Switcher with window previews work, including Live Switching, and a Settings screen with English and Russian text. See the [specification](docs/spec.md) for the plan.

## Build and run

Requires macOS 26 or later, Xcode, [mise](https://mise.jdx.dev) and [Just](https://just.systems).

1. Create a self-signed code-signing certificate named `OpenSwipe Development` in your login keychain. Keychain Access → Certificate Assistant → Create a Certificate…, with the type set to Code Signing. A stable certificate keeps macOS's Accessibility grant across rebuilds.
2. Build and launch:

   ```sh
   just run
   ```

3. Grant OpenSwipe Accessibility access when asked.

Logs are written to `~/Library/Logs/OpenSwipe`. Run `just --list` for the other commands.

## Documentation

- [Specification](docs/spec.md)
- [Glossary](GLOSSARY.md)
- [Architecture decisions](docs/adr)

## License

[MIT](LICENSE)
