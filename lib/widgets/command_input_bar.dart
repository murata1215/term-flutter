import 'package:flutter/material.dart';

/// コマンド入力バーウィジェット
///
/// ターミナル画面の下部に固定表示されるコンパクトな入力バー。
/// 構成: [↑][↓] [TextField] [送信ボタン]
///
/// ↑↓ボタンはシェルに矢印キーのエスケープシーケンスを送信する。
/// これによりbash自体が履歴を展開するため、su後のユーザーの履歴にも対応できる。
///
/// [enabled] が false の場合、入力フィールドと全ボタンが無効化される。
/// SSH切断時に使用し、再接続を促すためにヒントテキストを変更する。
class CommandInputBar extends StatefulWidget {
  /// コマンド送信時に呼び出されるコールバック
  final void Function(String command) onCommandSubmit;

  /// ↑ボタン押下時に呼び出されるコールバック
  final VoidCallback onHistoryUp;

  /// ↓ボタン押下時に呼び出されるコールバック
  final VoidCallback onHistoryDown;

  /// 外部からフォーカスを制御するためのFocusNode
  final FocusNode focusNode;

  /// 入力バーの有効/無効状態
  /// false の場合、全ての入力・ボタンが無効化される（切断時に使用）
  final bool enabled;

  const CommandInputBar({
    super.key,
    required this.onCommandSubmit,
    required this.onHistoryUp,
    required this.onHistoryDown,
    required this.focusNode,
    this.enabled = true,
  });

  @override
  State<CommandInputBar> createState() => _CommandInputBarState();
}

class _CommandInputBarState extends State<CommandInputBar> {
  /// テキスト入力フィールドのコントローラー
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// コマンドを送信する
  void _submitCommand() {
    if (!widget.enabled) return;
    final command = _controller.text;
    widget.onCommandSubmit(command);
    _controller.clear();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // 無効時のボタン色（グレーアウト）
    final buttonColor = widget.enabled ? Colors.white54 : Colors.grey[700];
    final sendColor = widget.enabled ? Colors.greenAccent : Colors.grey[700];

    return Container(
      color: Colors.grey[900],
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // ↑ボタン
              IconButton(
                onPressed: widget.enabled ? widget.onHistoryUp : null,
                icon: Icon(
                  Icons.arrow_upward,
                  color: buttonColor,
                  size: 20,
                ),
                tooltip: '前の履歴',
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                padding: EdgeInsets.zero,
              ),

              // ↓ボタン
              IconButton(
                onPressed: widget.enabled ? widget.onHistoryDown : null,
                icon: Icon(
                  Icons.arrow_downward,
                  color: buttonColor,
                  size: 20,
                ),
                tooltip: '次の履歴',
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                padding: EdgeInsets.zero,
              ),

              const SizedBox(width: 4),

              // コマンド入力フィールド
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  // 無効時は入力を受け付けない
                  enabled: widget.enabled,
                  style: TextStyle(
                    color: widget.enabled ? Colors.greenAccent : Colors.grey[600],
                    fontSize: 16,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    // 無効時は切断メッセージを表示
                    hintText: widget.enabled
                        ? '\$ コマンドを入力...'
                        : '切断中...',
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: widget.enabled ? Colors.grey[850] : Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Colors.greenAccent,
                        width: 1,
                      ),
                    ),
                    // 無効時のボーダー
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey[800]!,
                        width: 1,
                      ),
                    ),
                  ),
                  // onEditingComplete を上書きすることで、
                  // Enter押下時のデフォルト動作（フォーカスを外す）を抑制する。
                  // これによりキーボードが出しっぱなしになり、チラつかない。
                  // onSubmitted は使わない（フォーカスが外れる原因になる）。
                  onEditingComplete: _submitCommand,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                ),
              ),

              const SizedBox(width: 4),

              // 送信ボタン
              IconButton(
                onPressed: widget.enabled ? _submitCommand : null,
                icon: Icon(
                  Icons.send,
                  color: sendColor,
                  size: 20,
                ),
                tooltip: '実行',
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
