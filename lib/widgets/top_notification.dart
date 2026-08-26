import 'package:flutter/material.dart';

/// Theo dõi các banner đang hiện CÙNG LÚC để xếp chồng chúng theo thứ tự dọc.
/// Trước đây mỗi banner luôn tự định vị ở đúng 1 toạ độ cố định (đỉnh màn
/// hình), nên nếu 2 thông báo xuất hiện gần nhau (vd 2 lượt tải xong cùng lúc)
/// sẽ đè thẳng lên nhau, chỉ đọc được cái ở trên.
class _TopNotificationStack extends ChangeNotifier {
  static final _TopNotificationStack instance = _TopNotificationStack._();
  _TopNotificationStack._();

  final List<Object> _active = [];

  Object register() {
    final token = Object();
    _active.add(token);
    notifyListeners();
    return token;
  }

  int indexOf(Object token) => _active.indexOf(token);

  void unregister(Object token) {
    _active.remove(token);
    notifyListeners();
  }
}

/// Hiện 1 thông báo dạng banner nhỏ ở TRÊN CÙNG màn hình (dưới AppBar),
/// tự biến mất sau vài giây - dùng cho thông báo "đã lưu file" để dễ thấy hơn
/// SnackBar mặc định ở dưới đáy màn hình.
void showTopNotification(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Duration duration = const Duration(seconds: 3),
}) {
  // Không dùng Overlay.of(context) trực tiếp: khi context truyền vào là
  // navigatorKey.currentContext (context của chính Navigator, dùng để báo
  // "tải xong" từ DownloadManager), Overlay do Navigator tạo ra nằm ở DƯỚI
  // nó trong cây widget chứ không phải tổ tiên, nên Overlay.of() tìm ngược
  // lên sẽ không thấy -> trả null -> release build crash "Null check
  // operator used on a null value" (assert báo lỗi rõ ràng bị lược bỏ ở
  // debug). Navigator.of(context).overlay lấy đúng overlay của navigator
  // trong cả 2 trường hợp (context là chính Navigator, hoặc context bình
  // thường của 1 màn hình con).
  final overlay = Navigator.of(context).overlay;
  if (overlay == null) return; // Navigator chưa sẵn sàng - bỏ qua, không crash
  final scheme = Theme.of(context).colorScheme;
  final token = _TopNotificationStack.instance.register();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _TopNotificationWidget(
      token: token,
      message: message,
      icon: icon,
      color: scheme.primary,
      onColor: scheme.onPrimary,
      duration: duration,
      onDismiss: () {
        _TopNotificationStack.instance.unregister(token);
        entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _TopNotificationWidget extends StatefulWidget {
  final Object token;
  final String message;
  final IconData icon;
  final Color color;
  final Color onColor;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.token,
    required this.message,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe _TopNotificationStack: mỗi khi có banner khác xuất hiện/biến
    // mất, vị trí (slot) của CHÍNH banner này có thể đổi -> cần build lại để
    // trượt lên/xuống đúng chỗ thay vì đứng yên chồng lên banner khác.
    return AnimatedBuilder(
      animation: _TopNotificationStack.instance,
      builder: (context, _) {
        final index = _TopNotificationStack.instance.indexOf(widget.token);
        // index = -1 trong khoảnh khắc rất ngắn sau khi unregister (đang chạy
        // animation trượt ra) - giữ nguyên vị trí cuối thay vì nhảy giật lên đỉnh.
        final slot = index < 0 ? 0 : index;
        final top = MediaQuery.of(context).padding.top + 8 + slot * 64.0;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          top: top,
          left: 12,
          right: 12,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.onColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(color: widget.onColor, fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
