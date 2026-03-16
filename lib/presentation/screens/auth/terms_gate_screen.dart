import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../providers/terms_provider.dart';

/// Full-screen Terms & Conditions gate.
///
/// Shown once per [AppTerms.currentVersion]. Accept button is only enabled
/// after the user has scrolled to the bottom of the text.
/// Declining exits the app — the app cannot be used without acceptance.
class TermsGateScreen extends ConsumerStatefulWidget {
  const TermsGateScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  ConsumerState<TermsGateScreen> createState() => _TermsGateScreenState();
}

class _TermsGateScreenState extends ConsumerState<TermsGateScreen> {
  final _scrollController = ScrollController();
  bool _scrolledToEnd = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrolledToEnd) return;
    final pos = _scrollController.position;
    // Unlock the button within 40px of the bottom.
    if (pos.pixels >= pos.maxScrollExtent - 40) {
      setState(() => _scrolledToEnd = true);
    }
  }

  Future<void> _accept() async {
    setState(() => _loading = true);
    await ref.read(termsAcceptedProvider.notifier).accept();
    if (mounted) widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.xl,
                AppSpacing.base,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  Image.asset('assets/logo-white.png', height: 40),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Terms of Use & Privacy Policy',
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Version ${AppTerms.currentVersion} · Please read carefully before using Kash Cube.',
                    style: tt.bodySmall?.copyWith(color: cs.outline),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Scrollable body ──────────────────────────────────────────────
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.lg,
                  ),
                  child: const _TermsBody(),
                ),
              ),
            ),

            const Divider(height: 1),

            // ── Scroll hint ──────────────────────────────────────────────────
            if (!_scrolledToEnd)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward,
                        size: 14, color: cs.outline),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Scroll to read all terms',
                      style: tt.bodySmall?.copyWith(color: cs.outline),
                    ),
                  ],
                ),
              ),

            // ── Actions ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.sm,
                AppSpacing.base,
                AppSpacing.base,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed:
                        (_scrolledToEnd && !_loading) ? _accept : null,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('I Agree — Continue'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () {
                      // Cannot use app without agreeing; exit.
                      // On Android this minimises the app.
                      // Navigator cannot pop root.
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Decline & Exit'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// T&C Text Body  (V2.2 — mirrors docs/TERMS_OF_USE_V2_2_REORDERED.md)
// ─────────────────────────────────────────────────────────────────────────────

class _TermsBody extends StatelessWidget {
  const _TermsBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Core Legal Terms ────────────────────────────────────────────────
        _CategoryHeader('Core Legal Terms'),
        _Section(
          title: 'Acceptance of Terms',
          body:
              'By downloading, installing, accessing, or using Kash Cube (the App), you agree '
              'to be bound by these Terms of Use & Privacy Policy (Terms). If you do not agree, '
              'do not install or use the App. These Terms form a legally binding agreement '
              'between you (User) and the developer of Kash Cube (Developer, we, us).',
        ),
        _Section(
          title: 'Acknowledgment of Reading',
          body:
              'By accepting these Terms, you represent and warrant that you have read, '
              'understood, and agree to be bound by all provisions of these Terms. You '
              'acknowledge that you have had the opportunity to seek independent legal advice '
              'before accepting.',
        ),
        _Section(
          title: 'Electronic Records and Communications',
          body:
              'You consent to receive all communications, agreements, disclosures, and notices '
              'electronically, including via in-app notifications, email, or posting on official '
              'channels. Electronic records satisfy any legal requirement that such communications '
              'be in writing, in accordance with the Information Technology Act, 2000.',
        ),
        _Section(
          title: 'Eligibility',
          body:
              'You must be at least 18 years old and legally capable of entering into a binding '
              'agreement to use the App.',
        ),
        _Section(
          title: 'Nature of the App',
          body:
              'Kash Cube is a financial record-keeping tool that may assist with transaction '
              'logging, invoice generation, payment tracking, and GST-related calculations. '
              'The App is not a substitute for professional accounting, legal, or tax services.',
        ),
        _Section(
          title: 'No Financial, Legal, or Tax Advice',
          body:
              'Nothing in the App constitutes financial, accounting, legal, tax, or investment '
              'advice. Outputs are generated from user-entered data and may contain errors. '
              'You are solely responsible for reviewing and validating all information before '
              'relying on it.',
        ),
        _Section(
          title: 'GST Compliance Disclaimer',
          body:
              'The App may assist with GST-related workflows (including calculations, invoice '
              'preparation, summaries, and exports), but the Developer does not guarantee that '
              'any output is accurate, complete, current, or compliant with applicable law.\n\n'
              'GST laws, rates, portal requirements, and filing procedures may change at any '
              'time, including by authorities such as GSTN, CBIC, and other competent regulators.\n\n'
              'You are solely responsible for verifying GST values and documents, ensuring '
              'invoice and record compliance, and filing accurate returns within statutory '
              'timelines. To the maximum extent permitted by law, the Developer is not liable '
              'for tax shortfall, interest, penalty, audit outcome, notice, prosecution, or '
              'other regulatory consequences arising from use of the App or reliance on '
              'App-generated outputs.',
        ),

        // ── Data & Privacy ──────────────────────────────────────────────────
        _CategoryHeader('Data & Privacy'),
        _Section(
          title: 'Local Data Storage',
          body:
              'Kash Cube is designed as a privacy-first, local-first application. Financial '
              'records and SMS-derived transaction data are processed and stored on your device. '
              'At present, the Developer does not transmit your financial records to its servers.',
        ),
        _Section(
          title: 'User Data Responsibility',
          body:
              'You are solely responsible for data accuracy, backups, and device security. '
              'The Developer cannot recover data lost due to device failure, theft, malware, '
              'factory reset, accidental deletion, or uninstall.',
        ),
        _Section(
          title: 'SMS Permission and Processing',
          body:
              'On supported Android devices, the App may request SMS permission only to detect '
              'financial transaction notifications. SMS data is processed on-device for this '
              'purpose. You may revoke SMS permission at any time in system settings.',
        ),
        _Section(
          title: 'Anonymous Analytics and Crash Reporting',
          body:
              'To improve reliability, the App may process limited analytics and crash telemetry '
              'as described in-app and in settings. The Developer does not intentionally collect '
              'transaction content or financial record details as analytics payload.\n\n'
              'Where analytics is optional, consent controls are provided in-app.',
        ),
        _Section(
          title: 'GDPR-Compatible Privacy Notice',
          body:
              'For locally stored financial records, you remain in direct control of your data '
              'on your device. Where non-financial telemetry is processed, it is handled in '
              'accordance with applicable privacy law and these Terms.',
        ),
        _Section(
          title: 'Security Disclaimer',
          body:
              'No software can be guaranteed fully secure. The Developer is not responsible for '
              'compromise caused by rooted or jailbroken devices, third-party malware, insecure '
              'device configuration, or unauthorized physical or device access.',
        ),

        // ── Services & Platform ─────────────────────────────────────────────
        _CategoryHeader('Services & Platform'),
        _Section(
          title: 'Third-Party Services',
          body:
              'Some features may interact with third-party services (for example, payment links, '
              'government portals, file sharing destinations, or platform services). Those '
              'services are independent and governed by their own terms and privacy policies.',
        ),
        _Section(
          title: 'Multi-Platform Distribution',
          body:
              'These Terms apply regardless of distribution channel, including app stores, '
              'direct downloads, and other permitted channels.',
        ),
        _Section(
          title: 'Shared Devices',
          body:
              'If the App is used on a shared device, you are responsible for access control '
              'and prevention of unauthorized viewing of sensitive information.',
        ),
        _Section(
          title: 'Web and Future Online Services',
          body:
              'If future versions introduce cloud storage, sync, or remote processing, '
              'applicable legal terms and privacy terms will be updated before such features '
              'are enabled for users.',
        ),

        // ── Technology & Features ───────────────────────────────────────────
        _CategoryHeader('Technology & Features'),
        _Section(
          title: 'AI and Automation Features',
          body:
              'The App may include automation, rule-based logic, or AI-assisted features '
              '(for example, categorization, summaries, or suggestions).\n\n'
              'All such outputs are informational only, may be incomplete or inaccurate, and '
              'are not professional advice (including financial, tax, legal, or accounting advice).\n\n'
              'You are solely responsible for independently reviewing and verifying all outputs '
              'before relying on them for filings, compliance, contractual, accounting, or '
              'business decisions.\n\n'
              'The Developer does not guarantee the correctness, completeness, or suitability '
              'of automated/AI outputs and is not liable for decisions made in reliance on '
              'those outputs, to the maximum extent permitted by law.',
        ),
        _Section(
          title: 'Updates and Feature Changes',
          body: 'The Developer may add, modify, suspend, or remove features at any time.',
        ),
        _Section(
          title: 'Experimental Features',
          body:
              'Beta or experimental features may be incomplete, may change without notice, '
              'and may be discontinued at any time. Use of experimental features is voluntary '
              'and at your own risk.',
        ),
        _Section(
          title: 'Technical Accuracy and Calculation Disclaimer',
          body:
              'The App performs calculations including but not limited to GST, totals, interest, '
              'and summaries using standard algorithms. However:\n'
              '  • Rounding, floating-point approximations, or calculation differences may occur.\n'
              '  • Date, time, or timezone calculations may be affected by device settings or '
              'regional configurations.\n'
              '  • Currency formatting follows device locale settings; you must verify actual '
              'numeric values independently.\n'
              '  • Calculation results are estimates only and are not guaranteed to match '
              'official portal calculations.',
        ),
        _Section(
          title: 'Device Compatibility',
          body:
              'The App is designed for specific platforms and device configurations. The '
              'Developer does not guarantee that all features will function on all devices, '
              'operating system versions, or hardware configurations. Compatibility issues '
              'may arise without notice.',
        ),
        _Section(
          title: 'Backup and Data Migration',
          body:
              'Backup creation and restoration are provided on a best-effort basis. The '
              'Developer does not guarantee successful backup, restore, or data migration '
              'between App versions or devices. You are solely responsible for verifying '
              'backup integrity and maintaining redundant copies of critical data.',
        ),
        _Section(
          title: 'Multi-Device and Sync Conflicts',
          body:
              'If you use the App on multiple devices or enable future sync features, data '
              'conflicts may occur. You are solely responsible for reconciling conflicting '
              'records. The Developer is not liable for data loss or corruption arising from '
              'multi-device usage or sync conflicts.',
        ),

        // ── Legal Rights ────────────────────────────────────────────────────
        _CategoryHeader('Legal Rights'),
        _Section(
          title: 'Intellectual Property',
          body:
              'All rights, title, and interest in and to the App (including software, design, '
              'trademarks, and content) remain with the Developer and licensors. You receive a '
              'limited, non-exclusive, non-transferable, revocable license to use the App in '
              'accordance with these Terms.\n\n'
              'You may not copy, modify, distribute, sublicense, reverse engineer, decompile, '
              'or disassemble the App except where such restriction is prohibited by law.',
        ),
        _Section(
          title: 'Prohibited Uses',
          body:
              'You must not use the App for unlawful activity, fraud, tax evasion, money '
              'laundering, rights violations, or unauthorized processing of third-party '
              'personal data.',
        ),
        _Section(
          title: 'User Content and Record Liability',
          body:
              'All records, invoices, entries, summaries, and exports created in the App are '
              'user-generated content controlled by you. The Developer does not verify or '
              'certify user content. You are solely responsible for the accuracy, legality, '
              'authorization, and use of your content.',
        ),
        _Section(
          title: 'Evidence and Legal Use Disclaimer',
          body:
              'App-generated documents and exports (including PDF/CSV reports, invoices, and '
              'summaries) are informational tools and are not certified legal/accounting '
              'evidence by default. The Developer makes no representation that such outputs '
              'will be accepted by courts, regulators, banks, or tax authorities.',
        ),

        // ── Legal Protections ───────────────────────────────────────────────
        _CategoryHeader('Legal Protections'),
        _Section(
          title: 'Disclaimer of Warranties',
          body:
              'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF ANY KIND, '
              'WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING MERCHANTABILITY, FITNESS FOR '
              'A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.',
        ),
        _Section(
          title: 'Limitation of Liability',
          body:
              'To the maximum extent permitted by law, the Developer is not liable for indirect, '
              'incidental, special, consequential, exemplary, or punitive damages, or for loss '
              'of profits, revenue, data, goodwill, business opportunity, or regulatory penalties.\n\n'
              'Aggregate liability for all claims arising out of or relating to the App will not '
              'exceed the greater of: (a) amount paid by you for the App in the 12 months '
              'preceding the claim, or (b) INR 1 if no amount was paid.\n\n'
              'Nothing in these Terms limits liability that cannot be excluded under applicable law.',
        ),
        _Section(
          title: 'Indemnification',
          body:
              'You agree to defend, indemnify, and hold harmless the Developer from third-party '
              'claims, liabilities, losses, and expenses (including reasonable legal fees) '
              'arising from your misuse of the App, your content, or your violation of law '
              'or these Terms.',
        ),
        _Section(
          title: 'Force Majeure',
          body:
              'The Developer is not liable for delay or failure caused by events beyond '
              'reasonable control, including natural disasters, internet outages, infrastructure '
              'failures, cyber incidents, labor disputes, and government actions.',
        ),

        // ── Dispute Resolution ──────────────────────────────────────────────
        _CategoryHeader('Dispute Resolution'),
        _Section(
          title: 'Arbitration',
          body:
              'Any dispute, controversy, or claim arising out of or relating to these Terms or '
              'the App shall be referred to and finally resolved by binding arbitration in '
              'accordance with the Arbitration and Conciliation Act, 1996 (as amended). The '
              'arbitration shall be conducted by a sole arbitrator mutually agreed upon, or '
              'failing agreement within 30 days, appointed in accordance with the Act. The seat '
              'of arbitration shall be Puducherry, India. The language of arbitration shall be '
              'English. The arbitral award shall be final and binding.',
        ),
        _Section(
          title: 'Class Action Waiver',
          body:
              'You agree that any dispute resolution proceedings will be conducted only on an '
              'individual basis and not as a class, consolidated, or representative action. '
              'You waive any right to participate in any class action, collective action, or '
              'representative proceeding against the Developer.',
        ),
        _Section(
          title: 'Time Limit on Claims',
          body:
              'Any claim or cause of action arising out of or related to these Terms or the App '
              'must be filed within one (1) year after such claim or cause of action arose, '
              'regardless of any statute or law to the contrary. Failure to file within this '
              'period shall result in permanent waiver of the claim.',
        ),
        _Section(
          title: 'Good-Faith Resolution',
          body:
              'Before initiating arbitration or any legal proceeding, you agree to first contact '
              'the Developer and attempt good-faith resolution for a period of at least 30 days.',
        ),
        _Section(
          title: 'Confidentiality of Disputes',
          body:
              'All arbitration proceedings, including filings, evidence, and awards, shall '
              'remain confidential and shall not be disclosed to any third party except as '
              'required by law or to enforce the award.',
        ),

        // ── Account & Access ────────────────────────────────────────────────
        _CategoryHeader('Account & Access'),
        _Section(
          title: 'Termination',
          body:
              'The Developer may suspend or terminate access where permitted by law, including '
              'for violation of these Terms, misuse, abuse, security risk, or legal compliance '
              'requirements.\n\n'
              'You may stop using the App at any time by uninstalling it.',
        ),

        // ── Structural Legal Clauses ────────────────────────────────────────
        _CategoryHeader('Structural Legal Clauses'),
        _Section(
          title: 'Severability',
          body:
              'If any provision is held invalid or unenforceable, the remaining provisions '
              'remain in full force, and the invalid provision will be interpreted to best '
              'reflect its original intent to the extent permitted by law.',
        ),
        _Section(
          title: 'Survival of Terms',
          body:
              'Provisions that by nature should survive termination survive, including '
              'intellectual property, disclaimers, limitation of liability, indemnification, '
              'governing law, dispute resolution, and user-content related liability disclaimers.',
        ),
        _Section(
          title: 'Entire Agreement',
          body:
              'These Terms constitute the entire agreement between you and the Developer '
              'regarding the App and supersede prior understandings relating to the same '
              'subject matter.',
        ),
        _Section(
          title: 'No Waiver',
          body:
              'The failure of the Developer to enforce any right or provision of these Terms '
              'shall not constitute a waiver of such right or provision. Any waiver must be '
              'in writing and signed by the Developer.',
        ),
        _Section(
          title: 'Assignment',
          body:
              'The Developer may assign or transfer these Terms, in whole or in part, without '
              'restriction. You may not assign or transfer any rights or obligations under '
              'these Terms without the prior written consent of the Developer.',
        ),
        _Section(
          title: 'No Third-Party Beneficiaries',
          body:
              'These Terms do not confer any rights or remedies upon any person or entity '
              'other than you and the Developer.',
        ),
        _Section(
          title: 'Headings',
          body:
              'Section headings are for convenience only and have no legal or contractual effect.',
        ),
        _Section(
          title: 'No Agency or Partnership',
          body:
              'Nothing in these Terms creates any agency, partnership, joint venture, or '
              'employment relationship between you and the Developer.',
        ),
        _Section(
          title: 'Cumulative Remedies',
          body:
              'All remedies available to the Developer under these Terms or at law are '
              'cumulative and not exclusive of any other remedies.',
        ),
        _Section(
          title: 'Language',
          body:
              'These Terms are drafted in English. If translated into any other language, '
              'the English version shall control in the event of any conflict or ambiguity.',
        ),

        // ── Platform Compliance ─────────────────────────────────────────────
        _CategoryHeader('Platform Compliance'),
        _Section(
          title: 'Platform Policy Compliance (App Stores)',
          body:
              'The App is intended to comply with applicable platform policies (including Google '
              'Play and Apple App Store policies). Permissions are used only for described '
              'functionality. SMS content is not collected for advertising, not sold, and not '
              'intentionally transmitted externally for profiling.',
        ),
        _Section(
          title: 'Open Source / Third-Party Components',
          body:
              'The App may include platform SDKs, open-source software, and third-party '
              'components subject to their own licenses. Those terms apply to the respective '
              'components.',
        ),

        // ── Privacy Controls ────────────────────────────────────────────────
        _CategoryHeader('Privacy Controls'),
        _Section(
          title: 'Data Deletion',
          body:
              'Because primary records are stored on-device, you may delete data by deleting '
              'records in-app, clearing app storage, or uninstalling the App. Deleted data '
              'may not be recoverable by the Developer.',
        ),

        // ── Legal Framework ─────────────────────────────────────────────────
        _CategoryHeader('Legal Framework'),
        _Section(
          title: 'Governing Law and Jurisdiction',
          body:
              'These Terms are governed by the laws of India. Subject to applicable law, courts '
              'in Puducherry, Puducherry, India have exclusive jurisdiction over disputes arising '
              'from or relating to these Terms or the App.',
        ),

        // ── Regulatory Compliance (India) ───────────────────────────────────
        _CategoryHeader('Regulatory Compliance (India)'),
        _Section(
          title: 'Consumer Protection Act 2019',
          body:
              'Nothing in these Terms is intended to exclude or limit any liability that cannot '
              'be excluded or limited under the Consumer Protection Act, 2019, or any other '
              'applicable consumer protection law.',
        ),
        _Section(
          title: 'Information Technology Act 2000',
          body:
              'You consent to electronic records and communications in accordance with the '
              'Information Technology Act, 2000. The Developer is an intermediary under the '
              'IT Act and complies with applicable intermediary guidelines.',
        ),
        _Section(
          title: 'Digital Personal Data Protection Act 2023',
          body:
              'For any personal data processed by the Developer (such as analytics telemetry), '
              'processing is conducted in accordance with the Digital Personal Data Protection '
              'Act, 2023, and applicable rules thereunder.',
        ),
        _Section(
          title: 'RBI and Payment Regulations',
          body:
              'The App does not process payments, hold funds, or act as a payment intermediary. '
              'No authorization from the Reserve Bank of India (RBI) or any payment regulator '
              'is claimed or required. The App is a record-keeping tool only.',
        ),
        _Section(
          title: 'Anti-Money Laundering',
          body:
              'You warrant that you will not use the App to facilitate money laundering, terror '
              'financing, or any activity prohibited under the Prevention of Money Laundering '
              'Act, 2002, or related laws.',
        ),
        _Section(
          title: 'Export Controls',
          body:
              'You warrant that your use of the App complies with applicable export control and '
              'sanctions laws, including those of India and any jurisdiction from which you '
              'access the App.',
        ),

        // ── Communication ───────────────────────────────────────────────────
        _CategoryHeader('Communication'),
        _Section(
          title: 'Contact Information',
          body:
              'For support or legal questions regarding these Terms, contact the official '
              'support channel listed on the App store listing or official app contact page.\n\n'
              'Version: ${AppTerms.currentVersion} · Effective Date: 16 March 2026',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Header
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Divider(color: cs.outlineVariant, height: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Widget
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: tt.bodyMedium?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
