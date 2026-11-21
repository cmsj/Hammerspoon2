cask "hammerspoon2" do
  # version and sha256 are bumped by .github/workflows/homebrew-cask.yml on each release
  version "0.0.17"
  sha256 "728817fb0954c1ea9d55267a5449abc759d987f4caa1e51f595f1e4b437ad1e0"

  url "https://github.com/cmsj/Hammerspoon2/releases/download/#{version}/Hammerspoon-2-#{version}.zip"
  name "Hammerspoon 2"
  desc "Desktop automation application driven by JavaScript"
  homepage "https://github.com/cmsj/Hammerspoon2"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle keeps the app up to date itself
  auto_updates true
  depends_on macos: :golden_gate

  app "Hammerspoon 2.app"
  binary "#{appdir}/Hammerspoon 2.app/Contents/MacOS/hs2"

  zap trash: [
    "~/.config/Hammerspoon2",
    "~/Library/Caches/net.tenshu.Hammerspoon-2",
    "~/Library/HTTPStorages/net.tenshu.Hammerspoon-2",
    "~/Library/Preferences/net.tenshu.Hammerspoon-2.plist",
  ]
end
