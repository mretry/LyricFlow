import 'package:flutter/material.dart';

import '../models/timed_cue.dart';

class CueList extends StatefulWidget {
  const CueList({
    required this.cues,
    required this.activeIndex,
    required this.onTapCue,
    required this.onManualScroll,
    required this.follow,
    super.key,
  });

  final List<TimedCue> cues;
  final int activeIndex;
  final ValueChanged<TimedCue> onTapCue;
  final VoidCallback onManualScroll;
  final bool follow;

  @override
  State<CueList> createState() => CueListState();
}

class CueListState extends State<CueList> {
  static const rowHeight = 96.0;
  final ScrollController _scroll = ScrollController();
  double _viewport = 400;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => jumpToActive(animate: false));
  }

  @override
  void didUpdateWidget(covariant CueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.follow &&
        (widget.activeIndex != oldWidget.activeIndex ||
            !oldWidget.follow || widget.cues.length != oldWidget.cues.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => jumpToActive());
    }
  }

  void jumpToActive({bool animate = true}) {
    if (!mounted || !_scroll.hasClients || widget.activeIndex < 0) return;
    final goal = (widget.activeIndex * rowHeight - _viewport * .38)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(
        goal,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(goal);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cues.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '还没有同步歌词\n导入 .lrc / .srt / .vtt 后，就能点击任意句跳转播放',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9F9CAB), height: 1.8),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      _viewport = constraints.maxHeight;
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null && widget.follow) {
            widget.onManualScroll();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          itemExtent: rowHeight,
          padding: EdgeInsets.symmetric(
            horizontal: 22,
            vertical: (_viewport * .25).clamp(26.0, 180.0),
          ),
          itemCount: widget.cues.length,
          itemBuilder: (context, index) {
            final cue = widget.cues[index];
            final active = index == widget.activeIndex;
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => widget.onTapCue(cue),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF313044) : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (active)
                      Container(
                        height: 36,
                        width: 3,
                        margin: const EdgeInsets.only(right: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9ABFF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: active ? 23 : 20,
                          height: 1.28,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? const Color(0xFFF8F5FF)
                              : const Color(0xFF9895AA),
                        ),
                        child: Text(cue.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }
}
