import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../../avatar/domain/avatar_colors.dart';
import '../../avatar/domain/avatar_model.dart';
import '../../avatar/domain/avatar_mood.dart';
import '../../avatar/presentation/avatar_view.dart';

class SettingsAvatarCustomizePage extends ConsumerStatefulWidget {
  const SettingsAvatarCustomizePage({super.key, required this.modelId});

  final String modelId;

  @override
  ConsumerState<SettingsAvatarCustomizePage> createState() =>
      _SettingsAvatarCustomizePageState();
}

class _SettingsAvatarCustomizePageState
    extends ConsumerState<SettingsAvatarCustomizePage> {
  late final AvatarModel _model;
  late final AvatarColors _initialColors;
  late AvatarColors _draft;
  late AvatarColors _previewColors;
  late AvatarPart _selectedPart;
  Timer? _previewTimer;
  bool _saving = false;
  bool _confirmingDiscard = false;

  bool get _dirty => _draft != _initialColors;

  @override
  void initState() {
    super.initState();
    _model = avatarModelById(widget.modelId);
    _initialColors =
        (ref.read(avatarColorsProvider)[_model.id] ?? AvatarColors.empty)
            .restrictTo(_model.parts);
    _draft = _previewColors = _initialColors;
    _selectedPart = _model.parts.first;
  }

  void _edit(AvatarColors colors) {
    if (_saving || colors == _draft) return;
    setState(() => _draft = colors);
    _previewTimer ??= Timer(const Duration(milliseconds: 100), () {
      _previewTimer = null;
      if (_previewColors != _draft) {
        setState(() => _previewColors = _draft);
      }
    });
  }

  Future<bool> _confirm(String title, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reset() async {
    if (await _confirm('Khôi phục mặc định?', 'Khôi phục') && mounted) {
      _edit(AvatarColors.empty);
    }
  }

  Future<void> _confirmDiscard() async {
    if (_saving || _confirmingDiscard || !_dirty) return;
    _confirmingDiscard = true;
    final discard = await _confirm('Bỏ thay đổi?', 'Bỏ thay đổi');
    _confirmingDiscard = false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final notifier = ref.read(avatarColorsProvider.notifier);
    final previous = notifier.state[_model.id];
    final next = {...notifier.state};
    if (_draft == AvatarColors.empty) {
      next.remove(_model.id);
    } else {
      next[_model.id] = _draft;
    }

    final storage = ref.read(secureStorageProvider);
    setState(() => _saving = true);
    notifier.state = Map.unmodifiable(next);
    try {
      await storage.saveAvatarColorsJson(encodeAvatarColorsMap(next));
    } catch (_) {
      if (notifier.mounted) {
        final restored = {...notifier.state};
        if (previous == null) {
          restored.remove(_model.id);
        } else {
          restored[_model.id] = previous;
        }
        notifier.state = Map.unmodifiable(restored);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không lưu được cài đặt')));
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewHeight = (MediaQuery.sizeOf(context).height * 0.4)
        .clamp(240.0, 360.0)
        .toDouble();
    final pickerColor =
        _draft[_selectedPart] ?? _model.originalColors[_selectedPart]!;

    return PopScope<void>(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Tùy chỉnh ${_model.name}'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Lưu'),
            ),
          ],
        ),
        body: NavigationContentFrame(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: ResponsiveFormContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: previewHeight,
                      child: AvatarView(
                        model: _model,
                        mood: AvatarMood.neutral,
                        colors: _previewColors,
                        semanticsLabel: 'Xem trước nhân vật 3D',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final part in _model.parts) _partChip(part),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AbsorbPointer(
                      absorbing: _saving,
                      child: Semantics(
                        label: 'Chọn màu ${_selectedPart.label}',
                        child: HueRingPicker(
                          pickerColor: pickerColor,
                          onColorChanged: (color) =>
                              _edit(_draft.withPart(_selectedPart, color)),
                          enableAlpha: false,
                          displayThumbColor: true,
                          portraitOnly: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _saving || _draft == AvatarColors.empty
                          ? null
                          : _reset,
                      child: const Text('Khôi phục mặc định'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _partChip(AvatarPart part) {
    final color = _draft[part] ?? _model.originalColors[part];
    final description = _draft.toJson()[part.wireName] ?? 'Mặc định';
    return Semantics(
      label: 'Màu ${part.label}',
      value: description,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: ChoiceChip(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          showCheckmark: false,
          avatar: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: const SizedBox.square(dimension: 18),
          ),
          label: ExcludeSemantics(child: Text(part.label)),
          selected: _selectedPart == part,
          onSelected: _saving
              ? null
              : (_) => setState(() => _selectedPart = part),
        ),
      ),
    );
  }
}
