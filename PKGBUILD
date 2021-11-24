pkgname="borgrestore-git"
pkgver="0.1"
pkgrel="0.1"
pkgdesc="Puts the system in exactly the same state as it is in a Borg snapshot."
arch=("any")
source=("git+https://github.com/solisinvictum/borgrestore")
sha512sums=("SKIP")
depends=(git borg)
optdepends=('vorta: a nice Borg GUI')

package() {

mkdir -p "${pkgdir}/usr/bin"
cp "${srcdir}/borgrestore/borgrestore" "${pkgdir}/usr/bin/borgrestore"
chmod 644 "${pkgdir}/usr/bin/borgrestore"
chmod +x "${pkgdir}/usr/bin/borgrestore"

mkdir -p "${pkgdir}/etc/borgrestore"
cp "${srcdir}/borgrestore/borgrestore.conf" "${pkgdir}/etc/borgrestore/borgrestore.conf"
chmod 644 "${pkgdir}/etc/borgrestore/borgrestore.conf"
chmod +x "${pkgdir}/etc/borgrestore/borgrestore.conf"

}
