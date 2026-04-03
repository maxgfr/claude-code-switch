#!/bin/sh
# Called by semantic-release to inject the new version into ccs
VERSION="$1"
sed -i "s/^VERSION=\".*\"/VERSION=\"${VERSION}\"/" ccs
