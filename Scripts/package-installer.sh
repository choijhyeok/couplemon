#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/dist/CoupleMon.app"
pkg_path="$project_dir/dist/CoupleMon.pkg"

"$project_dir/Scripts/package-app.sh" >/dev/null
version=$(plutil -extract CFBundleShortVersionString raw "$app_dir/Contents/Info.plist")

rm -f "$pkg_path"
pkgbuild \
    --component "$app_dir" \
    --install-location /Applications \
    --identifier com.couplemon.app.installer \
    --version "$version" \
    "$pkg_path"

echo "$pkg_path"
