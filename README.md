# QEMU PCI VIRTUAL GPIO QUICKSTART

Quickstart for building and testing virtual gpio module for use togather with qemu.

## INIT

$ git submodule --init --recursive

## COMPILE

Simply run:

```
$ make
```

ivshmem-server is build as a separate target togather with qemu just in case you are tinkering qemu elsewhere:

```
$ make qemu/build/contrib/ivshmem-server/ivshmem-server
```

## LAUNCHING

```
$ ./qemu/build/contrib/ivshmem-server/ivshmem-server -F -v -l 1M -n 1
$ qemu-system-x86_64 -cpu host -kernel build-linux/arch/x86/boot/bzImage -initrd initramfs.cpio.xz -nographic -append "nokaslr console=ttyS0 root=/dev/ram" -chardev socket,path=/tmp/ivshmem_socket,id=ivshmemid -device ivshmem-doorbell,chardev=ivshmemid,vectors=1 -enable-kvm
```

