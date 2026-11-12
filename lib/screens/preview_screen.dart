import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdfx/pdfx.dart';
import 'package:open_filex/open_filex.dart';
import '../theme/app_colors.dart';
import '../utils/file_type_helper.dart';

/// Full-screen file preview.
/// Deletes [filePath] on dispose when [isTempFile] is true. Los temporales de
/// archivos del servidor los gestiona PreviewService (caché), no esta pantalla.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.isTempFile = false,
  });

  final String filePath;
  final String fileName;
  final bool isTempFile;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  @override
  void dispose() {
    if (widget.isTempFile) {
      final f = File(widget.filePath);
      f.exists().then((exists) { if (exists) f.delete(); });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = FileTypeHelper.categorize(widget.fileName);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          widget.fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _buildContent(category),
      ),
    );
  }

  Widget _buildContent(FileCategory category) {
    switch (category) {
      case FileCategory.image:
        return _ImagePreview(filePath: widget.filePath);
      case FileCategory.svg:
        return _SvgPreview(filePath: widget.filePath);
      case FileCategory.video:
        return _VideoPreview(filePath: widget.filePath);
      case FileCategory.audio:
        return _AudioPreview(filePath: widget.filePath, fileName: widget.fileName);
      case FileCategory.pdf:
        return _PdfPreview(filePath: widget.filePath);
      case FileCategory.text:
        return _TextPreview(filePath: widget.filePath);
      case FileCategory.unknown:
        return _UnknownPreview(filePath: widget.filePath, fileName: widget.fileName);
    }
  }
}

// ─── Image ────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    // Decodificar a ~2× la resolución de pantalla en lugar del tamaño
    // original (una foto de 48 MP ocupa ~190 MB decodificada).
    final media = MediaQuery.of(context);
    final targetWidth = (media.size.width * media.devicePixelRatio * 2).round();
    return PhotoView(
      imageProvider: ResizeImage.resizeIfNeeded(targetWidth, null, FileImage(File(filePath))),
      errorBuilder: (_, _, _) => const _PreviewError('No se pudo abrir la imagen.'),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
    );
  }
}

// ─── SVG ──────────────────────────────────────────────────────────────

class _SvgPreview extends StatelessWidget {
  const _SvgPreview({required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.file(
        File(filePath),
        fit: BoxFit.contain,
      ),
    );
  }
}

// ─── Video ────────────────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.filePath});
  final String filePath;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  ChewieController? _chewie;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: _controller,
          autoPlay: false,
          looping: false,
        );
      });
    }).catchError((Object _) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _PreviewError(
        'No se pudo reproducir este video en el dispositivo.',
        filePath: widget.filePath,
      );
    }
    if (_chewie == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewie!);
  }
}

// ─── Audio ────────────────────────────────────────────────────────────

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({required this.filePath, required this.fileName});
  final String filePath;
  final String fileName;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _error = false;
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      await _player.play(DeviceFileSource(widget.filePath));
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _PreviewError(
        'No se pudo reproducir este audio en el dispositivo.',
        filePath: widget.filePath,
      );
    }
    final playing = _state == PlayerState.playing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎵', style: TextStyle(fontSize: 72)),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.fileName,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_duration > Duration.zero)
              Slider(
                value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
                max: _duration.inMilliseconds.toDouble(),
                activeColor: AppColors.accentPrimary,
                inactiveColor: AppColors.borderMedium,
                onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_position), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                Text(_fmt(_duration), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            IconButton(
              iconSize: 56,
              tooltip: playing ? 'Pausar' : 'Reproducir',
              color: AppColors.accentPrimary,
              icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded),
              onPressed: () {
                if (playing) {
                  _player.pause();
                } else {
                  _play();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── PDF ──────────────────────────────────────────────────────────────

class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.filePath});
  final String filePath;

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late PdfController _controller;

  @override
  void initState() {
    super.initState();
    // PdfController espera el Future dentro de un try/catch; el error se
    // muestra con el errorBuilder de PdfView.
    _controller = PdfController(document: PdfDocument.openFile(widget.filePath));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfView(
      controller: _controller,
      scrollDirection: Axis.vertical,
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        errorBuilder: (_, _) => _PreviewError(
          'No se pudo abrir el PDF.',
          filePath: widget.filePath,
        ),
      ),
    );
  }
}

// ─── Text ─────────────────────────────────────────────────────────────

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.filePath});
  final String filePath;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  /// Se muestran como mucho los primeros 256 KB: un único Text con decenas de
  /// MB congela la UI.
  static const _maxBytes = 256 * 1024;

  String? _content;
  bool _truncated = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final length = await file.length();
      final raf = await file.open();
      List<int> bytes;
      try {
        bytes = await raf.read(_maxBytes);
      } finally {
        await raf.close();
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (mounted) {
        setState(() {
          _content = text;
          _truncated = length > _maxBytes;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Text('No se pudo leer el archivo.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    if (_content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_truncated)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vista parcial: se muestran los primeros 256 KB.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => OpenFilex.open(widget.filePath),
                      child: const Text('Abrir completo'),
                    ),
                  ],
                ),
              ),
            SelectableText(
              _content!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Unknown ──────────────────────────────────────────────────────────

class _UnknownPreview extends StatelessWidget {
  const _UnknownPreview({required this.filePath, required this.fileName});
  final String filePath;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📁', style: TextStyle(fontSize: 72)),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Este tipo de archivo no se puede previsualizar.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentPrimary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir con…'),
              onPressed: () => OpenFilex.open(filePath),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error ────────────────────────────────────────────────────────────

class _PreviewError extends StatelessWidget {
  const _PreviewError(this.message, {this.filePath});
  final String message;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (filePath != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Abrir con otra app'),
                onPressed: () => OpenFilex.open(filePath!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
