import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'assistant_cards.dart';
import 'assistant_models.dart';

/// One chat bubble. User turns render right-aligned on the brand color;
/// assistant turns render left-aligned on a white hairline card with markdown.
class AssistantChatBubble extends StatelessWidget {
  const AssistantChatBubble({
    super.key,
    required this.message,
    this.streaming = false,
    this.onCopy,
    this.onFeedback,
  });

  final AssistantMessage message;
  final bool streaming;
  final VoidCallback? onCopy;
  final void Function(String value)? onFeedback;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final width = MediaQuery.of(context).size.width;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: width * (isUser ? 0.76 : 0.88)),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: isUser ? 10 : 12),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primary : AppColors.surface,
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(5),
              )
            : const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
        border: isUser ? null : Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: isUser
          ? Text(
              message.content,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, height: 1.45),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Native cards (tool-derived data) render above the prose.
                for (final card in message.cards)
                  AssistantCardView(card: card),
                MarkdownBody(
                  data: message.content.isEmpty && streaming
                      ? '…'
                      : message.content,
                  selectable: false,
                  styleSheet: _markdownStyle(context),
                  // Without a handler, rendered links do nothing on tap.
                  onTapLink: (text, href, title) {
                    if (href == null) return;
                    final uri = Uri.tryParse(href);
                    if (uri == null ||
                        !(uri.isScheme('http') || uri.isScheme('https'))) {
                      return; // http/https only — never intent:/file: etc.
                    }
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ],
            ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser) const _BotLabel(),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: message.content.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')));
                    },
              child: bubble,
            ),
          ),
          if (!isUser && !streaming && message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    onTap: onCopy,
                  ),
                  if (onFeedback != null) ...[
                    _MiniAction(
                      icon: message.feedback == 'UP'
                          ? Icons.thumb_up_alt_rounded
                          : Icons.thumb_up_alt_outlined,
                      tooltip: 'Helpful',
                      active: message.feedback == 'UP',
                      onTap: () => onFeedback!('UP'),
                    ),
                    _MiniAction(
                      icon: message.feedback == 'DOWN'
                          ? Icons.thumb_down_alt_rounded
                          : Icons.thumb_down_alt_outlined,
                      tooltip: 'Not helpful',
                      active: message.feedback == 'DOWN',
                      onTap: () => onFeedback!('DOWN'),
                    ),
                  ],
                  if (message.createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        DateFormat('h:mm a').format(message.createdAt!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.faint,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static MarkdownStyleSheet _markdownStyle(BuildContext context) {
    const body = TextStyle(
        fontSize: 15, height: 1.47, color: AppColors.inkSoft);
    return MarkdownStyleSheet(
      p: body,
      listBullet: body,
      a: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.primary, // runtime branding — not a const
          decoration: TextDecoration.underline),
      strong: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
      h1: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          color: AppColors.ink),
      h2: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.ink),
      h3: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
      code: const TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        color: AppColors.ink,
        backgroundColor: AppColors.surfaceAlt,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairlineSoft),
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      tableBorder: TableBorder.all(color: AppColors.hairline),
      tableHead: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
      tableBody: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
    );
  }
}

/// "✦ Nava360 Assistant" label above an assistant reply.
class _BotLabel extends ConsumerWidget {
  const _BotLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productName = ref.watch(brandingProvider).productName;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.deep,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_rounded,
                size: 11, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$productName Assistant',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon,
                size: 16, color: active ? AppColors.primary : AppColors.faint),
          ),
        ),
      ),
    );
  }
}

/// Animated three-dot "thinking" indicator with an optional activity label
/// ("Checking your leave balance…").
class AssistantThinkingIndicator extends StatefulWidget {
  const AssistantThinkingIndicator({super.key, this.label});

  final String? label;

  @override
  State<AssistantThinkingIndicator> createState() =>
      _AssistantThinkingIndicatorState();
}

class _AssistantThinkingIndicatorState extends State<AssistantThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_c.value * 3 - i).clamp(0.0, 1.0);
                  final bounce = (t < 0.5 ? t : 1 - t) * 2;
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    transform:
                        Matrix4.translationValues(0, -3.0 * bounce, 0),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: 0.4 + 0.6 * bounce),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
            if (widget.label != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.label!,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty-state suggestions ("Try asking"): a white grouped list, one row per
/// prompt.
class AssistantSuggestions extends StatelessWidget {
  const AssistantSuggestions({super.key, required this.onPick});

  final void Function(String prompt) onPick;

  static const _suggestions = [
    'How many casual leaves do I have left?',
    'Show my attendance this month',
    'When is the next holiday?',
    'What is pending on me for approval?',
    'What was my last net salary?',
    'Which assets are assigned to me?',
  ];

  static const _icons = [
    Icons.event_available_rounded,
    Icons.schedule_rounded,
    Icons.wb_sunny_outlined,
    Icons.assignment_turned_in_outlined,
    Icons.receipt_long_rounded,
    Icons.laptop_mac_rounded,
  ];

  static Color _tone(int i) => switch (i % 6) {
        0 => AppColors.primary,
        1 => AppColors.info,
        2 => const Color(0xFF9A5B00),
        3 => const Color(0xFF4253A8),
        4 => AppColors.success,
        _ => AppColors.pink,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(title: 'Try asking', small: true),
        const SizedBox(height: 8),
        ProListGroup(
          children: [
            for (var i = 0; i < _suggestions.length; i++)
              ProListRow(
                leading: ProIconWell(icon: _icons[i], color: _tone(i)),
                title: _suggestions[i],
                titleMaxLines: 2,
                chevron: false,
                trailing: const Icon(Icons.north_east_rounded,
                    size: 16, color: Color(0xFF9FB0B4)),
                onTap: () => onPick(_suggestions[i]),
              ),
          ],
        ),
      ],
    );
  }
}
