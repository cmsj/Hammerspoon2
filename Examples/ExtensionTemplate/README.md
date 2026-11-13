# Extension template

A minimal Hammerspoon 2 extension, `com.example.hello`, to copy and build on. See the Extensions
guide in the Hammerspoon 2 documentation for what extensions can do and the rules they follow.

```bash
./build.sh
cp -R build/com.example.hello.hsmodule ~/.config/Hammerspoon2/Extensions/
```

Then turn on **Allow extensions** in the Advanced tab of Hammerspoon 2's Settings, and:

```js
const example = require('ext:com.example.hello')
console.log(example.add(2, 3))
console.log(example.greet('world'))
```

To make it your own, rename:

- the extension, `com.example.hello`: in `build.sh`, `Bundle/Info.plist` (`HSModuleName` and
  `CFBundleIdentifier`), and the name of `Bundle/com.example.hello.js`
- the module's Objective-C class name, `ComExampleHelloModule`: in `ExampleModule.swift` and
  `Bundle/Info.plist` (`NSPrincipalClass`)
- the product, `ExampleExtension`, if you like: in `Package.swift`, `build.sh` and
  `Bundle/Info.plist` (`CFBundleExecutable`)

The package depends on the HammerspoonSDK package for the oldest version of Hammerspoon 2 the
extension should work with; set `HSSDKVersion` in `Bundle/Info.plist` to the SDK version that
release provides (`HSSDK.version`). Build with Xcode 27 or later: Hammerspoon 2 refuses
extensions built with older ones.
