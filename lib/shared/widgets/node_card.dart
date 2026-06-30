import 'package:flutter/material.dart';
import '../theme/colors.dart';

class NodeCard extends StatelessWidget {
  final String id;
  final bool active;

  const NodeCard({
    super.key,
    required this.id,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? AppColors.success : AppColors.error,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            color: active ? AppColors.success : AppColors.error,
            size: 12,
          ),
          const SizedBox(width: 8),
          Text(id),
        ],
      ),
    );
  }
}