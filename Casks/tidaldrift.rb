cask "tidaldrift" do
  version "1.4.3"
  sha256 "b94bc4ccd3aedec1cbc1de92d10b30a4c096c5f94acc05f885f99cffc24d16d9"

  url "https://github.com/goldberg-consulting/measured.one.tidal-drift/releases/download/v#{version}/TidalDrift-#{version}.dmg"
  name "TidalDrift"
  desc "Menu-bar Mac utility for discovering, connecting to, and streaming between Macs on your local network"
  homepage "https://github.com/goldberg-consulting/measured.one.tidal-drift"

  depends_on macos: ">= :ventura"

  app "TidalDrift.app"

  zap trash: [
    "~/Library/Preferences/com.goldbergconsulting.tidaldrift.plist",
    "~/Library/Application Support/TidalDrift",
  ]
end
