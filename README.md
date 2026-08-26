# GitHub Repo Downloader — Hướng dẫn setup

## Tổng quan
- `github_downloader/`: app Flutter, đăng nhập GitHub, duyệt và tải file repo. Build APK tự động qua GitHub Actions.
- `oauth_backend/`: server FastAPI nhỏ, chỉ có 1 nhiệm vụ là đổi OAuth `code` lấy `access_token` (giữ `client_secret` an toàn, không để trong app).

## Bước 1: Tạo GitHub OAuth App
1. Vào https://github.com/settings/developers → **New OAuth App**
2. Điền:
   - **Application name**: tuỳ ý (vd: TuyTam Repo Downloader)
   - **Homepage URL**: `https://github.com` (hoặc bất kỳ URL nào)
   - **Authorization callback URL**: `githubdownloader://callback`
3. Bấm **Register application** → lấy **Client ID**
4. Bấm **Generate a new client secret** → lấy **Client Secret** (chỉ hiện 1 lần, lưu lại ngay)

## Bước 2: Deploy backend lên Railway
```bash
cd oauth_backend
git init
git add .
git commit -m "init oauth backend"
gh repo create oauth-backend --private --source=. --push
```
Sau đó vào Railway → New Project → Deploy from GitHub repo → chọn repo `oauth-backend`.

Trong Railway, vào tab **Variables**, thêm:
```
GITHUB_CLIENT_ID=<client id bước 1>
GITHUB_CLIENT_SECRET=<client secret bước 1>
```

Railway sẽ cho bạn 1 URL dạng `https://oauth-backend-production.up.railway.app` — copy lại URL này.

## Bước 3: Cập nhật thông tin trong app Flutter
Mở file `github_downloader/lib/services/auth_service.dart`, sửa 2 dòng:
```dart
static const String clientId = 'YOUR_GITHUB_CLIENT_ID'; // dán Client ID vào đây
static const String backendUrl = 'https://your-backend.up.railway.app'; // dán URL Railway vào đây (không có dấu / cuối)
```

## Bước 4: Đẩy code Flutter lên GitHub (qua Termux)
```bash
cd github_downloader
git init
git add .
git commit -m "init github downloader app"
gh repo create github-downloader --private --source=. --push
```

## Bước 5: Lấy APK
1. Vào repo trên GitHub → tab **Actions**
2. Workflow "Build APK" sẽ tự chạy sau khi push (mất khoảng 3-5 phút)
3. Khi chạy xong (dấu tích xanh) → bấm vào lần chạy đó → phần **Artifacts** ở cuối trang → tải file `github-downloader-apk`
4. Giải nén, cài file `.apk` trực tiếp trên điện thoại (cần bật "Cho phép cài từ nguồn không xác định" trong Settings)

## Lưu ý bảo mật
- Token GitHub được lưu bằng `flutter_secure_storage` (Android Keystore), không lưu dạng chữ thường.
- `client_secret` chỉ nằm trên server Railway, không bao giờ có trong app hay repo Flutter.
- Nếu muốn thu hồi quyền truy cập bất cứ lúc nào: GitHub → Settings → Applications → Authorized OAuth Apps → Revoke.
- Repo public tải được ngay không cần đăng nhập gì cả — chỉ khi vào repo private mới cần token (sau khi đăng nhập).

## Muốn mở rộng thêm?
Nói mình biết nếu muốn thêm: tìm kiếm repo qua tên, hiển thị danh sách repo của user đăng nhập thay vì nhập tay owner/repo, tải nguyên thư mục dạng zip, hoặc dark mode.
