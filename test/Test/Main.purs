module Test.Main where

import Prelude
import Bsdkrun.Options as Options
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import Foreign.Object as Object
import Sbx.MariaDB (profile)
import Sbx.Profile (Os(..))

main :: Effect Unit
main = do
  let c = profile.defaults
  unless (profile.url "12" c 3306 == "mysql://root:mariadb@127.0.0.1:3306/mariadb") $ throw "url"
  unless (profile.image "12" == "mariadb:12" && profile.image "mariadb:10.11-jammy" == "mariadb:10.11-jammy") $ throw "image"
  unless (profile.dataDir Linux == "/var/lib/mysql") $ throw "data dir"
  unless (Object.size (profile.env c) == 2) $ throw "root env"
  unless (Object.size (profile.env { user: "app", password: "x", db: "app" }) == 4) $ throw "user env"
  let args = Options.buildCreateArgs (Options.linux (profile.image "12") # Options.withZfs [ "mariadb-sbx@main:/var/lib/mysql" ])
  unless (args == [ "linux", "mariadb:12", "-d", "--zfs", "mariadb-sbx@main:/var/lib/mysql" ]) $ throw "zfs args"
  log "mariadb-sbx tests passed"
