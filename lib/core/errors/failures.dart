/// Base failure type for repository-layer errors, decoupled from
/// provider-specific exception types so viewmodels/UI never depend
/// directly on AuthException / PostgrestException classes.
class Failure {
  final String message;
  final String? code;

  const Failure(this.message, {this.code});

  @override
  String toString() => code != null ? '[$code] $message' : message;
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

class DataFailure extends Failure {
  const DataFailure(super.message, {super.code});
}