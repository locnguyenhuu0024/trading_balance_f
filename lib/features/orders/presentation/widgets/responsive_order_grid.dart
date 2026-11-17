import '../../../../core/widgets/app_motion.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

int orderGridColumnCountForWidth(double width) {
  if (width < 600) return 1;
  if (width < 900) return 2;
  if (width < 1600) return 3;
  return 4;
}

class ResponsiveOrderGrid extends StatelessWidget {
  const ResponsiveOrderGrid({
    super.key,
    required this.children,
    this.cardExtent,
  });

  final List<Widget> children;
  final double? cardExtent;

  @override
  Widget build(BuildContext context) {
    return AppEntranceScope(child: LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = orderGridColumnCountForWidth(constraints.maxWidth);
        const padding = EdgeInsets.all(AppTokens.space3);

        if (columnCount == 1) {
          return ListView.separated(
            padding: padding,
            itemCount: children.length,
            itemBuilder: (context, index) => AppEntrance(index: index, child: children[index]),
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppTokens.space2),
          );
        }

        if (cardExtent == null) {
          final rowCount = (children.length + columnCount - 1) ~/ columnCount;
          return ListView.separated(
            padding: padding,
            itemCount: rowCount,
            itemBuilder: (context, rowIndex) {
              final firstChildIndex = rowIndex * columnCount;
              return AppEntrance(index: rowIndex, child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(columnCount * 2 - 1, (index) {
                  if (index.isOdd) {
                    return const SizedBox(width: AppTokens.space3);
                  }

                  final columnIndex = index ~/ 2;
                  final childIndex = firstChildIndex + columnIndex;
                  return Expanded(
                    child: childIndex < children.length
                        ? children[childIndex]
                        : const SizedBox.shrink(),
                  );
                }),
              ));
            },
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppTokens.space3),
          );
        }

        final rowCount = (children.length + columnCount - 1) ~/ columnCount;
        return ListView.separated(
          padding: padding,
          itemCount: rowCount,
          separatorBuilder: (context, index) => const SizedBox(height: AppTokens.space3),
          itemBuilder: (context, rowIndex) => AppEntrance(
            index: rowIndex,
            child: SizedBox(
              height: cardExtent,
              child: Row(children: List.generate(columnCount * 2 - 1, (index) {
                if (index.isOdd) return const SizedBox(width: AppTokens.space3);
                final childIndex = rowIndex * columnCount + index ~/ 2;
                return Expanded(child: childIndex < children.length ? children[childIndex] : const SizedBox.shrink());
              })),
            ),
          ),
        );
      },
    ));
  }
}
