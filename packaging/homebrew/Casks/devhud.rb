cask "devhud" do
  version "0.3.1"
  sha256 "cf8c95c21dfd63203da25d3ab235c0dd1cd0bd99c7721e3fe03d4f17579b2556"

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
