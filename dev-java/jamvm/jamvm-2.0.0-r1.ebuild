# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: /var/cvsroot/gentoo-x86/dev-java/jamvm/jamvm-1.5.4-r2.ebuild,v 1.5 2014/08/10 20:16:11 slyfox Exp $

EAPI=5

inherit eutils flag-o-matic multilib java-vm-2 autotools

DESCRIPTION="An extremely small and specification-compliant virtual machine"
HOMEPAGE="http://jamvm.sourceforge.net/"
SRC_URI="mirror://sourceforge/${PN}/${P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"
IUSE="debug libffi"

DEPEND="dev-java/gnu-classpath:0
	|| ( dev-java/eclipse-ecj:* dev-java/ecj-gcj:* )
	libffi? ( virtual/libffi )
	amd64? ( virtual/libffi )"
RDEPEND="${DEPEND}"

src_prepare() {
	# without this patch, classes.zip is not found at runtime
	epatch "${FILESDIR}/classes-location.patch"
	epatch "${FILESDIR}/noexecstack.patch"
	eautoreconf

	# These come precompiled.
	# configure script uses detects the compiler
	# from PATH. I guess we should compile this from source.
	# Then just make sure not to hit
	# https://bugs.gentoo.org/show_bug.cgi?id=163801
	#
	#rm -v lib/classes.zip || die
}

src_configure() {
	filter-flags "-fomit-frame-pointer"

	if use amd64 || use libffi; then
		append-cflags "$(pkg-config --cflags-only-I libffi)"
	fi

	local fficonf="--enable-ffi"
	use !amd64 && fficonf="$(use_enable libffi ffi)"

	econf ${fficonf} \
		--disable-dependency-tracking \
		$(use_enable debug trace) \
		--libdir="${EPREFIX}"/usr/$(get_libdir)/${PN} \
		--includedir="${EPREFIX}"/usr/include/${PN} \
		--with-classpath-install-dir=/usr
}

create_launcher() {
	local script="${D}/${INSTALL_DIR}/bin/${1}"
	cat > "${script}" <<-EOF
		#!/bin/sh
		exec /usr/bin/jamvm \
			-Xbootclasspath/p:/usr/share/classpath/tools.zip" \
			gnu.classpath.tools.${1}.Main "\$@"
	EOF
	chmod +x "${script}"
}

src_install() {
	local libdir=$(get_libdir)
	local CLASSPATH_DIR=/usr/libexec/gnu-classpath
	local JDK_DIR=/usr/${libdir}/${PN}-jdk

	emake DESTDIR="${D}" install

	dodoc ACKNOWLEDGEMENTS AUTHORS ChangeLog NEWS README

	set_java_env "${FILESDIR}/${PN}.env"

	dodir ${JDK_DIR}/bin
	dosym /usr/bin/jamvm ${JDK_DIR}/bin/java
	for files in ${CLASSPATH_DIR}/g*; do
		if [ $files = "${CLASSPATH_DIR}/bin/gjdoc" ] ; then
			dosym $files ${JDK_DIR}/bin/javadoc || die
		else
			dosym $files \
				${JDK_DIR}/bin/$(echo $files|sed "s#$(dirname $files)/g##") || die
		fi
	done

	dodir ${JDK_DIR}/jre/lib
	dosym /usr/share/classpath/glibj.zip ${JDK_DIR}/jre/lib/rt.jar
	dodir ${JDK_DIR}/lib
	dosym /usr/share/classpath/tools.zip ${JDK_DIR}/lib/tools.jar

	local ecj_jar="$(readlink "${EPREFIX}"/usr/share/eclipse-ecj/ecj.jar)"
	exeinto ${JDK_DIR}/bin
	cat "${FILESDIR}"/javac.in | sed -e "s#@JAVA@#/usr/bin/jamvm#" \
		-e "s#@ECJ_JAR@#${ecj_jar}#" \
		-e "s#@RT_JAR@#/usr/share/classpath/glibj.zip#" \
		-e "s#@TOOLS_JAR@#/usr/share/classpath/tools.zip#" \
	| newexe - javac

	local libarch="${ARCH}"
	[ ${ARCH} == x86 ] && libarch="i386"
	[ ${ARCH} == x86_64 ] && libarch="amd64"
	dodir ${JDK_DIR}/jre/lib/${libarch}/client
	dodir ${JDK_DIR}/jre/lib/${libarch}/server
	dosym /usr/${libdir}/${PN}/libjvm.so ${JDK_DIR}/jre/lib/${libarch}/client/libjvm.so
	dosym /usr/${libdir}/${PN}/libjvm.so ${JDK_DIR}/jre/lib/${libarch}/server/libjvm.so
	dosym /usr/${libdir}/classpath/libjawt.so ${JDK_DIR}/jre/lib/${libarch}/libjawt.so

	# Can't use java-vm_set-pax-markings as doesn't work with symbolic links
	# Ensure a PaX header is created.
	local pax_markings="C"
	# Usally disabeling MPROTECT is sufficent.
	local pax_markings+="m"
	# On x86 for heap sizes over 700MB disable SEGMEXEC and PAGEEXEC as well.
	use x86 && pax_markings+="sp"

	pax-mark ${pax_markings} "${ED}"/usr/bin/jamvm
}
