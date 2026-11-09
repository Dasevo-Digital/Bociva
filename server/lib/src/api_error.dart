/// Fehler, den die API den Clients so mitteilt.
class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);
  final int status;
  final String code, message;
}
