wimboot: Windows Imaging Format bootloader for GRUB2
====================================================

This is an enhanced fork of [iPXE's wimboot](https://github.com/ipxe/wimboot/) with support for GRUB2.

Changes in this fork
--------------------

* Support loading the initrd via the EFI LoadFile2 protocol (from [a1ive's PR](https://github.com/ipxe/wimboot/pull/49)), so GRUB's modern `linux`/`initrd` commands work on EFI.
* Bumped the Linux boot protocol version in the bzImage prefix to 2.12 and populated the required header fields (`xloadflags`, `handover_offset`, etc.) so GRUB no longer rejects wimboot with *kernel too old* or *kernel doesn't support EFI handover*.
* Added a position-independent x86_64 EFI handover stub that reconstructs the full PE image from `boot_params` and the GRUB-loaded payload, then hands it to EFI `LoadImage`/`StartImage` so PE relocations are applied correctly. This makes the legacy `linuxefi`/`initrdefi` path work too.

[`wimboot`][wimboot] is a boot loader for Windows Imaging Format `.wim` files. It enables you to boot into a [Windows PE (WinPE)][winpe] deployment or recovery environment.

You can use `wimboot` with [iPXE][ipxe] to [boot Windows PE via HTTP][howto]. With a Gigabit Ethernet network, a typical WinPE image should download in just a few seconds.

Demo
----

This animation shows an HTTP network boot into the Windows 10 installer. The total elapsed time from power on to reaching the Windows installer screen is 17 seconds.

![Demo animation](doc/demo.gif)

Advantages
----------

### Speed

`wimboot` can download images at the full speed supported by your network, since it can use HTTP rather than TFTP.

### Ease of use

`wimboot` works directly with `.wim` image files; there is no need to wrap your `.wim` into an ISO or FAT filesystem image.

### BIOS/UEFI compatibility

`wimboot` allows you to use a single configuration and set of files to boot under both BIOS and UEFI environments.

License
-------

`wimboot` is free software licensed under the [GNU General Public License](LICENSE.txt).

Quickstart
----------

See https://ipxe.org/wimboot for instructions.

Grub Entry
----------

Extract the following files from your installation source (i.e. a Windows ISO) into a directory under GRUB's root, alongside the compiled wimboot binary:

```
boot/bcd
boot/boot.sdi
efi/boot/bootx64.efi
sources/boot.wim
```

Unlike iPXE, GRUB does not understand the `newc:name:/path` syntax — it will treat the whole string as a file name. The files must instead be packed into a single newc-format CPIO archive that GRUB loads as the initrd. Create it on the server with:

```
cd /path/to/wimboot/files
printf 'bcd\nboot.sdi\nboot.wim\nbootx64.efi\n' | cpio -o -H newc > initrd.img
```

The file names inside the archive must match what wimboot looks for (`bcd`, `boot.sdi`, `*.wim`, `bootx64.efi` / `bootia32.efi` / `bootaa64.efi`), so run `cpio` from the directory containing the files and feed it bare names (no `./` prefix, no subdirectories).

Then add a menu entry using the modern `linux`/`initrd` commands:

```
menuentry "wimboot" {
    linux /src/wimboot
    initrd /src/initrd.img
}
```

On EFI systems, prefer `linux`/`initrd` over `linuxefi`/`initrdefi`: the former uses EFI `LoadImage`/`StartImage` and passes the initrd via the LoadFile2 protocol, which matches the code paths enabled in this fork. The legacy `linuxefi`/`initrdefi` commands also work thanks to the EFI handover stub, but are no longer required.

[wimboot]: https://ipxe.org/wimboot
[ipxe]: https://ipxe.org
[winpe]: https://en.wikipedia.org/wiki/Windows_Preinstallation_Environment
[howto]: https://ipxe.org/howto/winpe
