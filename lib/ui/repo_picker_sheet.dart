/// Bottom sheet picking the repo selected notes are assigned to.
library;

import 'package:flutter/material.dart';

import 'package:todo/data/repo_assign.dart';

/// The repos already on notes, plus a field for a new `kuhyx/<name>`.
///
/// Pops with the chosen `owner/name`; dismissing it pops null. The field
/// starts at `kuhyx/` (content, not a label) and refuses anything that is
/// not `owner/name` with an error icon rather than words.
class RepoPickerSheet extends StatefulWidget {
  /// Creates the picker listing [repos].
  const RepoPickerSheet({required this.repos, super.key});

  /// Distinct repos already present on notes, in display order.
  final List<String> repos;

  @override
  State<RepoPickerSheet> createState() => _RepoPickerSheetState();
}

class _RepoPickerSheetState extends State<RepoPickerSheet> {
  final _field = TextEditingController(text: 'kuhyx/');
  bool _bad = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _field.text.trim();
    if (!isRepoName(value)) return setState(() => _bad = true);
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('repo-picker'),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final repo in widget.repos)
                    ListTile(
                      key: ValueKey('repo-$repo'),
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(repo),
                      onTap: () => Navigator.of(context).pop(repo),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const ValueKey('repo-new'),
                controller: _field,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_bad) setState(() => _bad = false);
                },
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.create_new_folder_outlined),
                  error: _bad
                      ? const Icon(
                          Icons.error_outline,
                          size: 16,
                          semanticLabel: 'Not owner/name',
                        )
                      : null,
                  suffixIcon: IconButton(
                    key: const ValueKey('repo-new-submit'),
                    onPressed: _submit,
                    icon: const Icon(Icons.check, semanticLabel: 'Use repo'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
