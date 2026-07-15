# Kế hoạch cải tiến Clawstatus — sửa các vấn đề nghiêm trọng

Phạm vi: chỉ sửa bug và tăng độ ổn định. Không thêm tính năng mới
(launch-at-login, lưu vị trí HUD, cảnh báo ngưỡng… nằm ngoài phạm vi).

Trạng thái: ☐ chưa làm · ☑ hoàn thành

---

## Giai đoạn 1 — Bug nghiêm trọng (làm trước)

### ☑ 1. Claude CLI fetch không có timeout — có thể treo toàn bộ app

- **File:** `macos/Sources/ClawlineCore/UsageClient.swift` (`ClaudeUsageCommand.run`, ~dòng 205)
- **Vấn đề:** `process.waitUntilExit()` không có deadline. Nếu `claude` treo
  (auth prompt, node stall, chờ mạng), continuation không bao giờ resume →
  `refresh()` không return → `isRefreshing` kẹt `true` vĩnh viễn → vòng poll
  60 giây dừng hẳn, menu bar hiển thị dữ liệu cũ cho tới khi relaunch.
- **Cách sửa:**
  - Thêm timeout 30 giây (Claude CLI khởi động chậm hơn Codex nên dài hơn 12s
    của Codex): dùng `DispatchWorkItem` hẹn giờ gọi `process.terminate()` và
    resume continuation với `UsageError.claudeCommandFailed("Timed out")`.
  - Đảm bảo continuation chỉ resume đúng một lần (guard bằng lock/flag như
    `CodexProcessState.finish`).
  - Hỗ trợ hủy tác vụ qua `withTaskCancellationHandler` giống mô hình
    `CodexProcessBox` để đồng nhất hai provider.
- **Kiểm chứng:** thay tạm đường dẫn executable bằng script `sleep 300`,
  xác nhận refresh trả lỗi sau 30s và lần poll kế tiếp vẫn chạy.

### ☑ 2. Codex binary chết → mỗi poll đợi đủ 12 giây

- **File:** `macos/Sources/ClawlineCore/UsageClient.swift` (`CodexProcessState`)
- **Vấn đề:** không set `process.terminationHandler`. Nếu `codex` thoát ngay
  (bản cũ chưa có `app-server`, cài đặt hỏng) thì không có output, mỗi poll
  chờ trọn 12 giây timeout.
- **Cách sửa:**
  - Set `process.terminationHandler` trong `start(...)`: khi process thoát mà
    chưa `completed`, gọi `finish(.failure(.codexCommandFailed("Codex exited (status N)")))`.
  - Chuyển timeout từ `asyncAfter` closure sang `DispatchWorkItem` lưu trong
    state, gọi `cancel()` trong `finish(...)` — hiện closure giữ `state`
    (process + pipes) sống thêm 12 giây sau cả khi fetch đã thành công.
- **Kiểm chứng:** trỏ tạm candidate tới `/usr/bin/false`, xác nhận lỗi trả về
  gần như ngay lập tức thay vì sau 12 giây.

### ☑ 3. "Updated Xs ago" hiển thị số giây thô + badge "Live" sai với cache cũ

- **File:** `macos/Sources/Clawline/HUDView.swift` (`footerText`, ~dòng 216)
  và `macos/Sources/Clawline/UsageStore.swift` (init, ~dòng 35)
- **Vấn đề:**
  - Sau khi Mac ngủ dậy hoặc hiển thị snapshot cache từ hôm trước, footer in
    "Updated 43200s ago".
  - Khi launch từ cache, `connectionState = .live` ngay lập tức → badge xanh
    "Live" dù dữ liệu đã cũ nhiều giờ, trước cả khi poll đầu tiên xong.
- **Cách sửa:**
  - Format thời gian tương đối theo bậc: `<60s` → "Xs ago", `<60m` → "Xm ago",
    còn lại → "Xh ago" (hoặc dùng `RelativeDateTimeFormatter`).
  - Thêm case `.cached` vào `ConnectionState`; khi init từ cache dùng
    `.cached`, chỉ chuyển `.live` sau lần fetch thành công đầu tiên. Badge
    hiển thị "Cached" màu secondary.
- **Kiểm chứng:** cập nhật `ClawlineCheck` nếu tách hàm format ra
  `ClawlineCore`; test thủ công bằng cách sửa `capturedAt` trong
  `~/Library/Application Support/Clawstatus/state.json` lùi 1 ngày rồi mở app.

### ☑ 4. Version bị hardcode trùng lặp 3 nơi

- **File:** `macos/Sources/ClawlineCore/UsageClient.swift` (`fetch(appVersion: String = "0.4.0")`)
- **Vấn đề:** version nằm ở cả code, `Info.plist`, và Cask. Mỗi lần release
  phải sửa tay cả ba, dễ trôi lệch.
- **Cách sửa:** ở app target, đọc
  `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`
  và truyền xuống `CodexUsageClient.fetch(appVersion:)`; đổi default trong
  core thành giá trị trung tính (vd. `"unknown"`). Cask giữ version riêng vì
  bắt buộc. Lưu ý: khi chạy `swift run` (không có bundle Info.plist) phải
  fallback an toàn.
- **Kiểm chứng:** `swift run --package-path macos ClawlineCheck` vẫn pass;
  build app và xác nhận Codex fetch vẫn hoạt động.

---

## Giai đoạn 2 — Độ ổn định

### ☑ 5. Không có backoff khi provider lỗi liên tục

- **File:** `macos/Sources/Clawline/UsageStore.swift` (`pollContinuously`)
- **Vấn đề:** khi cả hai CLI không cài, app vẫn spawn process `claude` (node)
  mỗi 60 giây vô hạn.
- **Cách sửa:** backoff lũy tiến khi cả hai provider cùng thất bại:
  60s → 120s → 240s → tối đa 300s; reset về 60s ngay khi có một fetch thành
  công hoặc người dùng bấm "Refresh now".
- **Kiểm chứng:** gỡ tạm cả hai CLI khỏi candidates, quan sát khoảng cách
  giữa các lần poll tăng dần (thêm log tạm hoặc dùng os.Logger từ mục 6).

### ☑ 6. Parse lỗi thì "câm lặng" — không phân biệt nguyên nhân, không log

- **File:** `macos/Sources/ClawlineCore/UsageClient.swift`,
  `macos/Sources/Clawline/UsageStore.swift` (`message(for:provider:)`)
- **Vấn đề:** khi Claude CLI đổi format text của `/usage`, parser fail và user
  chỉ thấy "Claude unavailable" — không có manh mối gì. Không có logging ở
  bất kỳ đâu nên bug report của user không dùng được.
- **Cách sửa:**
  - `message(for:)` phân biệt `usageOutputInvalid` / `codexOutputInvalid`:
    "Claude output format changed — update Clawstatus".
  - Thêm `os.Logger` (subsystem `com.clawstatus`, category theo provider) log
    loại lỗi ở mức `.error`. **Tuân thủ AGENTS.md: chỉ log tên loại lỗi,
    tuyệt đối không log nội dung report/response** (có thể chứa thông tin
    tài khoản như email, plan).
- **Kiểm chứng:** cho parser nhận input rác, xem message trong HUD và log
  qua `log stream --predicate 'subsystem == "com.clawstatus"'`.

### ☑ 7. Giờ reset của Claude bỏ qua timezone trong report

- **File:** `macos/Sources/ClawlineCore/UsageClient.swift`
  (`ClaudeUsageParser.resetDate`, ~dòng 291)
- **Vấn đề:** report ghi `resets Jul 14 at 3:29pm (Asia/Saigon)` nhưng parser
  dùng `TimeZone.current` và vứt phần trong ngoặc. Nếu CLI cấu hình timezone
  khác hệ thống, countdown sẽ lệch nhiều giờ.
- **Cách sửa:** tách chuỗi trong `(...)`, thử `TimeZone(identifier:)`; nếu hợp
  lệ thì dùng cho formatter, không thì fallback `.current` như hiện tại.
- **Kiểm chứng:** thêm case vào `ClawlineCheck` với report ghi timezone khác
  timezone máy, assert `resetsAt` đúng theo timezone trong report.

---

## Thứ tự thực hiện đề xuất

1. Mục 1 và 2 làm chung một nhánh (cùng file, cùng mô hình process-handling).
2. Mục 3 (UI/state) độc lập, làm riêng.
3. Mục 4 nhỏ, có thể gộp vào bất kỳ nhánh nào.
4. Mục 6 làm trước mục 5 (backoff cần log để kiểm chứng).
5. Mục 7 độc lập, kèm test trong `ClawlineCheck`.

Sau mỗi mục:

```bash
swift run --package-path macos ClawlineCheck
./macos/scripts/build-app.sh && open macos/dist/Clawstatus.app
```

Commit theo AGENTS.md: message ngắn, thể mệnh lệnh, một vấn đề một commit
(vd. `Add timeout to Claude usage command`).
