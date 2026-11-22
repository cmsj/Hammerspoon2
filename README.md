# Hammerspoon 2

## What is Hammerspoon?

This is a tool for powerful automation of macOS. At its core, Hammerspoon is just a bridge between the operating system and a JavaScript scripting engine.

What gives Hammerspoon its power is a set of modules that expose specific pieces of system functionality, to the user. With these, you can write JavaScript to control many aspects of your macOS environment.

The first version of Hammerspoon used Lua for its scripting engine, this is a modernized rewrite that uses the same JavaScript engine as Safari.

## Minimum requirements

Hammerspoon 2 requires macOS 27 or later.

## How do I install it?

### Manually

 * Download the [latest release](https://github.com/Hammerspoon/Hammerspoon2/releases/latest)
 * Drag `Hammerspoon 2.app` from your `Downloads` folder to `/Applications`

### Homebrew

 * TBC

## Getting Started

 * If you are new to Hammerspoon, read our Getting Started Guide (link TBD)
 * If you are coming from the original Hammerspoon, see our Migration Guide (link TBD)
 * Full API documentation can be found here (link TBD), or by running `hs.docs.show()` in the Hammerspoon Console window.

## Getting Help

 * There are multiple places you can communicate with other users: (links TBD)
   * GitHub Discussions
   * [Discord](https://discord.gg/vxchqkRbkR)
   * [Reddit](https://www.reddit.com/r/Hammerspoon)
 * If you find a bug in Hammerspoon, or want to request a new feature, please file an issue (link TBD)

## Development

### Building

This is an Xcode project. Open `Hammerspoon 2.xcodeproj` in Xcode to build. To generate doc artifacts, run `npm install` in the top level of the repository.

The code is linted with [SwiftLint](https://github.com/realm/SwiftLint) (rules in `.swiftlint.yml`), which runs as a Swift package build tool plugin. The first time you build, Xcode asks you to trust and enable `SwiftLintBuildToolPlugin`. Command line builds need the same approval, or `-skipPackagePluginValidation` passed to `xcodebuild`.

## License

See the LICENSE file for details.

## Acknowledgments

This is a modernized rewrite of the original [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) project, and builds on projects such as:
 * [AXSwift](https://github.com/mredig/AXSwift)
 * [javascriptcore-extras](https://github.com/mhayes853/javascript-core-extras)
 * [swift-commandlinekit](https://github.com/objecthub/swift-commandlinekit)
