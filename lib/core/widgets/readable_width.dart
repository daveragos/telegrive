import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../platform/app_platform.dart';

/// The widest a page of settings and explanations reads well at.
const double readableWidth = 760;

/// [bottom] below a list, and on a computer the padding at each side that
/// keeps it [readableWidth] wide in the middle of a wider page. Padding
/// rather than a narrower list keeps the scrollbar at the window's edge.
EdgeInsets readableListPadding(BuildContext context, {double bottom = 0}) {
  if (!AppPlatform.isDesktop) return EdgeInsets.only(bottom: bottom);
  final side = math.max(0.0, (MediaQuery.sizeOf(context).width - _sidebarAllowance - readableWidth) / 2);
  return EdgeInsets.fromLTRB(side, 0, side, bottom);
}

/// What the sidebar beside a page takes of the window's width.
const double _sidebarAllowance = 233;
