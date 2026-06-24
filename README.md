# ModKit

Native macOS Modbus TCP client. No dependencies, no Electron, no Java — just a lean SwiftUI app built on Network.framework.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Features

### Scanner (Modbus Master)
- Connect to any Modbus TCP device by IP, port, and Unit ID
- Read Holding Registers (FC03), Input Registers (FC04), Coils (FC01), Discrete Inputs (FC02)
- Write single register via FC06 (double-click any row or right-click → Write)
- Binary column shows each bit with its position number (15 → 0) highlighted in real time
- Auto-poll with configurable interval (ms)
- Sortable table — click any column header
- Connection timeout (8 s) with Cancel button
- Last used IP / port / Unit ID saved automatically

### Simulator (Modbus Slave)
- Spin up a local Modbus TCP server on any port
- 2 000 holding registers, pre-seeded with sample data
- Responds to FC03 reads and FC06/FC10 writes
- Live register editor — change any value and it is immediately visible to connecting masters

---

## Install

### Option A — Download (recommended)

1. Download the latest `ModKit-vX.X.X-macOS.zip` from [Releases](../../releases)
2. Unzip and drag **ModKit.app** to `/Applications`
3. First launch — macOS will block it (app is ad-hoc signed, not notarized):
   - **macOS 14 / 15:** go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway**
   - **macOS 13:** right-click the app → **Open** → **Open**

> If you see "ModKit is damaged and can't be opened", run this in Terminal:
> ```
> xattr -cr /Applications/ModKit.app
> ```

### Option B — Build from source

```bash
# Requires Xcode 15+ installed
git clone https://github.com/RodriguesMarllon/ModKit.git
cd ModKit
make run          # builds Release, installs to ~/Applications, and opens
```

Other make targets:

```
make build        # build only (Release, into DerivedData)
make install      # build + copy to ~/Applications/ModKit.app
make run          # install + open
make clean        # remove DerivedData and ~/Applications/ModKit.app
```

---

## Why

Every Modbus diagnostic tool I could find was either Windows-only (ModScan32, Modbus Poll), requires a JVM, or costs money. ModKit is free, native, and runs on Apple Silicon.

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (build from source only)

---

## License

MIT
