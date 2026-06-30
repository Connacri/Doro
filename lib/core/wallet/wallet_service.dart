import 'wallet_model.dart';
import '../dag/dag_engine.dart';
import '../dag/transaction_model.dart';
import '../security/signature_service.dart';

class WalletService {
  final Map<String, Wallet> _wallets = {};
  final DagEngine dag;
  final SignatureService signatureService;

  WalletService({
    required this.dag,
    required this.signatureService,
  });

  Wallet createWallet(String address, String publicKey) {
    final wallet = Wallet(
      address: address,
      publicKey: publicKey,
      balance: BigInt.zero,
    );

    _wallets[address] = wallet;
    return wallet;
  }

  Wallet? getWallet(String address) => _wallets[address];

  bool transfer({
    required String from,
    required String to,
    required BigInt amount,
    required String signature,
    required List<String> approvals,
  }) {
    final sender = _wallets[from];
    final receiver = _wallets[to];

    if (sender == null || receiver == null) return false;

    if (sender.balance < amount) return false;

    // debit
    sender.debit(amount);
    receiver.credit(amount);

    final tx = Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      from: from,
      to: to,
      amount: amount,
      approvals: approvals,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      signature: signature,
    );

    dag.add(tx);

    return true;
  }
}