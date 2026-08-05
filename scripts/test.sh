#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc Tests/DesktopSessionMonitorTests.swift Sources/DesktopSessionMonitor.swift Sources/StatusPolicy.swift -o build/tests/DesktopSessionMonitorTests -framework Cocoa
build/tests/DesktopSessionMonitorTests
