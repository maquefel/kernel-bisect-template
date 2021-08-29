# -*- GNUMakefile -*-

# Requirements:
#  /bin/bash as SHELL

export SHELL = /bin/bash

all:    world

#  GNU Make >= 3.82
#  GCC ;)

TARGET_ARCH ?= x86_64

ifndef PARALLEL
ifndef NOPARALLEL
PARALLEL := -j$(shell echo $$((`nproc` + 2)))
endif
endif

KERNEL_TREE ?= ${CURDIR}/linux
SYSROOT ?= ${CURDIR}/initramfs

${SYSROOT}:
	mkdir -p $@

${SYSROOT}/.mount-stamp:	| ${SYSROOT}
	touch $@

.PHONY: world

world:	${SYSROOT}/bin/busybox \
	${SYSROOT}/etc/group \
	${SYSROOT}/etc/passwd \
	${SYSROOT}/etc/inittab \
	${SYSROOT}/init \
	${SYSROOT}/loginroot \
	build-linux/arch/x86_64/boot/bzImage \
	${SYSROOT}/lib/modules \
	initramfs.cpio.xz

# --- kernel

build-linux/arch/x86/configs:
	mkdir -p $@

.PHONY: kernel

build-linux/arch/x86/configs/x86_64_qemu_defconfig: | build-linux/arch/x86/configs configs/x86_64_qemu_defconfig
	cp configs/x86_64_qemu_defconfig $@

build-linux/.config:   | build-linux/arch/x86/configs/x86_64_qemu_defconfig
	make ARCH=${TARGET_ARCH} -C ${KERNEL_TREE} O=${CURDIR}/build-linux x86_64_qemu_defconfig

build-linux/arch/x86_64/boot/bzImage: build-linux/.config
	make ${PARALLEL} -C build-linux ARCH=${TARGET_ARCH} V=1

.PHONY: .install-modules

${SYSROOT}/lib/modules:	build-linux/arch/x86_64/boot/bzImage
	make ${PARALLEL} -C build-linux INSTALL_MOD_PATH=${SYSROOT} modules_install

.install-modules: ${SYSROOT}/lib/modules ${SYSROOT}/.mount-stamp

clean::
	-make ${PARALLEL} -C build-linux clean
	-make ${PARALLEL} -C ${KERNEL_TREE} mrproper
	-rm -rf ${SYSROOT}/lib/modules

distclean::
	-rm -rf build-linux

# --- gpio-tools

build-linux/tools/gpio:
	mkdir -p $@

build-linux/tools/gpio/gpio-event-mon:	build-linux/tools/gpio
	LDFLAGS="-static" make -C linux/tools/gpio/ O=build-linux/tools/gpio

${SYSROOT}/usr/bin/gpio-event-mon:	build-linux/tools/gpio/gpio-event-mon
	make -C linux/tools/gpio/ O=build-linux/tools/gpio DESTDIR=${SYSROOT} install

# --- virtual-gpio-basic

virtual_gpio_basic/vg_get_set:	virtual_gpio_basic/vg_get_set.c virtual_gpio_basic/ivshmem-client.c
	make -C virtual_gpio_basic KDIR=${CURDIR}/build-linux QEMU_DIR=${CURDIR}/qemu

virtual_gpio_basic/virtual_gpio_basic.ko:	virtual_gpio_basic/virtual_gpio_basic.c
	make -C virtual_gpio_basic KDIR=${CURDIR}/build-linux QEMU_DIR=${CURDIR}/qemu modules

.install-virtual-gpio:	virtual_gpio_basic/virtual_gpio_basic.ko virtual_gpio_basic/vg_get_set
	make -C virtual_gpio_basic KDIR=${CURDIR}/build-linux QEMU_DIR=${CURDIR}/qemu modules_install

.PHONY: .install-virtual-gpio

# --- initramfs

CREATE_DIRS := \
        /dev \
        /dev/pts \
        /boot \
        /etc \
        /home \
        /mnt \
        /opt \
        /proc \
        /root \
        /srv \
        /sys \
        /usr \
        /var \
        /var/log \
        /run \
        /tmp \
        /lib

$(patsubst %,${SYSROOT}%,${CREATE_DIRS}):       ${SYSROOT}/.mount-stamp
	install -d -m 0755 $@

.PHONY:	populate-dirs

populate-dirs:	| $(patsubst %,${SYSROOT}%,${CREATE_DIRS})

${SYSROOT}/etc/passwd:	etc/passwd ${SYSROOT}/.mount-stamp | ${SYSROOT}/etc
	install -m 644 $< $@

${SYSROOT}/etc/group:	etc/group ${SYSROOT}/.mount-stamp | ${SYSROOT}/etc
	install -m 644 $< $@

${SYSROOT}/etc/inittab:	etc/inittab ${SYSROOT}/.mount-stamp | ${SYSROOT}/etc
	install -m 644 $< $@

${SYSROOT}/init:	scripts/init | ${SYSROOT}
	install -m 755 $< $@

${SYSROOT}/loginroot:	scripts/loginroot | ${SYSROOT}
	install -m 755 $< $@

# --- busybox

build-busybox:
	mkdir $@

busybox/configs/qemu_defconfig: 	configs/busybox_config
	cp $< $@

build-busybox/.config:	busybox/configs/qemu_defconfig | build-busybox
	make -C busybox O=../build-busybox ARCH=${TARGET_ARCH} qemu_defconfig

build-busybox/busybox:	build-busybox/.config
	make ${PARALLEL} -C build-busybox ARCH=${TARGET_ARCH}

${SYSROOT}/bin/busybox:	build-busybox/busybox | populate-dirs
	make ${PARALLEL} -C build-busybox ARCH=${TARGET_ARCH} CONFIG_PREFIX=${SYSROOT} install
	rm -rf ${SYSROOT}/linuxrc

.PHONY: .install-busybox

.install-busybox : ${SYSROOT}/bin/busybox

clean::
	-make -C build-busybox ARCH=${TARGET_ARCH} clean

distclean::
	rm -rf build-busybox

initramfs.cpio.xz: ${SYSROOT}/bin/busybox ${SYSROOT}/loginroot ${SYSROOT}/init ${SYSROOT}/etc/inittab ${SYSROOT}/etc/group ${SYSROOT}/etc/passwd \
	${SYSROOT}/usr/bin/gpio-event-mon \
	.install-modules .install-virtual-gpio
	(cd ${SYSROOT} && find . -print0 | cpio --null -ov --format=newc | xz -C crc32 > ../initramfs.cpio.xz)

clean::
	-rm -rf initramfs.cpio.xz

distclean::
	rm -rf ${SYSROOT}
