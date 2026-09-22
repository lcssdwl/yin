import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/constants.dart';

/// 旋转唱片(黑胶 + 封面)
///
/// 播放时匀速旋转,暂停时停在原地
class RotatingCover extends StatefulWidget {
  final String imageUrl;
  final double size;
  final bool rotating;

  const RotatingCover({
    super.key,
    required this.imageUrl,
    this.size = 240,
    this.rotating = true,
  });

  @override
  State<RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<RotatingCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    if (widget.rotating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant RotatingCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rotating != oldWidget.rotating) {
      if (widget.rotating) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl.isEmpty ? AppConstants.defaultCover : widget.imageUrl;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF1A1A1A),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.grey.shade800,
                child: const Icon(Icons.music_note, color: Colors.white54),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade800,
                child: const Icon(Icons.music_note, color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
