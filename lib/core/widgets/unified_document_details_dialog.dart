import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

class UnifiedDocumentField {
  const UnifiedDocumentField(this.label, this.value, {this.icon});

  final String label;
  final Object? value;
  final IconData? icon;
}

class UnifiedDocumentSection {
  const UnifiedDocumentSection({required this.title, required this.fields});

  final String title;
  final List<UnifiedDocumentField> fields;
}

Future<void> showUnifiedDocumentDetails({
  required BuildContext context,
  required String title,
  required String documentNumber,
  required String status,
  required List<UnifiedDocumentSection> sections,
  IconData icon = Icons.description_outlined,
}) {
  return showAppWorkspaceDialogBuilder<void>(
    context: context,
    useRootNavigator: true,
    title: title,
    builder: (_) => Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  AppText(
                    documentNumber,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _StatusBadge(status: status),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, index) => _SectionCard(section: sections[index]),
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final UnifiedDocumentSection section;

  @override
  Widget build(BuildContext context) {
    final fields = section.fields
        .where(
          (field) =>
              field.value != null && field.value.toString().trim().isNotEmpty,
        )
        .toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            section.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: fields
                    .map(
                      (field) => SizedBox(
                        width: width,
                        child: _FieldRow(field: field),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final UnifiedDocumentField field;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          field.icon ?? Icons.label_outline,
          size: 18,
          color: Colors.grey.shade700,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                field.label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 2),
              AppSelectableText(
                field.value.toString(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AppText(
        status,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
