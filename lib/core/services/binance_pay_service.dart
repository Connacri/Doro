// lib/core/services/binance_pay_service.dart
//
// Client Flutter du flow de paiement Binance Pay (voir
// supabase/functions/create-wager-payment et confirm-wager-payment).
//
// Ne parle JAMAIS directement à l'API Binance : tout passe par les
// edge functions, qui seules détiennent les clés API Binance
// (BINANCE_API_KEY / BINANCE_API_SECRET côté serveur, jamais dans l'app).

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class WagerPaymentInfo {
  final String wagerId;
  final String depositAddress;
  final String amountExact;
  final String currency;
  final String network;

  WagerPaymentInfo({
    required this.wagerId,
    required this.depositAddress,
    required this.amountExact,
    required this.currency,
    required this.network,
  });

  factory WagerPaymentInfo.fromJson(Map<String, dynamic> json) => WagerPaymentInfo(
        wagerId: json['wagerId'] as String,
        depositAddress: json['depositAddress'] as String,
        amountExact: json['amountExact'] as String,
        currency: json['currency'] as String,
        network: json['network'] as String,
      );
}

enum ConfirmOutcome { confirmed, pending, rejected, error }

class ConfirmResult {
  final ConfirmOutcome outcome;
  final String message;

  ConfirmResult(this.outcome, this.message);
}

class BinancePayService {
  final SupabaseClient supabase;

  BinancePayService(this.supabase);

  /// Étapes 1-4 : crée la mise et récupère l'adresse + le montant exact
  /// à afficher (QR code + copier-coller).
  Future<WagerPaymentInfo> createWagerPayment({
    String? betId,
    String? predictionEventId,
    required String chosenOption,
    required double amount,
  }) async {
    final res = await supabase.functions.invoke(
      'create-wager-payment',
      body: {
        if (betId != null) 'betId': betId,
        if (predictionEventId != null) 'predictionEventId': predictionEventId,
        'chosenOption': chosenOption,
        'amount': amount,
      },
    );
    if (res.status != 200) {
      throw Exception('Échec de création de la mise : ${res.data}');
    }
    return WagerPaymentInfo.fromJson(res.data as Map<String, dynamic>);
  }

  /// Étape 7-12 : soumet le TxID collé par l'user. Peut renvoyer "pending"
  /// (propagation réseau) — dans ce cas [pollUntilResolved] doit être
  /// utilisé côté UI pour retenter automatiquement.
  Future<ConfirmResult> confirmPayment({required String wagerId, required String txId}) async {
    try {
      final res = await supabase.functions.invoke(
        'confirm-wager-payment',
        body: {'wagerId': wagerId, 'txId': txId},
      );
      final data = res.data as Map<String, dynamic>? ?? {};
      switch (res.status) {
        case 200:
          return ConfirmResult(ConfirmOutcome.confirmed, "✅ Mise confirmée.");
        case 202:
          return ConfirmResult(
            ConfirmOutcome.pending,
            data['message'] as String? ?? "En attente de confirmation réseau…",
          );
        case 409:
          return ConfirmResult(
            ConfirmOutcome.rejected,
            data['message'] as String? ?? "Paiement rejeté : montant ou transaction invalide.",
          );
        default:
          return ConfirmResult(ConfirmOutcome.error, data['error']?.toString() ?? "Erreur inconnue.");
      }
    } catch (e) {
      return ConfirmResult(ConfirmOutcome.error, "Erreur réseau : $e");
    }
  }

  /// Retry automatique (étape 12b) : toutes les 5s, pendant max 2 minutes,
  /// tant que le backend répond "pending". S'arrête dès que confirmed ou
  /// rejected. À utiliser en fallback si le Realtime n'a pas encore
  /// notifié (ex: connexion faible).
  Stream<ConfirmResult> pollUntilResolved({
    required String wagerId,
    required String txId,
    Duration interval = const Duration(seconds: 5),
    Duration timeout = const Duration(minutes: 2),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await confirmPayment(wagerId: wagerId, txId: txId);
      yield result;
      if (result.outcome != ConfirmOutcome.pending) return;
      await Future.delayed(interval);
    }
    yield ConfirmResult(ConfirmOutcome.error, "Délai dépassé, réessaie plus tard ou contacte le support.");
  }

  /// Écoute Realtime sur la ligne `wagers` : notifie instantanément dès
  /// que l'edge function passe le statut à confirmed/rejected, sans
  /// attendre le prochain tick de polling.
  StreamSubscription<List<Map<String, dynamic>>> watchWagerStatus({
    required String wagerId,
    required void Function(String status, String? rejectReason) onChange,
  }) {
    return supabase
        .from('wagers')
        .stream(primaryKey: ['id'])
        .eq('id', wagerId)
        .listen((rows) {
      if (rows.isEmpty) return;
      final row = rows.first;
      onChange(row['status'] as String, row['reject_reason'] as String?);
    });
  }
}
