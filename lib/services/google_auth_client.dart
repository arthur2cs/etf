import 'package:http/http.dart' as http;

/// A [http.BaseClient] that attaches Google OAuth headers obtained from
/// [GoogleSignInAccount.authHeaders] to every request, so it can be used
/// with the `googleapis` package clients (SheetsApi, DriveApi, ...).
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
