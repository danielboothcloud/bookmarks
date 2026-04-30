sealed class AppError {
  const AppError();
}

final class NetworkError extends AppError {
  final String? message;
  const NetworkError([this.message]);
}

final class SyncError extends AppError {
  final String? message;
  const SyncError([this.message]);
}

final class StorageError extends AppError {
  final String? message;
  const StorageError([this.message]);
}

final class NotFoundError extends AppError {
  final String? message;
  const NotFoundError([this.message]);
}

final class AuthError extends AppError {
  final String? message;
  const AuthError([this.message]);
}
