# Stress-relief Sound Watcher

Watcher tự động **mở / đóng** app `/Applications/Stress-relief.app` theo trạng thái
**Background Sounds** (Âm thanh nền) mà user bật/tắt trong System Settings của macOS.

## Nguyên lý hoạt động

macOS lưu trạng thái Background Sounds trong preferences:

- Domain: `com.apple.ComfortSounds`
- Key: `comfortSoundsEnabled` (`1` = bật, `0` = tắt)

Watcher (chạy ngầm vĩnh viễn qua LaunchAgent) poll key này mỗi **2 giây**
và duy trì bất biến sau:

> **App đang chạy  ⇔  `comfortSoundsEnabled == 1`**

- User bật Background Sounds → watcher tự `open` app.
- User tắt Background Sounds → watcher tự quit app (graceful trước, SIGTERM fallback).

## Cấu trúc thư mục

```
/Applications/Stress-relief/            ← repo nguồn (git)
├── Stress-relief/                      ← source Swift của app Touch Bar
├── Stress-relief.xcodeproj/
└── sound-watcher/                      ← THƯ MỤC CỦA WATCHER (mọi thứ ở đây)
    ├── README.md                       ← file này
    ├── com.gimmick.stress-relief-comfort-follow.plist  ← bản chính của LaunchAgent
    ├── Stress-relief Sound Watcher.app/ ← bundle watcher (executable = bash script)
    │   └── Contents/
    │       ├── Info.plist              (bundle id: com.gimmick.stress-relief-sound-watcher)
    │       ├── MacOS/                  (script watcher chính)
    │       └── Resources/AppIcon.icns
    ├── icon/
    │   ├── make-icon.swift             ← script sinh icon (CoreGraphics)
    │   ├── AppIcon-1024.png            ← icon gốc 1024px
    │   ├── AppIcon.icns                ← icon đã build (cũng được gắn vào app chính)
    │   └── AppIcon.iconset/            ← bộ png 16→1024
    └── legacy/
        └── comfort-watcher-v1.sh       ← phiên bản script đầu tiên (đã thay bằng bundle)

~/Library/LaunchAgents/com.gimmick.stress-relief-comfort-follow.plist
    ← bản copy của plist trong repo (launchd CHỈ đọc từ đây)
~/Library/Logs/stress-relief-watcher.log
    ← log hoạt động (tự truncate khi vượt 200 KB)
```

> **Lưu ý:** file trong `~/Library/LaunchAgents/` là bản *triển khai*; muốn sửa cấu hình
> thì sửa bản trong repo rồi copy qua và restart agent (xem bên dưới).

## Cài đặt / Gỡ cài đặt

```bash
# Cài (sau khi đã có plist tại ~/Library/LaunchAgents/)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gimmick.stress-relief-comfort-follow.plist

# Gỡ (dừng watcher ngừng ngặt)
launchctl bootout gui/$(id -u)/com.gimmick.stress-relief-comfort-follow

# Khi sửa plist (cả 2 bản) → restart agent
launchctl bootout gui/$(id -u)/com.gimmick.stress-relief-comfort-follow
cp /Applications/Stress-relief/sound-watcher/com.gimmick.stress-relief-comfort-follow.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gimmick.stress-relief-comfort-follow.plist

# Kiểm tra đang chạy
launchctl list | grep comfort
pgrep -fl "Stress-relief Sound Watcher"
```

## Các mode của watcher executable

Executable của bundle là bash script, hỗ trợ các mode để test mà không cần đụng app:

```bash
W="/Applications/Stress-relief/sound-watcher/Stress-relief Sound Watcher.app/Contents/MacOS/Stress-relief Sound Watcher"

# (không tham số) — vòng lặp vĩnh viễn, LaunchAgent chạy mode này
"$W"

# Chỉ đọc state 1 lần, ghi log hành động SẼ làm, KHÔNG đụng app, thoát
"$W" --dry-run

# Đọc state từ file thay vì defaults (dùng để test logic)
echo 1 > /tmp/comfort-sounds-state
"$W" --mock /tmp/comfort-sounds-state

# Đóng app ngay rồi thoát
"$W" --quit
```

## Test thủ công

1. **System Settings → Accessibility → Audio → Background Sounds** → bật/tắt toggle.
2. Xem log phản ứng:

```bash
tail -20 ~/Library/Logs/stress-relief-watcher.log
```

Log mẫu:

```
2026-10-24 17:57:32 state init -> 0
2026-10-24 17:57:32 background-sounds OFF: app already not running
2026-10-24 18:02:15 state 0 -> 1
2026-10-24 18:02:15 background-sounds ON: launched app
```

## Icon

Icon của app **vẽ bằng code** (CoreGraphics trong `make-icon.swift` — nền gradient
teal→xanh đêm, thanh equalizer + sóng âm trắng, **không dùng emoji**):

```bash
cd /Applications/Stress-relief/sound-watcher/icon
swift make-icon.swift AppIcon-1024.png
# resize các size chuẩn rồi:
iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns /Applications/Stress-relief.app/Contents/Resources/
```

## Troubleshooting

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| App không mở khi bật sound | Xem log; check `launchctl list \| grep comfort` còn chạy không |
| Watcher không tự khởi động sau reboot | Plist phải nằm ở `~/Library/LaunchAgents/`, không phải thư mục khác |
| Icon không cập nhật trong Finder | `touch /Applications/Stress-relief.app` rồi mở lại app; nếu vẫn cũ thì `killall Finder` |
| Bootstrap lỗi `5: Input/output error` | Thường là lỗi tạm thời khi bootout chạy cùng lúc → bootstrap lại |
| Log phình to | Tự truncate ở 200 KB; kiểm tra `stat -f %z ~/Library/Logs/stress-relief-watcher.log` |

## Trạng thái hoàn thiện (`final-version-main`)

Toàn bộ 16 cảnh 8-bit — bao gồm **BABBLE** (bản vẽ Kandinsky với bảng màu O(1) `32,768` màu và gradient khởi tạo sẵn), **STEAM** (cô gái anime 8-bit nháy mắt giữa 5 tầng khói suối khoáng tím đêm), và **OCEAN** (bãi biển bình minh 3 tầng sóng, 5 cá mập, 10 sao biển và 2 chú tôm trên cát) — đã được hoàn tất và tối ưu hóa CPU/GPU/Pin.

## Watcher bundle nhận diện trong Login Items

Bundle có tên riêng **"Stress-relief Sound Watcher"** và bundle id
`com.gimmick.stress-relief-sound-watcher`, nên dễ phân biệt với các agent khác của user
(khác với label LaunchAgent `com.gimmick.stress-relief-comfort-follow` — label chỉ dùng nội bộ launchd).
