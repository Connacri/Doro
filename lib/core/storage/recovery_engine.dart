class RecoveryEngine {
  void recover(List<dynamic> corruptedState) {
    corruptedState.removeWhere((e) => e == null);
  }

  bool validateIntegrity(List<dynamic> state) {
    return state.isNotEmpty;
  }
}