import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/booking.dart';
import '../../data/models/credit.dart';
import '../../data/models/invoice.dart';
import '../../data/models/loan.dart';
import '../../data/models/party_financial_summary.dart';
import '../../data/models/party_reminder.dart';
import '../../data/models/transaction.dart';
import 'booking_provider.dart';
import 'context_provider.dart';
import 'credit_provider.dart';
import 'invoice_provider.dart';
import 'loan_provider.dart';
import 'party_provider.dart';
import 'party_reminder_provider.dart';
import 'transaction_provider.dart';

/// Aggregated financial snapshot for a single party.
/// Parameterised by party ID.
final partyFinancialSummaryProvider =
    FutureProvider.family<PartyFinancialSummary, int>((ref, partyId) async {
      // Re-evaluate whenever the active context switches.
      ref.watch(activeContextProvider);
      // Step 1 – fetch party to get name (needed for reminder lookup which is name-based)
      final party = await ref.read(partyRepositoryProvider).getById(partyId);
      if (party == null) throw Exception('Party $partyId not found');

      // Step 2 – parallel DB queries
      final results = await Future.wait([
        ref
            .read(invoiceRepositoryProvider)
            .getByPartyId(partyId), // 0: List<Invoice>
        ref
            .read(creditRepositoryProvider)
            .getByCustomerId(partyId), // 1: List<Credit>
        ref
            .read(loanRepositoryProvider)
            .getByLenderId(partyId), // 2: List<Loan>
        ref
            .read(transactionRepositoryProvider)
            .countByPartyId(partyId), // 3: int
        ref
            .read(bookingRepositoryProvider)
            .getByPartyId(partyId), // 4: List<Booking>
        ref
            .read(partyReminderRepositoryProvider)
            .getByParty(party.name), // 5: List<PartyReminder>
        ref
            .read(transactionRepositoryProvider)
            .getByPartyId(partyId), // 6: List<Transaction>
      ]);

      final invoices = results[0] as List<Invoice>;
      final credits = results[1] as List<Credit>;
      final loans = results[2] as List<Loan>;
      final txnCount = results[3] as int;
      final bookings = results[4] as List<Booking>;
      final reminders = results[5] as List<PartyReminder>;
      final transactions = results[6] as List<Transaction>;

      final lastTxnDate = transactions.isNotEmpty
          ? transactions.first.date
          : null;

      return PartyFinancialSummary.compute(
        partyId: partyId,
        partyName: party.name,
        invoices: invoices,
        credits: credits,
        loans: loans,
        bookings: bookings,
        transactionCount: txnCount,
        reminders: reminders,
        lastTransactionDate: lastTxnDate,
      );
    });
