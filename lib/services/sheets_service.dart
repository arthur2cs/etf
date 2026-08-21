import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;

import 'google_auth_client.dart';

class SheetsAuthException implements Exception {
  final String message;
  SheetsAuthException(this.message);

  @override
  String toString() => message;
}

const _spreadsheetTitle = 'ETF Reminder - Suivi PEA';

const _transactionsSheet = 'transactions';
const _configSheet = 'config';
const _inflationSheet = 'inflation';

const _transactionsHeader = [
  'date',
  'isin',
  'montant_eur',
  'prix_unitaire',
  'nb_actions',
  'commission_eur',
];
const _configHeader = ['isin', 'nom', 'categorie', 'pct_cible'];
const _inflationHeader = ['annee', 'taux_pct'];

/// Reads/writes the app's data in a Google Sheet owned by the signed-in
/// user. The sheet is the single source of truth: reinstalling the app on
/// a new phone and signing in again picks up right where it left off.
class SheetsService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      sheets.SheetsApi.spreadsheetsScope,
      drive.DriveApi.driveFileScope,
    ],
  );

  sheets.SheetsApi? _sheetsApi;
  drive.DriveApi? _driveApi;
  String? _spreadsheetId;

  Future<GoogleSignInAccount> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw SheetsAuthException('Connexion Google annulée.');
    }
    final authHeaders = await account.authHeaders;
    final client = GoogleAuthClient(authHeaders);
    _sheetsApi = sheets.SheetsApi(client);
    _driveApi = drive.DriveApi(client);
    return account;
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) return null;
    final authHeaders = await account.authHeaders;
    final client = GoogleAuthClient(authHeaders);
    _sheetsApi = sheets.SheetsApi(client);
    _driveApi = drive.DriveApi(client);
    return account;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _sheetsApi = null;
    _driveApi = null;
    _spreadsheetId = null;
  }

  bool get isSignedIn => _sheetsApi != null;

  /// Finds the app's spreadsheet by name, or creates it (with the 3 tabs
  /// and their header rows) if it doesn't exist yet — e.g. on first launch
  /// or after reinstalling on a new phone.
  Future<String> ensureSpreadsheet() async {
    if (_spreadsheetId != null) return _spreadsheetId!;
    final driveApi = _driveApi;
    final sheetsApi = _sheetsApi;
    if (driveApi == null || sheetsApi == null) {
      throw SheetsAuthException('Non connecté à Google.');
    }

    final found = await driveApi.files.list(
      q: "name = '$_spreadsheetTitle' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    if (found.files != null && found.files!.isNotEmpty) {
      _spreadsheetId = found.files!.first.id;
      return _spreadsheetId!;
    }

    final created = await sheetsApi.spreadsheets.create(
      sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: _spreadsheetTitle),
        sheets: [
          sheets.Sheet(properties: sheets.SheetProperties(title: _transactionsSheet)),
          sheets.Sheet(properties: sheets.SheetProperties(title: _configSheet)),
          sheets.Sheet(properties: sheets.SheetProperties(title: _inflationSheet)),
        ],
      ),
    );
    _spreadsheetId = created.spreadsheetId;

    await _writeHeader(_transactionsSheet, _transactionsHeader);
    await _writeHeader(_configSheet, _configHeader);
    await _writeHeader(_inflationSheet, _inflationHeader);

    return _spreadsheetId!;
  }

  Future<void> _writeHeader(String sheetName, List<String> header) async {
    await _sheetsApi!.spreadsheets.values.update(
      sheets.ValueRange(values: [header]),
      _spreadsheetId!,
      '$sheetName!A1',
      valueInputOption: 'RAW',
    );
  }

  Future<List<List<Object?>>> _readRows(String sheetName) async {
    final spreadsheetId = await ensureSpreadsheet();
    // UNFORMATTED_VALUE returns raw numbers/date-serials instead of
    // locale-formatted strings (e.g. "111,33" or "24/10/2025" if the
    // spreadsheet's locale is French) — parsing below expects that.
    final result = await _sheetsApi!.spreadsheets.values.get(
      spreadsheetId,
      '$sheetName!A2:Z',
      valueRenderOption: 'UNFORMATTED_VALUE',
    );
    return result.values ?? [];
  }

  Future<void> _overwriteRows(String sheetName, List<String> header, List<List<Object?>> rows) async {
    final spreadsheetId = await ensureSpreadsheet();
    await _sheetsApi!.spreadsheets.values.clear(
      sheets.ClearValuesRequest(),
      spreadsheetId,
      '$sheetName!A2:Z',
    );
    if (rows.isEmpty) return;
    await _sheetsApi!.spreadsheets.values.update(
      sheets.ValueRange(values: rows),
      spreadsheetId,
      '$sheetName!A2',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<void> _appendRow(String sheetName, List<Object?> row) async {
    final spreadsheetId = await ensureSpreadsheet();
    await _sheetsApi!.spreadsheets.values.append(
      sheets.ValueRange(values: [row]),
      spreadsheetId,
      '$sheetName!A1',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<List<List<Object?>>> readTransactionRows() => _readRows(_transactionsSheet);

  Future<void> appendTransactionRow(List<Object?> row) => _appendRow(_transactionsSheet, row);

  Future<List<List<Object?>>> readConfigRows() => _readRows(_configSheet);

  Future<void> overwriteConfigRows(List<List<Object?>> rows) =>
      _overwriteRows(_configSheet, _configHeader, rows);

  Future<List<List<Object?>>> readInflationRows() => _readRows(_inflationSheet);

  Future<void> overwriteInflationRows(List<List<Object?>> rows) =>
      _overwriteRows(_inflationSheet, _inflationHeader, rows);
}
