class DeepLinkState {
  String? currentLocation;
  bool navigationPending = false;

  void clearCurrentLocation() {
    currentLocation = null;
    navigationPending = false;
  }
}
