# Copyright 1999-2018 Gentoo Foundation
# Copyright 2016-2018 Digital Integrity GmbH
# Distributed under the terms of the GNU General Public License v2

# This script is based on: sys-fs/btrfs-progs-separated-4.17.1.ebuild

EAPI=6

inherit fcaps user

libbtrfs_soname=0

if [[ ${PV} != 9999 ]]; then
	MY_PN="btrfs-progs"
	MY_PV="v${PV/_/-}"
	[[ "${PV}" = *_rc* ]] || \
	KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~ia64 ~mips ~ppc ~ppc64 ~sparc ~x86"
	SRC_URI="https://www.kernel.org/pub/linux/kernel/people/kdave/${MY_PN}/${MY_PN}-${MY_PV}.tar.xz"
	S="${WORKDIR}"/${MY_PN}-${MY_PV}
else
	WANT_LIBTOOL=none
	inherit autotools git-r3
	EGIT_REPO_URI="https://github.com/kdave/btrfs-progs.git"
	EGIT_BRANCH="devel"
fi

DESCRIPTION="Distinct suid/fscaps binaries for specific btrfs subcommands"
HOMEPAGE="https://btrfs.wiki.kernel.org"

LICENSE="GPL-2"
SLOT="0/${libbtrfs_soname}"
IUSE="adduser btrbk-snapshot btrbk-source btrbk-target btrbk-delete +btrbk-info"

RESTRICT=test # tries to mount repared filesystems

RDEPEND="
	sys-apps/util-linux:0=
	!sys-fs/btrfs-progs-separated
"
DEPEND="${RDEPEND}"

if [[ ${PV} == 9999 ]]; then
	DEPEND+=" sys-devel/gnuconfig"
fi

PATCHES=(
	"${FILESDIR}"/cmds-separated-fscaps-v2.patch
)

declare -A INSTALL_FCAPS

# Hint: "make list-fscaps | sed -nr 's/^([a-z-]+)=(.*)$/\[\1\]="\2"/p'"
INSTALL_FCAPS=(
	[btrfs-send]="cap_sys_admin,cap_fowner,cap_dac_read_search"
	[btrfs-receive]="cap_sys_admin,cap_fowner,cap_chown,cap_mknod,cap_setfcap,cap_dac_override,cap_dac_read_search"
	[btrfs-subvolume-list]="cap_sys_admin,cap_fowner,cap_dac_read_search"
	[btrfs-subvolume-show]="cap_sys_admin,cap_fowner,cap_dac_read_search"
	[btrfs-subvolume-snapshot]="cap_sys_admin,cap_fowner,cap_dac_override,cap_dac_read_search"
	[btrfs-subvolume-delete]="cap_sys_admin,cap_dac_override"
	[btrfs-filesystem-usage]="cap_sys_admin"
	[btrfs-qgroup-destroy]="cap_sys_admin,cap_dac_override"
)

pkg_setup() {
	[ -z "${BTRFS_PROGS_SEPARATED_GROUP_NAME}" ] && BTRFS_PROGS_SEPARATED_GROUP_NAME=btrfs
	einfo "Using group \"${BTRFS_PROGS_SEPARATED_GROUP_NAME}\" for separated btrfs commands."
	enewgroup ${BTRFS_PROGS_SEPARATED_GROUP_NAME}

	[ -z "${BTRBK_USER_NAME}" ] && BTRBK_USER_NAME=btrbk
	BTRBK_USER_HOME=/home/${BTRBK_USER_NAME}
	BTRBK_USER_SH=/bin/bash
	use adduser && enewuser "${BTRBK_USER_NAME}" -1 "${BTRBK_USER_SH}" "${BTRBK_USER_HOME}" "${BTRFS_PROGS_SEPARATED_GROUP_NAME}"

	BTRFS_PROGS_INSTALL=( btrfs-subvolume-show  btrfs-subvolume-list )
	use btrbk-source   && BTRFS_PROGS_INSTALL+=( btrfs-subvolume-snapshot btrfs-send )
	use btrbk-target   && BTRFS_PROGS_INSTALL+=( btrfs-receive )
	use btrbk-snapshot && BTRFS_PROGS_INSTALL+=( btrfs-subvolume-snapshot )
	use btrbk-delete   && BTRFS_PROGS_INSTALL+=( btrfs-subvolume-delete )
	use btrbk-info     && BTRFS_PROGS_INSTALL+=( btrfs-filesystem-usage )
}

src_prepare() {
	default
	if [[ ${PV} == 9999 ]]; then
		AT_M4DIR=m4 eautoreconf
		mkdir config || die
		local automakedir="$(autotools_run_tool --at-output automake --print-libdir)"
		[[ -e ${automakedir} ]] || die "Could not locate automake directory"
		ln -s "${automakedir}"/install-sh config/install-sh || die
		ln -s "${EPREFIX}"/usr/share/gnuconfig/config.guess config/config.guess || die
		ln -s "${EPREFIX}"/usr/share/gnuconfig/config.sub config/config.sub || die
	fi
}

src_configure() {
	local myeconfargs=(
		--bindir="${EPREFIX}"/usr/bin
		--disable-documentation
		--disable-convert
		$(use_enable elibc_glibc backtrace)
	)
	econf "${myeconfargs[@]}"
}

src_compile() {
	emake V=1 ${BTRFS_PROGS_INSTALL[@]/%/.separated}
}

src_install() {
	# this would install all binaries, regardless of use flags:
	#emake V=1 DESTDIR="${D}" install-fscaps "${makeargs[@]}"

	for obj in ${BTRFS_PROGS_INSTALL[@]}; do
		newbin "${obj}.separated" "${obj}"
		fowners root:${BTRFS_PROGS_SEPARATED_GROUP_NAME} "/usr/bin/${obj}"
	done
}

pkg_postinst() {
	for obj in ${BTRFS_PROGS_INSTALL[@]}; do
		fcaps -g ${BTRFS_PROGS_SEPARATED_GROUP_NAME} -m 4710 -M 0710 "${INSTALL_FCAPS[$obj]}" "${EROOT}/usr/bin/${obj}"
	done

	if ! use adduser; then
		ewarn "NOTE: If you want to run the separated programs with elevated privileges"
		ewarn "you have to add yourself to the ${BTRFS_PROGS_SEPARATED_GROUP_NAME} group."
	fi

	if use adduser; then
		einfo "Example ssh configuration (${BTRBK_USER_HOME}/.ssh/authorized_keys):"
		einfo "   from=\"192.168.0.42\",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding <pubkey>"
	fi
}
