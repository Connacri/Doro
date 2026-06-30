extension StringExt on String {
  bool get isEmptyOrNull => trim().isEmpty;

  String truncate(int len) {
    return length > len ? "${substring(0, len)}..." : this;
  }
}