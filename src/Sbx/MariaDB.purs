module Sbx.MariaDB (profile) where

import Prelude
import Data.Maybe (Maybe(..))
import Data.String as String
import Data.Tuple.Nested ((/\))
import Foreign.Object as Object
import Sbx.Profile (ClientCmd(..), FancyCmd(..), Os(..), Profile, shellQuote, withBsdPath)

profile :: Profile
profile =
  { tool: "mariadb-sbx"
  , product: "MariaDB"
  , guestPort: 3306
  , defaultTag: "11"
  , image: \tag -> if String.contains (String.Pattern "/") tag || String.contains (String.Pattern ":") tag then tag else "mariadb:" <> tag
  , hasCredentials: true
  , defaults: { user: "root", password: "mariadb", db: "mariadb" }
  , dataDir: case _ of
      Linux -> "/var/lib/mysql"
      FreeBSD -> "/var/db/mysql"
      NetBSD -> "/var/mysql"
  , rootfsVolume: false
  , env: \c -> Object.fromFoldable $
      [ "MARIADB_ROOT_PASSWORD" /\ c.password
      , "MARIADB_DATABASE" /\ c.db
      ] <> (if c.user == "root" then [] else [ "MARIADB_USER" /\ c.user, "MARIADB_PASSWORD" /\ c.password ])
  , command: Nothing
  , provision: case _ of
      Linux -> Nothing
      FreeBSD -> Just freebsd
      NetBSD -> Just netbsd
  -- `ping` exits 0 whenever a server answers, even with "access denied";
  -- during the image's first-boot initialisation the temporary server has no
  -- TCP listener, so this stays false until the real one is up.
  , ready: \_ _ -> withBsdPath "mariadb-admin ping -h 127.0.0.1 --silent"
  , client: Guest \_ c -> withBsdPath ("mariadb -h 127.0.0.1 -u " <> shellQuote c.user <> " -p" <> shellQuote c.password <> " " <> shellQuote c.db)
  , clientName: "mariadb"
  , fancy: { name: "mycli", cmd: HostTool \c port -> [ "mycli", url c port ] }
  , url
  , studioSupported: const true
  , dialect: "mysql"
  , driver: "mysql2"
  , migrations: Nothing
  }

url :: { user :: String, password :: String, db :: String } -> Int -> String
url c port = "mysql://" <> c.user <> ":" <> c.password <> "@127.0.0.1:" <> show port <> "/" <> c.db

-- Idempotent: install once, let the rc script initialise the data directory
-- on its first start, then make sure the requested user (reachable over TCP
-- from the host) and database exist. root@localhost keeps its socket auth.
sql :: String
sql = String.joinWith "\n"
  [ "mariadb -u root <<SQL"
  , "CREATE USER IF NOT EXISTS '$SBX_USER'@'%' IDENTIFIED BY '$SBX_PASSWORD';"
  , "ALTER USER '$SBX_USER'@'%' IDENTIFIED BY '$SBX_PASSWORD';"
  , "GRANT ALL PRIVILEGES ON *.* TO '$SBX_USER'@'%' WITH GRANT OPTION;"
  , "CREATE DATABASE IF NOT EXISTS \\`$SBX_DB\\`;"
  , "FLUSH PRIVILEGES;"
  , "SQL"
  ]

waitSocket :: String
waitSocket = "i=0; until mariadb-admin ping --silent >/dev/null 2>&1 || [ $i -ge 60 ]; do sleep 1; i=$((i+1)); done"

freebsd :: String
freebsd = String.joinWith "\n"
  [ "set -e"
  , "export PATH=/usr/local/bin:/usr/local/sbin:$PATH"
  , "pkg info -e mariadb114-server >/dev/null 2>&1 || env ASSUME_ALWAYS_YES=yes pkg install -y mariadb114-server"
  , "sysrc mysql_enable=YES >/dev/null"
  , "mkdir -p /usr/local/etc/mysql/conf.d"
  , "printf '[mysqld]\\nbind-address = 0.0.0.0\\n' > /usr/local/etc/mysql/conf.d/sbx.cnf"
  , "chown mysql:mysql /var/db/mysql"
  , "service mysql-server status >/dev/null 2>&1 || service mysql-server start >/dev/null"
  , waitSocket
  , sql
  ]

netbsd :: String
netbsd = String.joinWith "\n"
  [ "set -e"
  , "export PATH=/usr/pkg/bin:/usr/pkg/sbin:$PATH"
  , "pkg_info -qE 'mariadb-server-[0-9]*' >/dev/null 2>&1 || pkgin -y install mariadb-server"
  , "cp -f /usr/pkg/share/examples/rc.d/mysqld /etc/rc.d/mysqld"
  , "grep -q '^mysqld=YES' /etc/rc.conf || echo 'mysqld=YES' >> /etc/rc.conf"
  , "[ -f /usr/pkg/etc/my.cnf ] || printf '[mysqld]\\nbind-address = 0.0.0.0\\n' > /usr/pkg/etc/my.cnf"
  , "grep -q 'bind-address' /usr/pkg/etc/my.cnf || printf '[mysqld]\\nbind-address = 0.0.0.0\\n' >> /usr/pkg/etc/my.cnf"
  , "chown mysql:mysql /var/mysql"
  , "/etc/rc.d/mysqld status >/dev/null 2>&1 || /etc/rc.d/mysqld start >/dev/null"
  , waitSocket
  , sql
  ]
