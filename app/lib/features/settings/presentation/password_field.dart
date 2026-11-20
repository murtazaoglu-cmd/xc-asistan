// Şifre alanı: gizli yazım + göster/gizle düğmesi (≥ 48 dp). Ham şifre günlüğe/yedeğe yazılmaz.
import 'package:material_ui/material_ui.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.autofocus = false,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final String? helperText;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autofocus: widget.autofocus,
    enableSuggestions: false,
    autocorrect: false,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: widget.textInputAction,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: widget.validator,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Şifreyi göster' : 'Şifreyi gizle',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}
