import 'package:flutter/material.dart';

/// Asks for a single line of text. The dialog OWNS its controller (disposed with the dialog's
/// state, after its exit animation), unlike a controller disposed right after `showDialog` returns.
/// Returns the trimmed text, or null if cancelled or left empty.
Future<String?> promptText(BuildContext context, {required String title, String initial = '', String action = 'OK', String? hint}) async {
  final r = await showDialog<String>(context: context, builder: (_) => _PromptDialog(title: title, initial: initial, action: action, hint: hint));
  final t = r?.trim();
  return t == null || t.isEmpty ? null : t;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.initial, required this.action, this.hint});
  final String title, initial, action;
  final String? hint;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _c = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(key: const Key('prompt-field'), controller: _c, autofocus: true, decoration: InputDecoration(hintText: widget.hint), onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.action)),
        ],
      );
}
