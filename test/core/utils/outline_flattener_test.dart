import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/outline_flattener.dart';

class TestNode {
  const TestNode(this.title, this.page, [this.children = const []]);
  final String title;
  final int? page;
  final List<TestNode> children;
}

List<OutlineItem> flatten(List<TestNode> roots, {int maxDepth = 8}) => flattenOutline<TestNode>(
      roots,
      title: (n) => n.title,
      page: (n) => n.page,
      children: (n) => n.children,
      maxDepth: maxDepth,
    );

void main() {
  test('parcours en profondeur, avec la profondeur de chaque entrée', () {
    final items = flatten(const [
      TestNode('Introduction', 1),
      TestNode('Chapitre 1', 3, [
        TestNode('1.1', 4),
        TestNode('1.2', 7, [TestNode('1.2.1', 8)]),
      ]),
      TestNode('Annexes', 40),
    ]);

    expect(items.map((i) => i.title), ['Introduction', 'Chapitre 1', '1.1', '1.2', '1.2.1', 'Annexes']);
    expect(items.map((i) => i.depth), [0, 0, 1, 1, 2, 0]);
    expect(items.map((i) => i.page), [1, 3, 4, 7, 8, 40]);
  });

  test('sommaire vide', () {
    expect(flatten(const []), isEmpty);
  });

  test('une entrée sans destination garde page null', () {
    final items = flatten(const [TestNode('Sans lien', null)]);
    expect(items.single.page, isNull);
  });

  test('la profondeur est plafonnée', () {
    final deep = TestNode('a', 1, [
      TestNode('b', 2, [
        TestNode('c', 3, [TestNode('d', 4)]),
      ]),
    ]);
    final items = flatten([deep], maxDepth: 1);
    expect(items.map((i) => i.title), ['a', 'b']);
  });

  test('les titres sont nettoyés de leurs espaces', () {
    final items = flatten(const [TestNode('  Titre  ', 1)]);
    expect(items.single.title, 'Titre');
  });
}
