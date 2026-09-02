// Hammerspoon 2 configuration
//
// This file is loaded on startup, and reloaded whenever you choose "Reload Config"
// from the menu bar icon.
//
// Full API documentation: https://cmsj.github.io/Hammerspoon2
// You can also browse it locally at any time with: hs.docs.show()
//
// See also:
// - https://cmsj.github.io/Hammerspoon2/main/js/getting-started.html
// - https://cmsj.github.io/Hammerspoon2/main/js/migration-guide.html

hs.notify.show("Hammerspoon 2", "Config loaded successfully.")

// Example: bind cmd+alt+h to show a notification.
// Uncomment the lines below and reload your config to try it out.
//
// const helloHotkey = hs.hotkey.bind(["cmd", "alt"], "h", () => {
//   hs.notify.show("Hammerspoon 2", "Hello from your config!")
// })
//
// Note: capture the return value in a variable that lives as long as your config
//       does, otherwise it will simply stop firing after the next garbage collection.