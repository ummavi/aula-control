#!/bin/zsh
# Build a relocatable bundle without installing it or changing privacy grants.
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release -Xswiftc -gnone
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/build/AULA Control.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/AulaControl" "$app_dir/Contents/MacOS/AulaControl"
# Linker debug symbols can retain absolute object paths even with -gnone.
# Strip those from the distributed copy, then sign the final executable.
strip -S "$app_dir/Contents/MacOS/AulaControl"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "$app_dir/Contents/Resources/"
cp Resources/FLEXOKI_LICENSE.txt Resources/ThirdPartyNotices.txt LICENSE "$app_dir/Contents/Resources/"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
