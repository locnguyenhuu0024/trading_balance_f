import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_content_frame.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../../../core/widgets/responsive_form_content.dart';
import '../../avatar/domain/avatar_model.dart';

final _isSavingAvatarModelProvider = StateProvider<bool>((ref) => false);

class SettingsAvatarModelPage extends ConsumerWidget {
  const SettingsAvatarModelPage({super.key});

  Future<void> _selectModel(
    BuildContext context,
    WidgetRef ref,
    AvatarModel model,
  ) async {
    final saving = ref.read(_isSavingAvatarModelProvider.notifier);
    if (saving.state) return;

    final selection = ref.read(avatarModelIdProvider.notifier);
    final previousId = selection.state;
    final storage = ref.read(secureStorageProvider);
    final messenger = ScaffoldMessenger.of(context);
    saving.state = true;
    selection.state = model.id;
    try {
      await storage.saveAvatarModelId(model.id);
    } catch (_) {
      if (selection.mounted) selection.state = previousId;
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Không lưu được cài đặt')),
        );
      }
    } finally {
      if (saving.mounted) saving.state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = avatarModelById(ref.watch(avatarModelIdProvider)).id;
    final isSaving = ref.watch(_isSavingAvatarModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chọn nhân vật')),
      body: NavigationContentFrame(
        child: SafeArea(
          top: false,
          child: ListView(
            children: [
              ResponsiveFormContent(
                child: Card(
                  child: Column(
                    children: [
                      for (final model in avatarModels)
                        Semantics(
                          key: ValueKey('avatar-model-${model.id}'),
                          selected: model.id == selectedId,
                          button: true,
                          child: ListTile(
                            minTileHeight: 56,
                            enabled: !isSaving,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox.square(
                                dimension: 48,
                                child: Image.asset(
                                  model.thumbnail,
                                  fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.view_in_ar),
                                ),
                              ),
                            ),
                            title: Text(model.name),
                            subtitle: Text(model.credit),
                            trailing: model.id == selectedId
                                ? const Icon(Icons.check_circle)
                                : null,
                            onTap: isSaving
                                ? null
                                : () => _selectModel(context, ref, model),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
