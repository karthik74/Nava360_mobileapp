import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'assistant_cards.dart';
import 'assistant_models.dart';

/// One chat bubble. User turns render right-aligned on the brand color;
/// assistant turns render left-aligned on a white card with markdown.
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
    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        border: isUser ? null : Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.soft,
      ),
      child: isUser
          ? Text(
              message.content,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13.5, height: 1.4),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
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
              padding: const EdgeInsets.only(top: 2, left: 4),
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
                            fontSize: 10, color: AppColors.muted),
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
        fontSize: 13.5, height: 1.45, color: AppColors.inkSoft);
    return MarkdownStyleSheet(
      p: body,
      listBullet: body,
      a: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.primary, // runtime branding — not a const
          decoration: TextDecoration.underline),
      strong: const TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
      h1: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
      h2: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
      h3: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
      code: TextStyle(
        fontSize: 12.5,
        fontFamily: 'monospace',
        color: AppColors.ink,
        backgroundColor: AppColors.surfaceAlt,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      tableBorder: TableBorder.all(color: AppColors.hairline),
      tableHead: const TextStyle(
          fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
      tableBody: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon,
              size: 15, color: active ? AppColors.primary : AppColors.muted),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
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
                          .withOpacity(0.4 + 0.6 * bounce),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
            if (widget.label != null) ...[
              const SizedBox(width: 8),
              Text(
                widget.label!,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty-state suggestion chips ("What can you ask?").
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final s in _suggestions)
          ActionChip(
            label: Text(s,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            onPressed: () => onPick(s),
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.hairline),
          ),
      ],
    );
  }
}
