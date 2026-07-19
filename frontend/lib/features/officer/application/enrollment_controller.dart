import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/officer_models.dart';

/// The in-progress officer enrollment, assembled across the 5-step stepper.
class OfficerEnrollmentDraft {
  const OfficerEnrollmentDraft({
    this.departmentId,
    this.designation,
    this.boundaryId,
    this.boundaryName,
    this.fullName = '',
    this.phoneNumber = '',
    this.employeeId = '',
    this.email = '',
  });

  final String? departmentId;
  final DesignationOption? designation;

  /// The final selected boundary (at the designation's level) + its name.
  final int? boundaryId;
  final String? boundaryName;

  final String fullName;
  final String phoneNumber;
  final String employeeId;
  final String email;

  bool get hasDepartment => departmentId != null;
  bool get hasDesignation => designation != null;
  bool get hasBoundary => boundaryId != null;

  OfficerEnrollmentDraft copyWith({
    String? departmentId,
    DesignationOption? designation,
    int? boundaryId,
    String? boundaryName,
    String? fullName,
    String? phoneNumber,
    String? employeeId,
    String? email,
    bool clearDesignation = false,
    bool clearBoundary = false,
  }) {
    return OfficerEnrollmentDraft(
      departmentId: departmentId ?? this.departmentId,
      designation:
          clearDesignation ? null : (designation ?? this.designation),
      boundaryId: clearBoundary ? null : (boundaryId ?? this.boundaryId),
      boundaryName: clearBoundary ? null : (boundaryName ?? this.boundaryName),
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      employeeId: employeeId ?? this.employeeId,
      email: email ?? this.email,
    );
  }
}

class OfficerEnrollmentController extends Notifier<OfficerEnrollmentDraft> {
  @override
  OfficerEnrollmentDraft build() => const OfficerEnrollmentDraft();

  /// Selecting a department invalidates downstream (designation + boundary).
  void setDepartment(String departmentId) {
    if (state.departmentId == departmentId) return;
    state = OfficerEnrollmentDraft(
      departmentId: departmentId,
      fullName: state.fullName,
      phoneNumber: state.phoneNumber,
      employeeId: state.employeeId,
      email: state.email,
    );
  }

  /// Selecting a designation invalidates the boundary selection.
  void setDesignation(DesignationOption designation) {
    state = state.copyWith(designation: designation, clearBoundary: true);
  }

  void setBoundary(int boundaryId, String boundaryName) {
    state = state.copyWith(boundaryId: boundaryId, boundaryName: boundaryName);
  }

  void clearBoundary() => state = state.copyWith(clearBoundary: true);

  void setDetails({
    required String fullName,
    required String phoneNumber,
    required String employeeId,
    required String email,
  }) {
    state = state.copyWith(
      fullName: fullName,
      phoneNumber: phoneNumber,
      employeeId: employeeId,
      email: email,
    );
  }

  void reset() => state = const OfficerEnrollmentDraft();
}

final officerEnrollmentProvider =
    NotifierProvider<OfficerEnrollmentController, OfficerEnrollmentDraft>(
  OfficerEnrollmentController.new,
);
