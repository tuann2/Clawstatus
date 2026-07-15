# Kế hoạch tính năng Clawstatus — provider settings, Antigravity và widget

Mục tiêu: cho phép người dùng chọn provider muốn theo dõi, chuẩn bị nền tảng
cho provider mới (Antigravity) và cải thiện trải nghiệm hiển thị. Không làm yếu
các nguyên tắc hiện tại: dependency-free, không đọc/lưu/log credential, chỉ
cache snapshot usage đã chuẩn hóa.

Trạng thái: ☐ chưa làm · ◐ cần spike/quyết định · ⛔ blocked · ☑ hoàn thành

## Kết luận review

| Hạng mục | Mức ưu tiên | Độ phức tạp | Khuyến nghị |
| --- | --- | --- | --- |
| Chọn provider trong Settings | Bắt buộc | Thấp–trung bình | Làm đầu tiên, ship trong 0.5.0 |
| Giao diện widget-style trong app | Nên làm | Thấp–trung bình | Gộp vào bản 0.5.0 |
| Antigravity CLI usage | **NO-GO hiện tại** | Trung bình–cao | Milestone riêng, chờ upstream |
| WidgetKit thật trên desktop | Nice to have | Cao | Blocked trên quyết định Developer ID |

### Antigravity: NO-GO tại thời điểm review (07/2026)

Đã probe trực tiếp `agy` **1.1.2** (bản cài local, thay cho probe 1.0.16 cũ):

- Không có subcommand `usage`/`quota`. Subcommand hiện có: agent, changelog,
  help, install, models, plugin, update.
- Không có flag JSON/headless nào cho quota. Cách non-interactive duy nhất là
  `-p/--print`, nhưng flag này **chạy prompt qua agent** — khác bản chất với
  `claude -p /usage` (lệnh local, không gọi model). Poll `agy -p "/usage"` mỗi
  60 giây sẽ tiêu tốn quota để đo quota và nhận output do model sinh tự do.
- Upstream: issue [google-antigravity/antigravity-cli#46][agy-46] (open,
  05/2026) báo `/stats` hỏng, không có interface máy đọc, chưa có phản hồi
  maintainer. Forum Google báo `/usage` [hiển thị sai 100%][agy-wrong] và
  [chỉ cập nhật sau khi restart][agy-stale].

Theo đúng điều kiện NO-GO ở mục 0.2: kế hoạch mặc định **không** chứa
Antigravity trong 0.5.0. Giai đoạn 2 giữ làm milestone riêng, chỉ mở lại khi
upstream cung cấp contract máy đọc được.

### WidgetKit: blocked trên quyết định signing

WidgetKit không chỉ là đổi SwiftUI view. SwiftPM không build được Widget
Extension (`.appex`) — bắt buộc chuyển sang Xcode project — và macOS 15+ siết
App Group entitlement (group phải prefix Team ID; ad-hoc signing sẽ bị prompt
hoặc hoạt động không ổn định). Thực tế giai đoạn 4 **yêu cầu Apple Developer
ID + notarization**; quyết định mua Developer ID nên là hạng mục độc lập vì nó
đồng thời xóa caveat `xattr` quarantine trong Cask. Widget desktop cũng là
trải nghiệm macOS 14+, trong khi app hỗ trợ macOS 13. Giai đoạn 3
(widget-style trong floating panel) đã cover phần lớn giá trị người dùng.

---

## Giai đoạn 0 — Chuẩn hóa kiến trúc

### ☑ 0.1. Chuẩn hóa mô hình provider

- Thêm `UsageProvider`: `.claude`, `.codex` (và `.antigravity` dự phòng) với
  `id`, tên hiển thị, ký hiệu menu bar (`C`, `X`, `A`) và màu mặc định.
- Tránh tiếp tục nhân đôi/ba các biến `snapshot/state/client`. Chuyển
  `UsageStore` sang registry theo provider:
  - snapshot đã chuẩn hóa;
  - trạng thái `loading/live/cached/unavailable/disabled`;
  - timestamp và lỗi an toàn để hiển thị.
- Mô hình window giữ tối giản: `label`, `usedPercent`, `resetsAt` tùy chọn.
  **Không** thêm quota dạng số lượng (`remainingValue/totalValue`) khi chưa có
  provider thật cần đến — Antigravity đang NO-GO nên mở rộng model lúc này là
  over-engineering.
- Cache: **giữ nguyên** hai file `state.json`/`codex-state.json` và Codable
  shape hiện tại; provider mới thêm file riêng (`<provider>-state.json`).
  Không cần format hợp nhất, không cần migration.

**Kiểm chứng:** Claude và Codex hiển thị đúng như trước; `ClawlineCheck` pass
với cache cũ nguyên trạng.

### ☑ 0.2. Gộp process-runner chung

- Sau các fix trong `docs/PLAN.md` (mục 1 và 2), Claude và Codex đều có logic
  timeout, cancellation và completion exactly-once gần giống nhau. Tách thành
  một helper chung (kiểu `CLIProcessRunner`) trong `ClawlineCore`:
  executable candidates, timeout cấu hình được, terminationHandler, drain
  stdout/stderr, exactly-once finish.
- Provider mới sau này dùng lại helper thay vì copy-paste lần thứ ba.

**Kiểm chứng:** `ClawlineCheck` pass; test thủ công timeout (executable giả
`sleep`) và binary thoát sớm (`/usr/bin/false`) cho cả hai provider.

### ◐ 0.3. Antigravity feasibility gate — điều kiện mở lại Giai đoạn 2

Trạng thái hiện tại: **NO-GO** (xem Kết luận review). Điều kiện GO, tất cả
phải đạt:

1. Có một trong các contract được upstream hỗ trợ:
   - flag JSON/headless cho quota;
   - subcommand quota riêng;
   - file cache quota được tài liệu hóa và không chứa credential;
   - API công khai dành cho quota cá nhân.
2. **Lệnh không gọi model và không tiêu tốn quota** — poll định kỳ mỗi 60 giây
   không được làm hao quota người dùng.
3. Output xác định (deterministic), parse được mà không cần credential, không
   tạo/chỉnh session hoặc settings của người dùng.
4. Test trên ít nhất hai phiên bản CLI với các trạng thái: signed in, signed
   out, quota bình thường, quota hết hạn.
5. Chốt fixture đã ẩn danh và schema mapping trước khi viết parser.

Ràng buộc bất biến: không đọc keyring/token/file auth/log của Antigravity;
không dùng PTY/TUI screen scraping trong production. Khi chưa GO, nếu muốn
nhắc tới Antigravity trong UI thì chỉ hiển thị "Open `/usage` in Terminal".

---

## Giai đoạn 1 — Settings chọn provider

### ☑ 1.1. Lưu lựa chọn provider

- Lưu một `Set<UsageProvider>` (hoặc từng key bool) trong `UserDefaults` qua
  `UIPreferences`.
- Mặc định bật Claude và Codex để không thay đổi hành vi người dùng cũ.
- Cache của provider bị tắt vẫn giữ trên disk để có thể bật lại, nhưng không
  hiển thị và không được tính vào trạng thái tổng.

### ☑ 1.2. Giao diện Settings

- Thêm nút bánh răng ở footer và mục `Providers` trong context menu.
- Settings tối thiểu là các toggle "Show Claude Code usage" / "Show Codex
  usage" (Antigravity chỉ xuất hiện khi gate 0.3 đạt GO).
- Dùng popover nhỏ thay vì settings window lớn; phù hợp với app
  accessory/menu-bar hiện tại.
- Cho phép tắt tất cả, nhưng hiển thị empty state "Enable a provider in
  Settings" và **dừng hẳn `pollingTask`** thay vì báo Offline; restart
  pollingTask khi bật lại provider đầu tiên.

### ☑ 1.3. Áp dụng lựa chọn vào polling và UI

- Provider bị tắt không được spawn CLI process.
- Bật provider phải fetch ngay; tắt provider phải ẩn ngay. Dùng generation
  token/counter theo provider để bỏ qua kết quả của fetch đang chạy nếu
  provider đã tắt giữa chừng.
- Backoff (đã có từ `docs/PLAN.md` mục 5) chỉ xét các provider đang bật; một
  provider disabled không được tính là failure.
- **Chính sách menu bar label (đã chốt):**
  - 1–2 provider bật: hiển thị như hiện tại, ví dụ `C 76% · X 47%`;
  - **cả 3 provider bật: chỉ hiển thị Claude** (`C 76%`) để giữ menu bar gọn;
    chi tiết đầy đủ xem trong HUD;
  - tắt tất cả: hiển thị icon app thay cho `—%`.
- `menuLabel`, HUD, availability message, cache timestamp và panel resize chỉ
  xét provider đang bật.
- Trạng thái tổng phải tránh "Live" gây hiểu nhầm: hiển thị status theo từng
  provider trong card; badge tổng chỉ là summary.

**Kiểm chứng:** test đủ 4 tổ hợp bật/tắt Claude/Codex (8 tổ hợp khi có
Antigravity), persistence sau relaunch, không spawn binary bị tắt, bật lại
fetch ngay, panel resize đúng và menu bar label đúng chính sách trên.

---

## Giai đoạn 2 — Antigravity CLI provider (milestone riêng, đang NO-GO)

⛔ Blocked: chỉ bắt đầu khi gate 0.3 đạt **GO**. Không gắn vào release 0.5.0.
Nội dung dưới đây giữ làm thiết kế sẵn để dùng khi upstream có contract.

### ☐ 2.1. Process lifecycle

- Dò executable theo thứ tự:
  `/opt/homebrew/bin/agy`, `/usr/local/bin/agy`, `~/.local/bin/agy`
  (xác nhận lại đường dẫn cài đặt thực tế trong spike).
- Dùng command contract đã chốt ở gate; không khởi tạo project/session và
  không thay đổi settings Antigravity.
- Dùng `CLIProcessRunner` chung từ mục 0.2 (timeout khởi điểm 20 giây,
  cancellation, exactly-once, drain stdout/stderr); không log raw output.

### ☐ 2.2. Parser và snapshot

- Parse danh sách quota theo model thay vì giả định chỉ có 5-hour/7-day.
  Nếu contract trả quota dạng số lượng thay vì phần trăm, đây là lúc mở rộng
  model window (đã hoãn ở mục 0.1).
- Chuẩn hóa tên model, remaining/used, reset time và timezone nếu có.
- Menu bar: theo chính sách đã chốt ở 1.3 — khi cả 3 provider bật, Antigravity
  không xuất hiện trên menu bar, chỉ trong HUD.
- Không tự suy ra phần trăm khi thiếu total; không hiển thị số giả khi không
  có quota máy đọc được.
- Cache riêng `antigravity-state.json`, chỉ chứa normalized snapshot.
- Thêm `UsageError` riêng và message phân biệt not installed, signed out,
  unsupported output, timeout.

### ☐ 2.3. UI và logging

- Thêm section `Antigravity` dùng danh sách meter động theo model.
- Màu riêng, accessibility label và compact layout không bị tràn khi có nhiều
  model; giới hạn số window hiển thị và có summary nếu cần.
- Logger category `Antigravity`, chỉ log loại lỗi; không log model response,
  account, plan, quota raw hoặc token.

**Kiểm chứng:** fixture hợp lệ/không hợp lệ, nhiều model, thiếu reset, timeout,
cancellation, binary thoát sớm, signed out; Claude/Codex vẫn hoạt động độc lập
khi Antigravity lỗi.

---

## Giai đoạn 3 — Chuyển UI hiện tại sang widget-style

Nên làm trong bản 0.5.0 vì không cần app extension.

### ☑ 3.1. Card theo provider

- Mỗi provider là một card/section có icon, tên, trạng thái riêng và meter.
- Header chung chỉ giữ tên app, summary freshness và nút Settings.
- Full mode ưu tiên khả năng đọc; Compact mode hiển thị một summary row cho
  mỗi provider đang bật.
- Khi một provider lỗi nhưng provider khác live, provider lỗi phải có badge
  `Cached`/`Unavailable` ngay trong section thay vì chỉ có footer bị cắt.

### ☑ 3.2. Layout động

- Tách `ProviderUsageCard`, `UsageMetricRow`, `ProviderStatusBadge` để dùng lại
  giữa floating panel, MenuBarExtra và WidgetKit sau này.
- Cập nhật `HUDContentShape` để theo dõi provider/metric động thay vì hai field
  Claude/Codex cố định.
- Đặt chiều cao tối đa và scroll chỉ khi thật sự cần; tránh panel vượt màn
  hình khi một provider có nhiều meter.
- Giữ double-click Compact, opacity và context menu hiện tại.

**Kiểm chứng:** checklist thủ công (repo chưa có test infra UI) cho các tổ hợp
0/1/2 provider, compact/full, cached/error, màn hình nhỏ. Hỗ trợ Dynamic Type
là hạng mục riêng ngoài phạm vi 0.5 — font trong `HUDView` đang hardcode size,
làm đúng là một thay đổi lớn hơn một tiêu chí kiểm chứng.

---

## Giai đoạn 4 — WidgetKit thật trên macOS (nice to have)

⛔ Blocked trên quyết định **Apple Developer ID + notarization** (xem Kết luận
review). Không bắt đầu 4.2–4.4 trước khi 4.1 chốt.

### ◐ 4.1. Decision gate về build và signing

- Quyết định mua Apple Developer Program ($99/năm). Lợi ích kép: notarization
  xóa caveat quarantine trong Cask, và là điều kiện thực tế để App Group +
  Widget Extension hoạt động ổn định trên macOS 15+.
- Tạo Xcode project/workspace với App target + Widget Extension target
  (SwiftPM không bundle/sign `.appex` được).
- Tạo App Group chung cho normalized snapshots và provider preferences;
  group phải prefix Team ID theo yêu cầu macOS 15+.
- Giữ main app hỗ trợ macOS 13 nếu có thể; Widget Extension desktop đặt
  minimum macOS 14. Nếu toolchain không cho hai deployment target độc lập,
  cần quyết định có nâng toàn app lên macOS 14 hay không.

### ☐ 4.2. Shared snapshot pipeline

- Main app vẫn là nơi duy nhất chạy CLI và poll usage.
- Sau mỗi snapshot/preference thay đổi, ghi normalized data atomically vào App
  Group rồi gọi `WidgetCenter.shared.reloadTimelines`.
- Widget không chạy CLI, không đọc auth và không kỳ vọng refresh mỗi 60 giây;
  WidgetKit kiểm soát timeline.
- Hiển thị timestamp/cached state rõ ràng khi main app chưa chạy hoặc dữ liệu
  cũ.

### ☐ 4.3. Widget UI v1

- `systemSmall`: summary của các provider đang bật.
- `systemMedium`: metric chính và reset time của các provider đang bật.
- Phiên bản đầu mirror lựa chọn provider từ Settings của app; App Intent cấu
  hình riêng cho từng widget để giai đoạn sau.
- Hỗ trợ rendering mode của macOS desktop và Notification Center; không phụ
  thuộc màu nền graphite cố định.

### ☐ 4.4. Packaging và release

- Build script phải embed extension tại `Contents/PlugIns`, sign nested bundle
  trước khi sign app và xác minh bằng `codesign --verify --strict`.
- Test widget xuất hiện trong gallery sau khi app launch, đặt được trên desktop
  macOS 14+, hoạt động trong Notification Center và còn nguyên sau Homebrew/DMG
  install.
- Cập nhật Info.plist, entitlements, Cask, INSTALL và release checklist.

**Điều kiện hoàn thành:** widget đọc đúng shared snapshot, không trực tiếp chạy
CLI, không lộ dữ liệu nhạy cảm và artifact DMG đã cài vẫn đăng ký extension.

---

## Thứ tự release đề xuất

### Clawstatus 0.5.0

1. Refactor provider registry (0.1) và process-runner chung (0.2).
2. Settings bật/tắt provider (giai đoạn 1), gồm chính sách menu bar label.
3. Widget-style UI trong floating panel (giai đoạn 3).
4. Tests, docs và release.

### Milestone Antigravity (không gắn version)

Mở lại khi gate 0.3 đạt GO — upstream có contract máy đọc, không tốn quota.
Theo dõi [antigravity-cli#46][agy-46].

### Milestone WidgetKit (không gắn version)

Mở lại sau khi chốt Apple Developer ID + notarization (4.1). Không để
WidgetKit chặn bất kỳ release nào khác.

## Verification chung sau mỗi giai đoạn

```bash
swift run --package-path macos ClawlineCheck
./macos/scripts/build-app.sh
codesign --verify --strict macos/dist/Clawstatus.app
git diff --check
```

Khi có Widget Extension, bổ sung kiểm tra `.appex`, App Group và widget gallery
trên macOS 14+.

## Tài liệu tham khảo

- [Antigravity CLI `/usage`](https://antigravity.google/docs/cli/commands/usage)
  và [CLI reference](https://antigravity.google/docs/cli-reference) — lưu ý:
  hai trang này render bằng JS, tool tự động không đọc được nội dung; chỉ dùng
  tham khảo cho người đọc, không dùng làm bằng chứng contract.
- [antigravity-cli#46 — Usage and Quota][agy-46] (open, 05/2026)
- [Forum: /usage hiển thị sai][agy-wrong] ·
  [Forum: /usage chỉ cập nhật sau restart][agy-stale]
- [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- [Apple: macOS Sonoma desktop widgets](https://support.apple.com/en-us/109035)

[agy-46]: https://github.com/google-antigravity/antigravity-cli/issues/46
[agy-wrong]: https://discuss.ai.google.dev/t/wrong-usage-information-in-antigravity-cli/147405
[agy-stale]: https://discuss.ai.google.dev/t/gemini-cli-antigravity-cli-day-1-impressions-only-updates-usage-after-quit-and-reload/146374
