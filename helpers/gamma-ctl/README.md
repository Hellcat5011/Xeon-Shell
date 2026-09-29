# gamma-ctl

A small Wayland client that implements `wlr-gamma-control-unstable-v1` to apply color-temperature changes (blue light filter).
This is built and managed directly by Xeon Shell; it is not a standalone tool meant to be run manually.

## Build Instructions

If you need to recompile the helper, run the following in this directory:

```bash
cargo build --release
```

The QML shell expects the compiled binary to be located at `target/release/gamma-ctl`.
