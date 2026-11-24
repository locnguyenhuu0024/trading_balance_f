import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../../avatar/domain/avatar_colors.dart';
import '../../avatar/domain/avatar_model.dart';
import '../../avatar/domain/avatar_mood.dart';
import '../../avatar/domain/avatar_outfit.dart';
import '../../avatar/presentation/avatar_view.dart';

class SettingsAvatarCustomizePage extends ConsumerStatefulWidget {
  const SettingsAvatarCustomizePage({super.key, required this.modelId});

  final String modelId;

  @override
  ConsumerState<SettingsAvatarCustomizePage> createState() =>
      _SettingsAvatarCustomizePageState();
}

class _SettingsAvatarCustomizePageState
    extends ConsumerState<SettingsAvatarCustomizePage>
    with SingleTickerProviderStateMixin {
  late final AvatarModel _model;
  late final List<AvatarItem> _items;
  late final TabController? _tabs;
  late final AvatarColors _initialColors;
  late final List<String> _initialOutfit;
  late List<String> _outfit;
  late List<AvatarPart> _parts;
  var _tab = 0;
  late AvatarColors _draft;
  late AvatarColors _previewColors;
  late AvatarPart _selectedPart;
  Timer? _previewTimer;
  bool _saving = false;
  bool _confirmingDiscard = false;

  bool get _dirty =>
      _draft != _initialColors || !listEquals(_outfit, _initialOutfit);

  @override
  void initState() {
    super.initState();
    _model = avatarModelById(widget.modelId);
    _items = itemsForModel(_model.id);
    _tabs = _items.isEmpty ? null : TabController(length: 2, vsync: this);
    _initialOutfit = equippedItems(
      _model.id,
      ref.read(avatarOutfitsProvider)[_model.id] ?? const [],
    ).map((item) => item.id).toList();
    _outfit = _initialOutfit;
    _parts = effectiveParts(_model, _outfit);
    _initialColors =
        (ref.read(avatarColorsProvider)[_model.id] ?? AvatarColors.empty)
            .restrictTo(_parts);
    _draft = _previewColors = _initialColors;
    _selectedPart = _parts.first;
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

  void _editOutfit(List<String> outfit) {
    if (_saving || listEquals(outfit, _outfit)) return;
    setState(() {
      _outfit = outfit;
      _parts = effectiveParts(_model, _outfit);
      if (!_parts.contains(_selectedPart)) _selectedPart = _parts.first;
    });
  }

  void _selectItem(AvatarItem item, bool borrowed) {
    final current = _outfit.contains(item.id);
    if (current == borrowed) return;
    _editOutfit([
      for (final id in _outfit)
        if (id != item.id) id,
      if (borrowed) item.id,
    ]);
  }

  Future<void> _clearOutfit() async {
    if (await _confirm('Bỏ phối đồ?', 'Bỏ phối đồ') && mounted) {
      _editOutfit(const []);
    }
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

  Map<String, T> _withModelValue<T>(Map<String, T> values, T? value) {
    final updated = {...values};
    if (value == null) {
      updated.remove(_model.id);
    } else {
      updated[_model.id] = value;
    }
    return Map.unmodifiable(updated);
  }

  Future<void> _save() async {
    if (_saving) return;
    final colors = ref.read(avatarColorsProvider.notifier);
    final outfits = ref.read(avatarOutfitsProvider.notifier);
    final previousColors = colors.state[_model.id];
    final previousOutfit = outfits.state[_model.id];
    final draftColors = _draft.restrictTo(_parts);
    final nextColors = _withModelValue(
      colors.state,
      draftColors == AvatarColors.empty ? null : draftColors,
    );
    final nextOutfits = _withModelValue(
      outfits.state,
      _outfit.isEmpty ? null : List<String>.unmodifiable(_outfit),
    );

    final storage = ref.read(secureStorageProvider);
    setState(() => _saving = true);
    outfits.state = nextOutfits;
    colors.state = nextColors;
    var outfitsSaved = false;
    try {
      await storage.saveAvatarOutfitsJson(encodeAvatarOutfits(nextOutfits));
      outfitsSaved = true;
      await storage.saveAvatarColorsJson(encodeAvatarColorsMap(nextColors));
    } catch (_) {
      final restoredOutfits = _withModelValue(
        outfits.mounted ? outfits.state : nextOutfits,
        previousOutfit,
      );
      if (outfits.mounted) outfits.state = restoredOutfits;
      if (colors.mounted) {
        colors.state = _withModelValue(colors.state, previousColors);
      }
      if (outfitsSaved && !listEquals(previousOutfit ?? const [], _outfit)) {
        try {
          await storage.saveAvatarOutfitsJson(
            encodeAvatarOutfits(restoredOutfits),
          );
        } catch (_) {
          // Report the save failure even if storage also rejects the rollback.
        }
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
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewHeight = (MediaQuery.sizeOf(context).height * 0.4)
        .clamp(240.0, 360.0)
        .toDouble();

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
                        colors: _previewColors.restrictTo(_parts),
                        outfit: _outfit,
                        semanticsLabel: 'Xem trước nhân vật 3D',
                      ),
                    ),
                    if (_tabs case final TabController tabs)
                      TabBar(
                        controller: tabs,
                        onTap: (index) => setState(() => _tab = index),
                        tabs: const [
                          Tab(text: 'Màu sắc', height: 48),
                          Tab(text: 'Phối đồ', height: 48),
                        ],
                      ),
                    if (_tab == 0)
                      ..._colorControls()
                    else
                      ..._outfitControls(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _colorControls() => [
    Wrap(spacing: 8, children: [for (final part in _parts) _partChip(part)]),
    const SizedBox(height: 16),
    AbsorbPointer(
      absorbing: _saving,
      child: Semantics(
        label: 'Chọn màu ${_selectedPart.label}',
        child: HueRingPicker(
          pickerColor:
              _draft[_selectedPart] ??
              originalColorFor(_model, _outfit, _selectedPart)!,
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
      onPressed: _saving || _draft == AvatarColors.empty ? null : _reset,
      child: const Text('Khôi phục mặc định'),
    ),
  ];

  List<Widget> _outfitControls() => [
    for (final item in _items) ...[
      const SizedBox(height: 16),
      Text(item.slot.label, style: Theme.of(context).textTheme.titleSmall),
      Wrap(
        spacing: 8,
        children: [
          _outfitChoice(item, borrowed: false),
          _outfitChoice(item, borrowed: true),
        ],
      ),
    ],
    const SizedBox(height: 16),
    OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: _saving || _outfit.isEmpty ? null : _clearOutfit,
      child: const Text('Bỏ phối đồ'),
    ),
  ];

  Widget _outfitChoice(AvatarItem item, {required bool borrowed}) {
    final label = borrowed ? item.label : 'Đồ gốc';
    return Semantics(
      label: '${item.slot.label}: $label',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: ChoiceChip(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          label: ExcludeSemantics(child: Text(label)),
          selected: _outfit.contains(item.id) == borrowed,
          onSelected: _saving ? null : (_) => _selectItem(item, borrowed),
        ),
      ),
    );
  }

  Widget _partChip(AvatarPart part) {
    final color = _draft[part] ?? originalColorFor(_model, _outfit, part);
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
