import 'package:flutter/material.dart';
import 'package:sci_http_client/error.dart';

import '../user_document.dart';

/// A user's tags, edited as chips. It reads the stored user document when
/// it opens and saves that document back with only `tags` changed, under
/// the rev it read. Pops with true once a change is saved.
///
/// A conflict — the user was changed since the document was read — is
/// shown, and the document read again with the edits dropped: the admin
/// sees the tags as they now are and makes the change again. It is never
/// retried on its own.
class EditTagsDialog extends StatefulWidget {
  final String userName;
  final Future<UserDocument> Function() load;
  final Future<void> Function(UserDocument document) save;

  static const conflictMessage = 'This user was changed since the tags were '
      'read. They have been read again: make the change again.';

  const EditTagsDialog({
    super.key,
    required this.userName,
    required this.load,
    required this.save,
  });

  @override
  State<EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<EditTagsDialog> {
  final _field = TextEditingController();
  UserDocument? _document;
  Object? _loadError;
  final _removed = <String>{};
  final _added = <String>[];
  String? _problem;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  List<String> get _tags => [
        for (final t in _document?.tags ?? const <String>[])
          if (!_removed.contains(t)) t,
        ..._added,
      ];

  bool get _changed => _removed.isNotEmpty || _added.isNotEmpty;

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final document = await widget.load();
      if (!mounted) return;
      setState(() {
        _document = document;
        _removed.clear();
        _added.clear();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _document = null;
        _loadError = e is ServiceError ? e.reason : e;
        _busy = false;
      });
    }
  }

  void _add() {
    final (:tag, :problem) = checkNewTag(_field.text, _tags);
    setState(() {
      _problem = problem;
      if (tag == null) return;
      _field.clear();
      if (!_removed.remove(tag)) _added.add(tag);
    });
  }

  void _remove(String tag) => setState(() {
        _problem = null;
        if (!_added.remove(tag)) _removed.add(tag);
      });

  Future<void> _save() async {
    final document = _document;
    if (_busy || document == null) return;
    if (!_changed) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(
          document.withTagEdit(removed: {..._removed}, added: [..._added]));
      if (mounted) Navigator.of(context).pop(true);
    } on ServiceError catch (e) {
      if (!mounted) return;
      if (e.isConflictError) {
        setState(() => _error = EditTagsDialog.conflictMessage);
        await _load();
      } else {
        setState(() {
          _busy = false;
          _error = e.reason;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorStyle =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error);
    final Widget body;
    if (_document == null && _loadError == null) {
      body = const Center(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator()));
    } else if (_document == null) {
      body = Text('The user could not be read: $_loadError',
          key: const Key('edit-tags-load-error'), style: errorStyle);
    } else {
      final tags = _tags;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isEmpty)
            Text('No tags', style: theme.textTheme.bodySmall)
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tag in tags)
                InputChip(
                  key: Key('edit-tag-$tag'),
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  isEnabled: !_busy,
                  deleteButtonTooltipMessage: 'Remove $tag',
                  onDeleted: () => _remove(tag),
                ),
            ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('edit-tags-field'),
                controller: _field,
                enabled: !_busy,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'New tag',
                  errorText: _problem,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                key: const Key('edit-tags-add'),
                onPressed: _busy ? null : _add,
                child: const Text('Add')),
          ]),
        ],
      );
    }
    return AlertDialog(
      title: Text('Tags · ${widget.userName}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  key: const Key('edit-tags-error'), style: errorStyle),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy && _document != null
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('edit-tags-save'),
          onPressed: _busy || _document == null ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
