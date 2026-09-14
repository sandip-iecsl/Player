import 'space.dart';

/// State representation for active pairing lifecycle.
class PairingState {
  final SpaceStatus status;
  final SpaceEntity? activeSpace;
  final String? errorMessage;
  final bool isLoading;

  const PairingState({
    this.status = SpaceStatus.none,
    this.activeSpace,
    this.errorMessage,
    this.isLoading = false,
  });

  bool get isPaired => status == SpaceStatus.active && activeSpace != null;
  bool get hasPartnerFolder => activeSpace?.partnerDriveFolderId != null && activeSpace!.partnerDriveFolderId!.isNotEmpty;
  bool get isTransitioning =>
      status == SpaceStatus.pending ||
      status == SpaceStatus.creatingSpace ||
      status == SpaceStatus.syncingPermissions ||
      status == SpaceStatus.unpairing ||
      isLoading;

  PairingState copyWith({
    SpaceStatus? status,
    SpaceEntity? activeSpace,
    bool clearActiveSpace = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isLoading,
  }) {
    return PairingState(
      status: status ?? this.status,
      activeSpace: clearActiveSpace ? null : (activeSpace ?? this.activeSpace),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  factory PairingState.initial() => const PairingState();

  @override
  String toString() {
    return 'PairingState(status: ${status.name}, space: ${activeSpace?.spaceId}, loading: $isLoading, error: $errorMessage)';
  }
}
