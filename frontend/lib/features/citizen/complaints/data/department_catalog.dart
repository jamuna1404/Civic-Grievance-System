import 'package:flutter/material.dart';

/// A selectable department, shown with a short citizen-friendly label and an
/// icon (never the raw `department_id`).
class DepartmentOption {
  const DepartmentOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  /// Matches `departments.department_id` in the backend seed.
  final String id;
  final String label;
  final IconData icon;
}

/// Icon used when a complaint references a department id not in [kDepartments]
/// (e.g. a new department added server-side before the client catalog).
const IconData kFallbackDepartmentIcon = Icons.apartment_outlined;

/// Client-side catalog mapping the seeded department IDs to short labels and
/// icons. Kept here (rather than fetched) so the picker stays fast and fully
/// themed; the IDs must stay in sync with the `departments` table seed.
const List<DepartmentOption> kDepartments = [
  DepartmentOption(
    id: 'GCC_ENG_ROADS',
    label: 'Roads & Potholes',
    icon: Icons.add_road_outlined,
  ),
  DepartmentOption(
    id: 'GCC_PH_SAN',
    label: 'Garbage & Sanitation',
    icon: Icons.delete_outline,
  ),
  DepartmentOption(
    id: 'GCC_ENG_SWD',
    label: 'Storm Water Drains',
    icon: Icons.water_drop_outlined,
  ),
  DepartmentOption(
    id: 'GCC_ELECT',
    label: 'Streetlights',
    icon: Icons.lightbulb_outline,
  ),
  DepartmentOption(
    id: 'CMWSSB_SEW',
    label: 'Sewerage',
    icon: Icons.plumbing_outlined,
  ),
  DepartmentOption(
    id: 'TANGEDCO_PWR',
    label: 'Power (TNEB)',
    icon: Icons.bolt_outlined,
  ),
  DepartmentOption(
    id: 'GCP_LAW_ORD',
    label: 'Police (L&O)',
    icon: Icons.local_police_outlined,
  ),
];
