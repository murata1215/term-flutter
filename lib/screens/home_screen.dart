import 'package:flutter/material.dart';

import '../models/ssh_connection_info.dart';
import '../services/connection_storage_service.dart';
import 'terminal_screen.dart';

/// ホーム画面（接続先一覧 + 新規接続）
///
/// 保存済みの接続先をリスト表示し、タップで即接続できる画面。
/// 「+」ボタンで新規接続フォームを表示し、新しいサーバーに接続する。
/// パスワード認証と秘密鍵認証の両方に対応する。
/// 接続成功時に接続先を自動保存し、次回以降はリストから選択するだけで接続可能。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 接続先ストレージサービス
  final ConnectionStorageService _storageService = ConnectionStorageService();

  /// 保存済み接続先リスト
  List<SshConnectionInfo> _savedConnections = [];

  /// 読み込み中フラグ
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  /// 保存済み接続先を読み込む
  Future<void> _loadConnections() async {
    final connections = await _storageService.loadConnections();
    if (mounted) {
      setState(() {
        _savedConnections = connections;
        _isLoading = false;
      });
    }
  }

  /// 保存済み接続先をタップして接続する
  void _connectToSaved(SshConnectionInfo info) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          connectionInfo: info,
          onConnectionSuccess: () async {
            await _storageService.saveConnection(info);
            _loadConnections();
          },
        ),
      ),
    );
  }

  /// 保存済み接続先を削除する
  Future<void> _deleteConnection(SshConnectionInfo info) async {
    await _storageService.deleteConnection(info);
    _loadConnections();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${info.name} を削除しました'),
          action: SnackBarAction(
            label: '取り消し',
            onPressed: () async {
              await _storageService.saveConnection(info);
              _loadConnections();
            },
          ),
        ),
      );
    }
  }

  /// 新規接続フォームをモーダルで表示する
  void _showNewConnectionForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewConnectionForm(
        onConnect: (info) {
          Navigator.of(context).pop();
          Navigator.of(this.context).push(
            MaterialPageRoute(
              builder: (context) => TerminalScreen(
                connectionInfo: info,
                onConnectionSuccess: () async {
                  await _storageService.saveConnection(info);
                  _loadConnections();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Terminal'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _showNewConnectionForm,
            icon: const Icon(Icons.add, color: Colors.greenAccent),
            tooltip: '新しい接続',
          ),
        ],
      ),
      backgroundColor: Colors.grey[900],
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : _savedConnections.isEmpty
              ? _buildEmptyState()
              : _buildConnectionList(),
    );
  }

  /// 接続先が保存されていない場合の空状態を構築する
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal, size: 64, color: Colors.greenAccent),
          const SizedBox(height: 16),
          const Text(
            'SSH Terminal',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '接続先がまだありません',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showNewConnectionForm,
            icon: const Icon(Icons.add),
            label: const Text(
              '新しい接続',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 保存済み接続先のリストを構築する
  Widget _buildConnectionList() {
    return ListView.builder(
      itemCount: _savedConnections.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final info = _savedConnections[index];
        return Dismissible(
          key: Key(info.uniqueKey),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Colors.red[700],
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[850],
                title: const Text('接続先を削除',
                    style: TextStyle(color: Colors.white)),
                content: Text(
                  '${info.name} を削除しますか？',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child:
                        const Text('削除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => _deleteConnection(info),
          child: ListTile(
            onTap: () => _connectToSaved(info),
            // 接続先アイコン（認証方式で変更）
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                // 秘密鍵認証の場合は鍵アイコン、パスワード認証の場合はサーバーアイコン
                info.isKeyAuth ? Icons.vpn_key : Icons.dns_outlined,
                color: Colors.greenAccent,
                size: 20,
              ),
            ),
            title: Text(
              info.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            // 接続先アドレスと認証方式を表示
            subtitle: Text(
              '${info.displayAddress}  ${info.authTypeLabel}',
              style: TextStyle(
                color: Colors.grey[400],
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: Colors.white38),
          ),
        );
      },
    );
  }
}

/// 新規接続フォーム（モーダルBottomSheet内）
///
/// ホスト/ポート/ユーザー名と、パスワードまたは秘密鍵を入力して接続する。
/// 認証方式はトグルスイッチで切り替え可能。
/// 接続成功時に自動保存されるため、保存ボタンは不要。
class _NewConnectionForm extends StatefulWidget {
  final void Function(SshConnectionInfo info) onConnect;

  const _NewConnectionForm({required this.onConnect});

  @override
  State<_NewConnectionForm> createState() => _NewConnectionFormState();
}

class _NewConnectionFormState extends State<_NewConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  /// パスワードの表示/非表示切り替え
  bool _obscurePassword = true;

  /// 認証方式（true: 秘密鍵, false: パスワード）
  bool _useKeyAuth = false;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  /// バリデーションしてコールバックを呼び出す
  void _connect() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.isNotEmpty
        ? _nameController.text
        : _hostController.text;

    final info = SshConnectionInfo(
      name: name,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      authType: _useKeyAuth ? 'key' : 'password',
      password: _useKeyAuth ? '' : _passwordController.text,
      privateKey: _useKeyAuth ? _privateKeyController.text : '',
      passphrase: _useKeyAuth ? _passphraseController.text : '',
    );

    widget.onConnect(info);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // キーボード表示時にシートが押し上がるように viewInsets を考慮
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ドラッグハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                '新しい接続',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '接続成功時に自動的に保存されます',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 20),

              // 表示名（任意）
              _buildField(
                controller: _nameController,
                label: '表示名（任意）',
                icon: Icons.label_outline,
                hint: '例: My Server',
              ),
              const SizedBox(height: 12),

              // ホスト（必須）
              _buildField(
                controller: _hostController,
                label: 'ホスト',
                icon: Icons.dns_outlined,
                hint: '例: 192.168.1.1 または example.com',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'ホスト名を入力してください' : null,
              ),
              const SizedBox(height: 12),

              // ポート
              _buildField(
                controller: _portController,
                label: 'ポート',
                icon: Icons.numbers,
                hint: '22',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'ポート番号を入力してください';
                  final port = int.tryParse(v);
                  if (port == null || port < 1 || port > 65535) {
                    return '1〜65535の範囲で入力してください';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ユーザー名（必須）
              _buildField(
                controller: _usernameController,
                label: 'ユーザー名',
                icon: Icons.person_outline,
                hint: '例: root',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'ユーザー名を入力してください' : null,
              ),
              const SizedBox(height: 16),

              // 認証方式の切り替えトグル
              _buildAuthTypeToggle(),
              const SizedBox(height: 12),

              // 認証方式に応じた入力フィールド
              if (_useKeyAuth) ...[
                // --- 秘密鍵認証 ---
                _buildPrivateKeyField(),
                const SizedBox(height: 12),
                _buildPassphraseField(),
              ] else ...[
                // --- パスワード認証 ---
                _buildPasswordField(),
              ],

              const SizedBox(height: 24),

              // 接続ボタン
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.login),
                  label: const Text(
                    '接続',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 認証方式の切り替え��グルを構築する
  ///
  /// SegmentedButton でパスワード/秘密鍵を切り替え
  Widget _buildAuthTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // パスワード認証ボタン
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _useKeyAuth = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_useKeyAuth ? Colors.greenAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: !_useKeyAuth ? Colors.black : Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'パスワード',
                      style: TextStyle(
                        color:
                            !_useKeyAuth ? Colors.black : Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 秘密鍵認証ボタン
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _useKeyAuth = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _useKeyAuth ? Colors.greenAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.vpn_key,
                      size: 16,
                      color: _useKeyAuth ? Colors.black : Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '秘密鍵',
                      style: TextStyle(
                        color:
                            _useKeyAuth ? Colors.black : Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// パスワード入力フィールドを構築する
  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'パスワード',
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText: 'パスワードを入力',
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[400]),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[400],
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'パスワードを入力してください' : null,
    );
  }

  /// 秘密鍵入力フィールドを構築する
  ///
  /// 複数行のテキストフィールドで、PEM形式の秘密鍵を貼り付ける。
  /// -----BEGIN OPENSSH PRIVATE KEY----- から
  /// -----END OPENSSH PRIVATE KEY----- までの全文を入力する。
  Widget _buildPrivateKeyField() {
    return TextFormField(
      controller: _privateKeyController,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      maxLines: 6,
      decoration: InputDecoration(
        labelText: '秘密鍵（PEM形式）',
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText:
            '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----',
        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: Icon(Icons.vpn_key, color: Colors.grey[400]),
        ),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return '秘密鍵を貼り付けてください';
        }
        // 基本的なPEM形式チェック（BEGIN/ENDが含まれているか）
        if (!v.contains('-----BEGIN') || !v.contains('-----END')) {
          return 'PEM形式の秘密鍵を入力してください';
        }
        return null;
      },
    );
  }

  /// パスフレーズ入力フィールドを構築する
  ///
  /// パスフレーズ付き秘密鍵の場合に使用する。
  /// 空欄の場合はパスフレーズなしとして扱う。
  Widget _buildPassphraseField() {
    return TextFormField(
      controller: _passphraseController,
      obscureText: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'パスフレーズ（任意）',
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText: 'パスフレーズがある場合のみ入力',
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(Icons.password, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
      // パスフレーズは任意のためバリデーションなし
    );
  }

  /// 共通のテキスト入力フィールドを構築する
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[850],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
      validator: validator,
    );
  }
}
