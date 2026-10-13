import 'dart:async';

class NotificationIntentBus {
  NotificationIntentBus._();

  static final NotificationIntentBus instance = NotificationIntentBus._();

  final StreamController<NotificationIntent> _controller =
      StreamController<NotificationIntent>.broadcast();

  Stream<NotificationIntent> get stream => _controller.stream;

  void emit(NotificationIntent intent) {
    if (_controller.isClosed) return;
    _controller.add(intent);
  }

  void dispose() {
    _controller.close();
  }
}

abstract class NotificationIntent {
  const NotificationIntent();
}

class CategorizeTransactionIntent extends NotificationIntent {
  final String reference;

  const CategorizeTransactionIntent(this.reference);
}

class QuickCategorizeTransactionIntent extends NotificationIntent {
  final String reference;
  final String categoryId;

  const QuickCategorizeTransactionIntent(this.reference, this.categoryId);
}

class OpenFailedParseReviewIntent extends NotificationIntent {
  final String reviewId;

  const OpenFailedParseReviewIntent(this.reviewId);
}
