import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../wallet/address_generator.dart';

/// Identité cryptographique persistante du node local — distincte des
/// wallets (le node garde la même identité même s'il crée ou importe
/// plusieurs wallets ensuite).
///
/// AVANT ce fix : `nodeId` était une chaîne arbitraire persistée en clair
/// (`"doro-<horodatage>"`), sans aucune clé associée. Le champ `approver`
/// d'un message `tx_approve` n'était vérifié contre RIEN : n'importe quel
/// pair connecté pouvait diffuser un vote de confirmation en prétendant
/// être n'importe quel nodeId — y compris un nodeId jamais rencontré. Un
/// seul pair malveillant pouvait donc fabriquer un nombre illimité de
/// votes gratuits, sans même avoir besoin de plusieurs instances/appareils.
///
/// APRÈS ce fix : `nodeId` est dérivé (via `AddressGenerator`, le même
/// mécanisme que pour une adresse de wallet) de la clé publique d'une
/// vraie paire Ed25519, générée une seule fois puis stockée dans le
/// Keystore/Keychain sécurisé du système. Chaque vote de confirmation
/// est désormais signé par cette clé et vérifié par le récepteur avant
/// d'être compté — voir `P2PNode._handleIncomingApprove`.
///
/// Ce que ça corrige : l'usurpation gratuite d'identité (un pair ne peut
/// plus voter au nom d'un nodeId dont il ne possède pas la clé privée).
/// Ce que ça NE corrige PAS à soi seul : rien n'empêche un attaquant de
/// générer plusieurs identités RÉELLES et distinctes (autant de paires de
/// clés qu'il veut — c'est gratuit en quelques millisecondes, comme pour
/// n'importe quelle adresse Bitcoin/Ethereum). Sans coût économique par
/// identité (stake, ou preuve de travail), le Sybil reste possible en
/// théorie ; ce fix élève le coût de "gratuit et instantané" à "il faut
/// une vraie clé + une vraie session P2P par identité", ce qui suffit à
/// bloquer l'attaque triviale décrite, mais n'est pas une garantie
/// d'impossibilité absolue — voir la note dans P2PNode à ce sujet.
class NodeIdentity {
  static const _seedKey = 'doro_node_identity_seed';
  static const _storage = FlutterSecureStorage();

  static Future<NodeIdentityKeyPair> getOrCreate() async {
    final existingHex = await _storage.read(key: _seedKey);
    final SimpleKeyPair keyPair;

    if (existingHex != null && existingHex.isNotEmpty) {
      final seed = _hexToBytes(existingHex);
      keyPair = await Ed25519().newKeyPairFromSeed(seed);
    } else {
      keyPair = await Ed25519().newKeyPair() as SimpleKeyPair;
      final seed = await keyPair.extractPrivateKeyBytes();
      await _storage.write(key: _seedKey, value: _bytesToHex(seed));
    }

    final publicKey = await keyPair.extractPublicKey();
    final pubKeyHex = _bytesToHex(publicKey.bytes);
    final nodeId = AddressGenerator.generate(pubKeyHex);

    return NodeIdentityKeyPair(
      nodeId: nodeId,
      publicKeyHex: pubKeyHex,
      keyPair: keyPair,
    );
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}

/// Identité complète du node : le `nodeId` public (partageable, dérivé de
/// la clé publique) et la paire de clés qui permet de signer les votes de
/// confirmation émis par ce node.
class NodeIdentityKeyPair {
  final String nodeId;
  final String publicKeyHex;
  final SimpleKeyPair keyPair;

  NodeIdentityKeyPair({
    required this.nodeId,
    required this.publicKeyHex,
    required this.keyPair,
  });
}