#Maintainer: solisinvictum https://github.com/solisinvictum/borgrestore
pkgname="borgrestore-git"
pkgver="0.1"
pkgrel="0.1"
pkgdesc="Puts the system in exactly the same state as it is in a Borg snapshot."
arch=("any")
source=("git+https://github.com/solisinvictum/borgrestore.git")
sha512sums=("SKIP")
depends=(git borg python-llfuse)
optdepends=('vorta: a nice Borg GUI')

package() {

  mkdir -p "${pkgdir}/usr/bin"
  cp "${srcdir}/borgrestore/borgrestore" "${pkgdir}/usr/bin/borgrestore"
  chmod +x "${pkgdir}/usr/bin/borgrestore"

  mkdir -p "${pkgdir}/etc/borgrestore"
  cp "${srcdir}/borgrestore/borgrestore.conf" "${pkgdir}/etc/borgrestore/borgrestore.conf"

}
