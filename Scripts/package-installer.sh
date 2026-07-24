#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/dist/CoupleMon.app"
pkg_path="$project_dir/dist/CoupleMon.pkg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/couplemon-pkg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT

"$project_dir/Scripts/package-app.sh" >/dev/null
version=$(plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist")
mkdir -p "$staging_dir/root"
cp -R "$app_dir" "$staging_dir/root/CoupleMon.app"
pkgbuild --analyze --root "$staging_dir/root" "$staging_dir/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$staging_dir/components.plist"
plutil -replace 0.BundleHasStrictIdentifier -bool YES "$staging_dir/components.plist"

rm -f "$pkg_path"
pkgbuild \
    --root "$staging_dir/root" \
    --component-plist "$staging_dir/components.plist" \
    --install-location /Applications \
    --identifier com.couplemon.app.installer \
    --version "$version" \
    "$pkg_path"

echo "$pkg_path"
