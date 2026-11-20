# mariadb-sbx

MariaDB in a [bsdkrun](https://github.com/tsirysndr/bsdkrun) microVM, with
**branchable data**: the data directory is a ZFS branch you fork copy-on-write,
switch between, and throw away, like `git branch` for your database. Drizzle
Studio, drizzle-kit, the `mariadb` client and [mycli](https://www.mycli.net)
are all wired to it.

```sh
mariadb-sbx start                  # boots MariaDB 12 in a VM, port 3306 on 127.0.0.1
mariadb-sbx checkout -b feature    # fork the data, mount the fork
mariadb-sbx drizzle push           # try a schema change on it
mariadb-sbx studio                 # look at it in Drizzle Studio
mariadb-sbx checkout main          # back to the untouched data
mariadb-sbx branch -d feature      # done with it
```

One sandbox per tool: a VM named `mariadb-sbx`, a ZFS volume named
`mariadb-sbx`, and a small state file under `~/.config/mariadb-sbx`. The server
runs inside the VM; everything else (Studio, drizzle-kit, mycli) runs on the
host and talks to it over a forwarded port.

Written in PureScript on the [bsdkrun PureScript
SDK](https://github.com/tsirysndr/bsdkrun-purescript). Siblings:
[postgres-sbx](../postgres-sbx) and [sqlite-sbx](../sqlite-sbx) share the same
code and commands.

## Requirements

| What | Why |
| --- | --- |
| [bsdkrun](https://github.com/tsirysndr/bsdkrun#install) 0.12 or newer | runs the VM and the ZFS volume (`brew install tsirysndr/tap/bsdkrun`) |
| macOS on Apple Silicon, or Linux with KVM | what bsdkrun supports |
| Node.js 22 or newer | runs the tool, drizzle-kit and Studio |
| `uv` or `pipx` (optional) | runs `mycli` without installing it by hand |

`mariadb-sbx doctor` checks all of it.

## Install

From a checkout, with the
[bsdkrun-purescript](https://github.com/tsirysndr/bsdkrun-purescript) SDK next
to it (see `spago.yaml` to point at the git repository instead):

```sh
npm install        # also builds (spago)
npm link           # puts `mariadb-sbx` on your PATH
mariadb-sbx doctor
```

### Single binary

```sh
npm run build:bin  # needs bun; writes dist/mariadb-sbx
```

The binary bundles the tool, the SDK and the `mysql2` driver. drizzle-kit
cannot be bundled (it ships esbuild's native binary and runs as its own
process), so `studio` and `drizzle` look for a `drizzle-kit` on PATH when run
from the binary: `npm i -g drizzle-kit drizzle-orm mysql2`. mycli is an
external tool either way.

## Commands

```
start      Start the sandbox, creating the VM and its data volume on first run
stop       Stop the VM (data stays on its branch)
status     Show the VM, the mounted branch and the connection URL
ssh        Open a shell in the VM (alias: shell)
log        Show the VM console log, -f to follow (alias: logs)
branch     List data branches, create one (copy-on-write) or delete one
checkout   Switch the data directory to BRANCH, -b to create it first (alias: switch)
mariadb    Open the mariadb client on the sandbox database
mycli      Open mycli (auto-completion, syntax highlighting) on the sandbox database
url        Print the connection URL
studio     Open Drizzle Studio on the sandbox database
drizzle    Run drizzle-kit with DATABASE_URL pointing at the sandbox
doctor     Check bsdkrun, the hypervisor, Node, drizzle-kit and mycli
destroy    Remove the VM and the data volume with every branch (asks first)
```

Every command has `--help`.

## Starting

```sh
mariadb-sbx start                               # linux, mariadb:12
mariadb-sbx start linux 10.11                   # any tag of the mariadb image
mariadb-sbx start linux ghcr.io/you/maria:dev   # or a full image reference
mariadb-sbx start freebsd 15.1                  # MariaDB 11.4 from pkg
mariadb-sbx start netbsd                        # MariaDB from pkgsrc
mariadb-sbx start --user app --password secret --db shop
```

| Option | Default | |
| --- | --- | --- |
| `--port, -p PORT` | 3306 | host port forwarded to the server; change it on a later start (the VM is recreated, the data stays) |
| `--user NAME` | root | user reachable from the host, with all privileges |
| `--password SECRET` | mariadb | its password (also root's) |
| `--db NAME` | mariadb | database created on first start |
| `--cpus N` | 2 | changeable on a later start |
| `--mem MIB` | 1024 | changeable on a later start |
| `--branch, -b BRANCH` | the current one | data branch to mount |
| `--size SIZE` | 10G | data volume size when it is created (sparse) |

The first `start` creates the volume and the VM and waits for the server to
accept TCP connections (the image's first-boot initialisation is detected and
waited out). Later starts resume the same VM; the OS, version and credentials are fixed
for the life of the sandbox (`destroy` to change them), while `--port`,
`--cpus` and `--mem` can be changed on any start.
Credentials and the database are applied when a data branch is first
initialised: on Linux through the image's `MARIADB_*` environment, on BSD by
the provisioning script.

On FreeBSD and NetBSD the first start installs the server with `pkg` /
`pkgin`, lets the rc script initialise the data branch, binds it to all
interfaces, and creates the user (`'user'@'%'`) and database; root keeps its
socket login. The same script runs on every start and is idempotent. These
guests are scripted but have had less exercise than Linux; `mariadb-sbx log`
shows what happened.

## Branches

The data directory lives on a ZFS branch inside the sandbox's volume. Branches
are ZFS clones: forking is instant and costs nothing until the branches diverge.

```sh
mariadb-sbx branch                  # list; * marks the mounted one (also: branch ls)
mariadb-sbx branch staging          # fork the current branch (no switch)
mariadb-sbx branch hotfix --from main
mariadb-sbx checkout staging        # stop, remount, start: ~40s on Linux
mariadb-sbx checkout -b try-this    # fork and switch in one go
mariadb-sbx branch -d try-this      # delete (also: branch rm NAME); not main, not the mounted one
```

`checkout` restarts the server on the other branch, so connections drop. A
branch keeps everything its parent had at fork time, users included. Forking
while the VM is stopped boots a short-lived FreeBSD helper to do it (about 15
seconds).

## Drizzle Studio and drizzle-kit

Both run on the host, from this package's `node_modules`.

```sh
mariadb-sbx studio                  # https://local.drizzle.studio, server on 127.0.0.1:4983
mariadb-sbx studio --port 5000 --host 0.0.0.0
mariadb-sbx drizzle push            # drizzle-kit push against the sandbox
mariadb-sbx drizzle generate
mariadb-sbx drizzle migrate
```

`drizzle` runs drizzle-kit in the current directory with `DATABASE_URL` set to
the sandbox (`mysql://user:password@127.0.0.1:3306/db`), so a project's
`drizzle.config.ts` can read `process.env.DATABASE_URL`. If the directory has
no drizzle config, one that points at the sandbox is supplied
(`~/.config/mariadb-sbx/drizzle.config.ts`, dialect `mysql`, no schema).

## Clients

```sh
mariadb-sbx mariadb                 # the mariadb client inside the VM, already logged in
mariadb-sbx mycli                   # mycli on the host via uvx or pipx, URL filled in
mariadb-sbx url                     # mysql://root:mariadb@127.0.0.1:3306/mariadb
mariadb-sbx ssh                     # a shell in the VM
```

## Where things live

| | |
| --- | --- |
| `~/.config/mariadb-sbx/state.json` | OS, version, port, credentials, branch, resources |
| `~/.config/mariadb-sbx/drizzle.config.ts` | written by `studio` / `drizzle` |
| `bsdkrun ps -a`, `bsdkrun zfs ls mariadb-sbx` | the VM and the volume, bsdkrun's own records |
| `/var/lib/mysql` (Linux), `/var/db/mysql` (FreeBSD), `/var/mysql` (NetBSD) | the branch's mountpoint in the guest |

`mariadb-sbx destroy` removes all of it after confirmation (`--yes` to skip).

## Troubleshooting

- `mariadb-sbx doctor` — bsdkrun, the hypervisor, Node, drizzle-kit, mycli.
- `mariadb-sbx log -f` — the guest console; `log --boot` for bsdkrun's own boot log when a VM dies early.
- `mariadb-sbx status` — whether the server accepts connections on the forwarded port.
- A VM named `mariadb-sbx` that the tool did not create: `bsdkrun rm -f mariadb-sbx`.

## Development

```sh
npm install
npm test            # unit tests (profile, argv)
npm run build
node bin/mariadb-sbx.js --help
```

`src/Sbx/MariaDB.purs` is the MariaDB profile: image, ports, credentials, data
directory, provisioning scripts, readiness probe, clients, drizzle dialect.
`Sbx.App`, `Sbx.Cli`, `Sbx.Native`, `Sbx.State` and `Sbx.Profile` are shared
verbatim with postgres-sbx and sqlite-sbx.

MIT license.
