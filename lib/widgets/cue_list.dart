import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/timed_cue.dart';

class CueList extends StatefulWidget {
  const CueList({
    required this.cues,
    required this.activeIndex,
    required this.onTapCue,
    required this.onManualScroll,
    required this.follow,
    required this.fontSize,
    super.key,
  });

  final List<TimedCue> cues;
  final int activeIndex;
  final ValueChanged<TimedCue> onTapCue;
  final VoidCallback onManualScroll;
  final bool follow;
  final double fontSize;

  @override
  State<CueList> createState() => CueListState();
}

class CueListState extends State<CueList> {
  final ItemScrollController _scroll = ItemScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => jumpToActive(animate: false),
    );
  }

  @override
  void didUpdateWidget(covariant CueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.follow &&
        (widget.activeIndex != oldWidget.activeIndex ||
            !oldWidget.follow ||
            widget.cues.length != oldWidget.cues.length ||
            widget.fontSize != oldWidget.fontSize)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => jumpToActive());
    }
  }

  void jumpToActive({bool animate = true}) {
    if (!mounted ||
        !_scroll.isAttached ||
        widget.activeIndex < 0 ||
        widget.activeIndex >= widget.cues.length) {
      return;
    }
    if (!animate) {
      _scroll.jumpTo(index: widget.activeIndex, alignment: 0.38);
      return;
    }
    unawaited(
      _scroll.scrollTo(
        index: widget.activeIndex,
        alignment: 0.38,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cues.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '还没有同步歌词\n导入 .lrc / .srt / .vtt / .ass 后，就能点击任意句跳转播放',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9F9CAB), height: 1.8),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            widget.follow) {
          widget.onManualScroll();
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _scroll,
        itemCount: widget.cues.length,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 72),
        itemBuilder: (context, index) {
          final cue = widget.cues[index];
          final active = index == widget.activeIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => widget.onTapCue(cue),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: (widget.fontSize * .48)
                        .clamp(8.0, 18.0)
                        .toDouble(),
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF313044)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (active)
                        Container(
                          height: (widget.fontSize * 1.65)
                              .clamp(28.0, 60.0)
                              .toDouble(),
                          width: 3,
                          margin: const EdgeInsets.only(right: 14, top: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC9ABFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            fontSize: active
                                ? widget.fontSize + 2
                                : widget.fontSize,
                            height: 1.32,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? const Color(0xFFF8F5FF)
                                : const Color(0xFFAAA7BC),
                          ),
                          child: Text(
                            cue.text,
                            softWrap: true,
                            maxLines: null,
                            overflow: TextOverflow.visible,
                            textWidthBasis: TextWidthBasis.parent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
