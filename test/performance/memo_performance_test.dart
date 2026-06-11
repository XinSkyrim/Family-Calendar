import 'dart:math' as math;

import 'package:calendar/testing/performance/memo_benchmark_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'performance_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PerformanceReporter reporter;
  const dataSizes = <int>[100, 1000, 5000];
  const transformIterations = 12;
  const widgetIterations = 8;
  const scrollIterations = 10;

  setUpAll(() async {
    reporter = await PerformanceReporter.create();
  });

  tearDownAll(() async {
    await reporter.save();
    // ignore: avoid_print
    print('Performance CSV saved to: ${reporter.outputPath}');
  });

  group('Memo performance benchmarks', () {
    for (final dataSize in dataSizes) {
      test('data_transform_$dataSize', () {
        final memos = MemoBenchmarkModels.generateSampleMemos(dataSize);
        final samples = _measureSamples(
          iterations: transformIterations,
          action: () {
            final sections = MemoBenchmarkModels.buildSections(memos);
            if (sections.isEmpty) {
              throw StateError('Expected memo sections for dataset $dataSize');
            }
          },
        );

        reporter.addRow(
          _rowFromSamples(
            metric: 'memo_section_transform',
            datasetSize: dataSize,
            iterations: transformIterations,
            samples: samples,
            notes: 'Transforms raw memo records into dated sections.',
          ),
        );
      });

      testWidgets('widget_render_$dataSize', (tester) async {
        final memos = MemoBenchmarkModels.generateSampleMemos(dataSize);
        final sections = MemoBenchmarkModels.buildSections(memos);

        final samples = await _measureWidgetSamples(
          tester,
          iterations: widgetIterations,
          action: () async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: MemoBenchmarkListView(sections: sections),
                ),
              ),
            );
            await tester.pump();
          },
        );

        expect(find.byType(MemoBenchmarkListView), findsOneWidget);

        reporter.addRow(
          _rowFromSamples(
            metric: 'memo_list_initial_render',
            datasetSize: dataSize,
            iterations: widgetIterations,
            samples: samples,
            notes: 'Builds the benchmark memo list widget tree.',
          ),
        );
      });
    }

    testWidgets('scroll_stress_5000', (tester) async {
      const dataSize = 5000;
      final memos = MemoBenchmarkModels.generateSampleMemos(dataSize);
      final sections = MemoBenchmarkModels.buildSections(memos);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoBenchmarkListView(sections: sections),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listFinder = find.byKey(const ValueKey('memo_benchmark_scroll_view'));
      expect(listFinder, findsOneWidget);

      final samples = <double>[];
      for (var i = 0; i < scrollIterations; i++) {
        final stopwatch = Stopwatch()..start();
        await tester.drag(listFinder, const Offset(0, -1200));
        await tester.pump();
        await tester.drag(listFinder, const Offset(0, 1200));
        await tester.pump();
        stopwatch.stop();
        samples.add(stopwatch.elapsedMicroseconds / 1000.0);
      }

      reporter.addRow(
        _rowFromSamples(
          metric: 'memo_list_scroll_stress',
          datasetSize: dataSize,
          iterations: scrollIterations,
          samples: samples,
          notes: 'Repeated up/down drag benchmark for large memo list.',
        ),
      );
    });
  });
}

List<double> _measureSamples({
  required int iterations,
  required void Function() action,
}) {
  for (var i = 0; i < 3; i++) {
    action();
  }

  final samples = <double>[];
  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / 1000.0);
  }
  return samples;
}

Future<List<double>> _measureWidgetSamples(
    WidgetTester tester, {
      required int iterations,
      required Future<void> Function() action,
    }) async {
  for (var i = 0; i < 2; i++) {
    await action();
  }

  final samples = <double>[];
  for (var i = 0; i < iterations; i++) {
    final stopwatch = Stopwatch()..start();
    await action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / 1000.0);
  }
  return samples;
}

PerformanceReportRow _rowFromSamples({
  required String metric,
  required int datasetSize,
  required int iterations,
  required List<double> samples,
  required String notes,
}) {
  final averageMs = samples.reduce((a, b) => a + b) / samples.length;
  final minMs = samples.reduce(math.min);
  final maxMs = samples.reduce(math.max);

  return PerformanceReportRow(
    metric: metric,
    datasetSize: datasetSize,
    iterations: iterations,
    averageMs: averageMs,
    minMs: minMs,
    maxMs: maxMs,
    notes: notes,
  );
}

class MemoBenchmarkListView extends StatelessWidget {
  const MemoBenchmarkListView({super.key, required this.sections});

  final List<MemoBenchmarkSection> sections;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('memo_benchmark_scroll_view'),
      itemCount: sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sections[sectionIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                section.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...section.items.map(
                  (item) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(item.dateLabel),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}