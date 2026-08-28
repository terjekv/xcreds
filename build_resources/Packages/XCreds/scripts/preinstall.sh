#!/bin/sh

target_path="${2:-/}"
application_path="${target_path%/}/Applications/XCreds.app"

/usr/bin/killall XCreds >/dev/null 2>&1 || true

if [ -d "${application_path}" ]; then
    /bin/rm -rf "${application_path}"
fi
