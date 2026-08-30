# Các lỗi đã sửa (26/08/2026)

So với bản gốc bạn upload. Chi tiết từng lỗi + lý do đã trao đổi trong chat;
đây là bản tóm tắt để tiện tra cứu lại sau này.

## Lỗi ảnh hưởng chức năng

1. **`lib/services/github_service.dart` - `searchFilesInRepo`**
   Branch chứa dấu "/" (vd `feature/abc`) khiến API git/trees trả lỗi vì
   không được mã hoá đúng. Sửa: dùng `Uri(pathSegments: [...])` để branch
   luôn được coi là 1 segment duy nhất.

2. **`lib/services/download_manager.dart` - `runDownload`**
   Khi lưu file thất bại (`save()` trả `null`) dù đã tải dữ liệu thành công,
   trước đây không gọi `onSuccess` lẫn `onError` -> tác vụ biến mất không rõ
   lý do. Sửa: gọi `onError` với thông báo rõ ràng trong trường hợp này.

3. **`lib/screens/run_detail_screen.dart` - `_downloadArtifact`**
   Artifact CI nhiều file/thư mục con: dùng thẳng đường dẫn trong zip (có
   dấu "/") làm tên file lưu vào Downloads sẽ lỗi vì `MediaStore.DISPLAY_NAME`
   không cho phép "/". Sửa: làm phẳng tên file khi có nhiều hơn 1 file.

4. **`lib/utils/time_ago.dart`**
   Luôn trả tiếng Việt hard-code, không theo ngôn ngữ đang chọn trong Cài đặt.
   Sửa: dùng chung hệ thống dịch `t()` (thêm khoá mới `time.*` trong
   `lib/l10n/strings.dart`).

5. **`lib/screens/browser_screen.dart`**
   Repo trống (0 file) bị coi như "chưa mở", ẩn hết nút Actions/Commits/
   Search/Upload - kể cả Upload, vốn là cách để thêm file đầu tiên. Sửa:
   thêm state `_repoOpened` tách riêng khỏi việc repo có file hay không.

6. **`lib/screens/settings_screen.dart` - `_importBackup`**
   Nhập backup đổi danh sách repo ghim nhưng không đồng bộ lại CI Watch đang
   chạy nền. Sửa: gọi `CiWatchService.syncWatchedReposIfEnabled()` sau khi
   nhập, đồng thời cập nhật lại số đếm hiển thị.

7. **`lib/screens/notifications_screen.dart`**
   - Token hết hạn (401) không được xử lý giống các màn khác (không tự đăng
     xuất/đưa về màn login, chỉ hiện lỗi chung + nút Thử lại vô dụng).
   - "Đánh dấu tất cả đã đọc" luôn xoá sạch danh sách kể cả khi đang xem tab
     "Tất cả", làm tab đó trống oan dù vẫn còn thông báo (đã đọc) đáng lẽ
     phải hiển thị.

## Lỗi nhỏ / cải thiện thêm

8. **`lib/screens/run_detail_screen.dart` - `_viewLog`**: dialog loading khi
   xem log thêm `barrierDismissible: false`, tránh việc chạm ra ngoài lúc
   đang tải sẽ khiến lần `Navigator.pop()` sau đó đóng nhầm luôn màn hình.

9. **`lib/widgets/file_editor_sheet.dart`**: nút "Tải về máy" giờ cũng khoá
   khi load file lỗi (`_error != null`), tránh tải ra file rỗng.

10. **`lib/widgets/top_notification.dart`**: thêm cơ chế xếp chồng khi nhiều
    thông báo hiện gần nhau (vd 2 lượt tải xong cùng lúc), thay vì đè lên
    nhau ở cùng 1 vị trí.

11. **`.github/workflows/dart.yml`**: sửa từ boilerplate Dart thuần (dùng
    `dart pub get`/`dart analyze`/`dart test`, nhánh `master`) sang đúng
    toolchain Flutter (`flutter pub get`/`flutter analyze`, nhánh `main`
    khớp với `build_apk.yml`), không lỗi khi chưa có thư mục `test/`.

## Đã xem nhưng chưa sửa (mức độ thấp, cân nhắc sau)

- `zipFiles` trong `github_service.dart`: đã sửa kèm luôn (mục 1 ở trên gộp
  chung PR sửa file này) - ranh giới cắt `folderPath` giờ kiểm tra đúng dấu
  "/" thay vì `startsWith()` suông.
- `downloadArtifactZip`: đã gộp sửa luôn - dùng chung 1 `http.Client()` và
  đóng lại đúng cách (`finally`), tránh rò rỉ connection khi thử lại nhiều
  lần cho file lớn.

## Lưu ý

File `github-downloader-fixed (1).zip` nằm lồng bên trong bản zip gốc bạn
upload (có vẻ là 1 bản backup cũ từ máy bạn, ngày 16/08) đã KHÔNG được đưa
vào bản zip mới này để tránh rối - nếu cần bản đó, dùng lại file gốc bạn đã
upload.

## Cập nhật thêm (theo phản hồi UI)

12. **`lib/screens/repo_list_screen.dart`**: thêm hàng chip lọc theo chủ sở
    hữu ("Của tôi" / "Tất cả" / từng tổ chức) ngay dưới ô tìm kiếm, mặc định
    chọn sẵn "Của tôi". Trước đây danh sách luôn gộp chung repo cá nhân với
    repo tổ chức/repo chỉ là collaborator (do API gọi `affiliation:
    owner,collaborator,organization_member`), khiến danh sách vừa dài vừa khó
    tìm đúng repo của mình. Repo đã ghim luôn hiện bất kể đang chọn lọc nào.
    Chip lọc tự ẩn nếu tài khoản chỉ có repo của riêng mình (không có gì để lọc).

13. **`lib/screens/repo_list_screen.dart`** (bổ sung): khi chọn "Tất cả" và
    không tìm kiếm, danh sách tự NHÓM theo owner kèm tiêu đề + số lượng
    ("Đã ghim", "Của tôi", tên từng tổ chức...) thay vì 1 danh sách phẳng dài.
    Chọn riêng 1 owner qua chip hoặc đang tìm kiếm thì vẫn hiện phẳng như cũ
    (nhóm lúc đó chỉ thừa).

## Cập nhật thêm (theo phản hồi màn khoá vân tay)

14. **`lib/services/app_settings.dart`, `lib/screens/lock_screen.dart`,
    `lib/main.dart`**: thêm khoảng "ân hạn" 30 phút cho màn khoá vân tay.
    Trước đây trạng thái "đã mở khoá" (`_unlocked`) chỉ sống trong RAM, nên
    mỗi khi Android tự giết tiến trình app lúc chạy nền (rất hay gặp, nhất là
    máy chạy nhiều tiến trình cùng lúc) là mất trạng thái, mở lại app phải
    verify lại dù chỉ vừa đóng app trước đó ít phút. Giờ mốc thời gian verify
    thành công gần nhất được lưu bền (`AppSettings.lastUnlockedAt`), mở lại
    app trong vòng 30 phút kể từ lần verify gần nhất sẽ được bỏ qua màn khoá.
    Muốn đổi thời lượng, sửa hằng số `AppSettings.unlockGracePeriod`.

## Gỡ bỏ tính năng (theo yêu cầu)

15. **Gỡ hoàn toàn tính năng khoá vân tay/khuôn mặt** — theo yêu cầu, không
    còn giữ dạng "ân hạn" nữa mà bỏ hẳn:
    - Xoá file `lib/screens/lock_screen.dart`
    - Gỡ `LockScreen` khỏi luồng khởi động (`lib/main.dart`) - đăng nhập xong
      vào thẳng danh sách repo
    - Gỡ `biometricLockEnabled`, `lastUnlockedAt`, `unlockGracePeriod`,
      `markUnlockedNow()` và các key lưu trữ liên quan khỏi
      `lib/services/app_settings.dart`
    - Gỡ card "Khoá app bằng vân tay/khuôn mặt" khỏi Cài đặt
      (`lib/screens/settings_screen.dart`)
    - Xoá 7 khoá dịch liên quan (`lock.*`, `settings.section_security`,
      `settings.biometric_lock`) khỏi `lib/l10n/strings.dart`
    - Gỡ dependency `local_auth` khỏi `pubspec.yaml`

    Lưu ý: file `android/app/src/main/AndroidManifest.xml` (không nằm trong
    những gì bạn gửi cho tôi, do Flutter tự sinh khi tạo project) có thể vẫn
    còn khai báo quyền `USE_BIOMETRIC` từ trước - quyền không dùng tới thì
    không gây lỗi gì, nhưng muốn dọn sạch hẳn thì tự kiểm tra/xoá dòng đó
    trong file đó nhé (tôi không có file này để sửa trực tiếp).

## Dọn nốt (theo phát hiện khi build)

16. **`.github/workflows/build_apk.yml`**: xoá bước tự thêm quyền
    `USE_BIOMETRIC` vào AndroidManifest.xml lúc build — sót lại từ tính năng
    khoá vân tay đã gỡ ở mục 15, không gây lỗi nhưng thừa.
