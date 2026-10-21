# Hammerspoon 2

A modernized rewrite of [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) - a powerful macOS application for automating your Mac using JavaScript.

## WARNING

Hammerspoon 2 is currently considered *EXPERIMENTAL*. There may be crashes, memory leaks, bugs, etc. and the JavaScript API may change radically without warning.

## Minimum requirements

Hammerspoon 2 requires macOS 27 or later.

Pre-releases up to (and including) 0.0.6 target macOS 15.6 and support both Apple Silicon and Intel. Later pre-releases up to (and including) 0.0.15 require macOS 26.

## Using Hammerspoon

 * Download one of the pre-releases from GitHub, unzip and place in /Applications
 * Create ~/.config/hammerspoon2/init.js
 * For the JavaScript API docs, see https://cmsj.github.io/Hammerspoon2/ or run hs.docs.show() in the Console window

## Development

### Building

This is an Xcode project. Open `Hammerspoon 2.xcodeproj` in Xcode to build. To generate doc artifacts, run `npm install` in the top level of the repository.

## License

See the LICENSE file for details.

## Acknowledgments

This is a modernized rewrite of the original [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) project.
