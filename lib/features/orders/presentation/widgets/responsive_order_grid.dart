import 'package:flutter/material.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = orderGridColumnCountForWidth(constraints.maxWidth);
        const padding = EdgeInsets.all(12);

        if (columnCount == 1) {
          return ListView.separated(
            padding: padding,
            itemCount: children.length,
            itemBuilder: (context, index) => children[index],
            separatorBuilder: (context, index) => const SizedBox(height: 8),
          );
        }

        if (cardExtent == null) {
          final rowCount = (children.length + columnCount - 1) ~/ columnCount;
          return ListView.separated(
            padding: padding,
            itemCount: rowCount,
            itemBuilder: (context, rowIndex) {
              final firstChildIndex = rowIndex * columnCount;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(columnCount * 2 - 1, (index) {
                  if (index.isOdd) return const SizedBox(width: 12);

                  final columnIndex = index ~/ 2;
                  final childIndex = firstChildIndex + columnIndex;
                  return Expanded(
                    child: childIndex < children.length
                        ? children[childIndex]
                        : const SizedBox.shrink(),
                  );
                }),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
          );
        }

        return GridView.builder(
          padding: padding,
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: cardExtent,
          ),
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}
