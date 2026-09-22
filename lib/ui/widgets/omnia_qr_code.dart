import 'package:flutter/material.dart';

/// Peintre de matrice QR Code avec style OMNIA.
class OmniaQrPainter extends CustomPainter {
  OmniaQrPainter({
    required this.data,
    required this.primaryColor,
    required this.backgroundColor,
  });

  final String data;
  final Color primaryColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final matrix = _generateMatrix(data);
    final count = matrix.length;
    final cellSize = size.width / count;

    final cellPaint = Paint()..color = primaryColor;

    for (var r = 0; r < count; r++) {
      for (var c = 0; c < count; c++) {
        if (matrix[r][c]) {
          final rect = Rect.fromLTWH(
            c * cellSize,
            r * cellSize,
            cellSize,
            cellSize,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.15)),
            cellPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant OmniaQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }

  /// Génère une matrice binaire déterministe pour le payload d'appairage.
  static List<List<bool>> _generateMatrix(String text) {
    const size = 25;
    final grid = List.generate(size, (_) => List.filled(size, false));

    void drawFinderPattern(int row, int col) {
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 7; c++) {
          final isBorder = r == 0 || r == 6 || c == 0 || c == 6;
          final isCenter = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          grid[row + r][col + c] = isBorder || isCenter;
        }
      }
    }

    // Motifs de synchronisation (Finder patterns)
    drawFinderPattern(0, 0);
    drawFinderPattern(0, size - 7);
    drawFinderPattern(size - 7, 0);

    // Lignes de synchronisation
    for (var i = 8; i < size - 8; i++) {
      grid[6][i] = i % 2 == 0;
      grid[i][6] = i % 2 == 0;
    }

    // Encodage haché du contenu pour les données
    final bytes = text.codeUnits;
    var byteIdx = 0;
    var bitIdx = 0;

    for (var r = 1; r < size - 1; r++) {
      for (var c = 1; c < size - 1; c++) {
        final inTopLeft = r < 9 && c < 9;
        final inTopRight = r < 9 && c >= size - 9;
        final inBottomLeft = r >= size - 9 && c < 9;
        if (inTopLeft || inTopRight || inBottomLeft || r == 6 || c == 6) {
          continue;
        }

        final b = bytes[byteIdx % bytes.length];
        final bit = ((b >> (bitIdx % 8)) & 1) == 1;
        // Masquage XOR pour dispersion homogène
        grid[r][c] = bit ^ ((r + c) % 2 == 0);

        bitIdx++;
        if (bitIdx % 8 == 0) byteIdx++;
      }
    }

    return grid;
  }
}

/// Widget affichant un QR code OMNIA Connect élégant.
class OmniaQrCode extends StatelessWidget {
  const OmniaQrCode({
    super.key,
    required this.data,
    this.size = 200,
    required this.color,
    required this.backgroundColor,
  });

  final String data;
  final double size;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: CustomPaint(
        size: Size(size - 24, size - 24),
        painter: OmniaQrPainter(
          data: data,
          primaryColor: color,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}
