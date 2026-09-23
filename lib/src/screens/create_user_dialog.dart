import 'package:flutter/material.dart';
import 'package:sci_http_client/error.dart';

/// The core admin console's email rule (sci_web_component2,
/// `AdminComponent.createUser`): the text must contain `local@host.tld`
/// somewhere. It is a search, not a whole-string match, exactly as the core
/// dialog applies it; the email is trimmed before it is sent.
final newUserEmailPattern =
    RegExp(r'[-0-9a-zA-Z.+_]+@[-0-9a-zA-Z.+_]+\.[a-zA-Z]{2,4}');

String? validateNewUserName(String? value) =>
    (value ?? '').isEmpty ? 'A name is required.' : null;

/// The core dialog's message, word for word.
String? validateNewUserEmail(String? value) =>
    newUserEmailPattern.hasMatch(value ?? '')
        ? null
        : 'A valid email must be supplied.';

String? validateNewUserPassword(String? value) =>
    (value ?? '').isEmpty ? 'A password is required.' : null;

/// Creates a user; completes when the server has answered.
typedef CreateUser = Future<void> Function(
    {required String name, required String email, required String password});

/// Name, email and password for a new user. Pops with the new user's name
/// once [create] succeeds; on a server error it shows the error and keeps
/// what was typed, so the admin can correct it and try again.
class CreateUserDialog extends StatefulWidget {
  final CreateUser create;
  const CreateUserDialog({super.key, required this.create});

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.create(
          name: _name.text, email: _email.text, password: _password.text);
      if (mounted) Navigator.of(context).pop(_name.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ServiceError ? e.reason : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Create user'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('create-user-name'),
                controller: _name,
                enabled: !_busy,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: validateNewUserName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('create-user-email'),
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: validateNewUserEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('create-user-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: validateNewUserPassword,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const Key('create-user-error'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
