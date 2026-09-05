cask "devhud" do
  version "0.3.1"
  sha256 "8915b6fdcdd3cb0cb481a9cf3987e32a9f7113606c11061e3aaef08cbad35e26"

  url "https://github.com/zacker3310/devHUD/releases/download/v#{version}/devHUD-#{version}.zip"
  name "devHUD"
  desc "Side-notch HUD for AI usage rings and local dev servers"
  homepage "https://github.com/zacker3310/devHUD"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "devHUD.app"

  # Non-admin Macs: brew install --cask --appdir=~/Applications devhud
  # (or export HOMEBREW_CASK_OPTS="--appdir=~/Applications").
  # The app registers its login item at whatever path it runs from.

  uninstall quit:       "cloud.acker.devhud",
            login_item: "devHUD"

  zap trash: [
    "~/Library/Logs/devHUD",
    "~/Library/Preferences/cloud.acker.devhud.plist",
  ]
end
