# my_system

Rebuild my laptop (Dell Precision 7770) from zero: Fedora 44 + Sway 1.12 + DMS, encrypted disk, drivers, apps and configs.

## Build the installer ISO

```sh
toolbox run -c iso ~/Projects/my_system/install/build-iso.sh
```

Makes the ISOs in `~/VMs/fedora-iso/`: `install/ks-dualboot.cfg` (free space only, Windows kept) and `install/ks.cfg` (erases the disk).

## Install

Boot the ISO with Secure Boot off and answer the questions. After the first login the personal setup runs by itself.

## Apply

```sh
./apply.sh system      # system part
./apply.sh home toolbox nvim   # personal part
```

## Layout

- `apply.sh`: idempotent setup
- `home/`: dotfiles, scripts and services linked into `~`
- `etc/`: system files
- `install/`: kickstarts and VM tests
- `nvim-setup/`, `toolbox/`, `show-desktop/`
