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

# --- s6

s6/skalibs/config.mak:
	(cd s6/skalibs && ./configure --prefix=${SYSROOT})

s6/skalibs/libskarnet.so.xyzzy: s6/skalibs/config.mak
	(cd s6/skalibs && make ${PARALLEL})

${SYSROOT}/lib/libskarnet.so: s6/skalibs/libskarnet.so.xyzzy | populate-dirs
	(cd s6/skalibs && make install)

s6/execline/config.mak:
	(cd s6/execline && ./configure --prefix=${SYSROOT} \
	--with-include=../skalibs/src/include/ \
	--with-lib=${SYSROOT}/lib \
	--with-lib=${SYSROOT}/lib/skalibs \
	--enable-static-libc)

s6/execline/execlineb: ${SYSROOT}/lib/libskarnet.so s6/execline/config.mak
	(cd s6/execline && make ${PARALLEL})

${SYSROOT}/bin/execlineb: s6/execline/execlineb
	(cd s6/execline && make install)

s6/s6/config.mak:
	(cd s6/s6 && ./configure --prefix=${SYSROOT} \
	--with-include=../skalibs/src/include \
	--with-include=../execline/src/include \
	--with-lib=${SYSROOT}/lib \
	--with-lib=${SYSROOT}/lib/execline \
	--with-lib=${SYSROOT}/lib/skalibs \
	--enable-static-libc)

s6/s6/s6-log: ${SYSROOT}/lib/libskarnet.so ${SYSROOT}/bin/execlineb s6/s6/config.mak
	(cd s6/s6 && make ${PARALLEL})

${SYSROOT}/bin/s6-log:	s6/s6/s6-log
	(cd s6/s6 && make install)

s6/s6-linux-init/config.mak:
	(cd s6/s6-linux-init && ./configure --prefix=${SYSROOT} \
	--enable-absolute-paths \
	--with-include=../skalibs/src/include \
	--with-include=../s6/src/include \
	--with-include=../execline/src/include \
	--with-lib=${SYSROOT}/lib \
	--with-lib=${SYSROOT}/lib/s6 \
	--with-lib=${SYSROOT}/lib/skalibs \
	--enable-static-libc)

s6/s6-linux-init/s6-linux-init: ${SYSROOT}/lib/libskarnet.so ${SYSROOT}/bin/execlineb ${SYSROOT}/bin/s6-log s6/s6-linux-init/config.mak
	(cd s6/s6-linux-init && make ${PARALLEL})

${SYSROOT}/bin/s6-linux-init: s6/s6-linux-init/s6-linux-init
	(cd s6/s6-linux-init && make install)
	-rm -rf ${SYSROOT}/etc/s6-linux-init/skel

s6/s6-rc/config.mak:
	(cd s6/s6-rc && ./configure --prefix=${SYSROOT} \
	--with-include=../skalibs/src/include \
	--with-include=../s6/src/include \
	--with-include=../execline/src/include \
	--with-lib=${SYSROOT}/lib \
	--with-lib=${SYSROOT}/lib/s6 \
	--with-lib=${SYSROOT}/lib/execline \
	--with-lib=${SYSROOT}/lib/skalibs \
	--enable-static-libc)

s6/s6-rc/s6-rc: ${SYSROOT}/lib/libskarnet.so ${SYSROOT}/bin/execlineb ${SYSROOT}/bin/s6-log s6/s6-rc/config.mak
	(cd s6/s6-rc && make ${PARALLEL})

${SYSROOT}/bin/s6-rc: s6/s6-rc/s6-rc
	(cd s6/s6-rc && make install)

${SYSROOT}/etc/s6-linux-init/skel:	etc/s6-linux-init/skel ${SYSROOT}/bin/s6-linux-init
	cp -r $< $@

${SYSROOT}/etc/s6-linux-init/current:	${SYSROOT}/etc/s6-linux-init/skel
	LD_LIBRARY_PATH="${SYSROOT}/lib/" fakeroot-ng s6/s6-linux-init/s6-linux-init-maker -1 -G "/sbin/getty -n -L -l /loginroot 115200 ttyS0 vt100" ${SYSROOT}/etc/s6-linux-init/current
	find $@ -type f -exec sed -i 's|${SYSROOT}||g' {} +

${SYSROOT}/sbin/init: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/init $@

${SYSROOT}/sbin/telinit: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/telinit $@

${SYSROOT}/sbin/shutdown: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/shutdown $@

${SYSROOT}/sbin/halt: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/halt $@

${SYSROOT}/sbin/poweroff: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/poweroff $@

${SYSROOT}/sbin/reboot: ${SYSROOT}/etc/s6-linux-init/current
	cp $</bin/reboot $@

${SYSROOT}/init:	scripts/init
	cp $< $@

.PHONY: .install-s6

.install-s6 : ${SYSROOT}/bin/s6-linux-init ${SYSROOT}/bin/s6-rc ${SYSROOT}/etc/s6-linux-init/current ${SYSROOT}/sbin/init ${SYSROOT}/sbin/telinit ${SYSROOT}/sbin/shutdown ${SYSROOT}/sbin/halt ${SYSROOT}/sbin/poweroff ${SYSROOT}/sbin/reboot ${SYSROOT}/init

initramfs.cpio.xz: ${SYSROOT}/bin/busybox ${SYSROOT}/loginroot ${SYSROOT}/init ${SYSROOT}/etc/inittab ${SYSROOT}/etc/group ${SYSROOT}/etc/passwd .install-modules .install-s6
	(cd ${SYSROOT} && find . -print0 | cpio --null -ov --format=newc | xz -C crc32 > ../initramfs.cpio.xz)

clean::
	-rm -rf initramfs.cpio.xz

distclean::
	rm -rf ${SYSROOT}
