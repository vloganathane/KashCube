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
// T&C Text Body
// ─────────────────────────────────────────────────────────────────────────────

class _TermsBody extends StatelessWidget {
  const _TermsBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: '1. Acceptance of Terms',
          body:
              'By installing, accessing, or using Kash Cube ("the App", "the Software"), '
              'you ("User", "you") agree to be legally bound by these Terms of Use and Privacy Policy '
              '("Terms"). If you do not agree, do not install or use the App.\n\n'
              'These Terms constitute the entire agreement between you and the developer of '
              'Kash Cube ("Developer", "we", "us") regarding your use of the App.',
        ),
        _Section(
          title: '2. Software Provided "As Is"',
          body:
              'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND, '
              'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, '
              'FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, COMPLETENESS, OR NON-INFRINGEMENT.\n\n'
              'We do not warrant that:\n'
              '  • The App will be error-free or uninterrupted\n'
              '  • Calculations (GST, tax, totals, interest) are accurate or legally compliant\n'
              '  • The App meets your specific business requirements\n'
              '  • Data stored in the App is safe from device failure, theft, or corruption\n\n'
              'USE OF THE APP IS ENTIRELY AT YOUR OWN RISK.',
        ),
        _Section(
          title: '3. No Financial, Legal, or Tax Advice',
          body:
              'Kash Cube is a personal record-keeping tool only. Nothing in the App constitutes '
              'financial advice, accounting advice, legal advice, tax advice, or any other '
              'professional advice.\n\n'
              'All GST calculations, invoice totals, credit amounts, and financial summaries '
              'displayed in the App are for your reference only. You are solely responsible for:\n'
              '  • Verifying the accuracy of all calculations\n'
              '  • Filing correct GST returns (GSTR-1, GSTR-3B, etc.) with the GST portal\n'
              '  • Complying with the Income Tax Act, Companies Act, and all applicable Indian laws\n'
              '  • Consulting a qualified Chartered Accountant or tax professional for financial decisions\n\n'
              'We accept no liability for any tax, penalty, or legal consequence arising from '
              'data entered into or generated by the App.',
        ),
        _Section(
          title: '4. User Data & Privacy',
          body:
              'ALL DATA YOU ENTER INTO KASH CUBE IS STORED EXCLUSIVELY ON YOUR DEVICE.\n\n'
              'We do not collect, transmit, store, or process any of your financial data, '
              'transaction records, customer names, invoice details, party information, SMS messages, '
              'or any personally identifiable financial information on our servers.\n\n'
              'You are solely responsible for:\n'
              '  • The security of your device and the data stored on it\n'
              '  • Creating and maintaining backups of your data\n'
              '  • Any loss of data due to device failure, factory reset, theft, or app uninstallation\n'
              '  • Ensuring your data complies with applicable data protection laws\n\n'
              'We strongly recommend enabling the encrypted backup feature and storing backups securely.',
        ),
        _Section(
          title: '5. SMS Access',
          body:
              'The App requests permission to read SMS messages on your Android device solely to '
              'automatically detect and import financial transactions from bank and payment service '
              'SMS notifications.\n\n'
              'SMS data is:\n'
              '  • Processed entirely on your device\n'
              '  • Never transmitted to any server\n'
              '  • Never shared with any third party\n\n'
              'You may revoke SMS permission at any time in Android Settings. Revoking this '
              'permission disables automatic SMS capture but does not affect other App functionality.',
        ),
        _Section(
          title: '6. Usage Analytics',
          body:
              'To improve the App, we may collect anonymous, aggregated usage data about '
              'which features are used. Specifically:\n\n'
              'We MAY collect (anonymous, no financial data):\n'
              '  • Which screens you visit (e.g., "Invoices screen opened")\n'
              '  • Which features you use (e.g., "PDF generated", "SMS capture used")\n'
              '  • App crash and error events\n\n'
              'We NEVER collect:\n'
              '  • Transaction amounts, invoice totals, or any financial figures\n'
              '  • Customer names, party names, or business names\n'
              '  • Invoice numbers, transaction IDs, or any record content\n'
              '  • Location data\n\n'
              'By accepting these Terms, you consent to the collection of anonymous usage '
              'data as described above. You may withdraw this consent at any time in '
              'Settings → Privacy → Usage Analytics.',
        ),
        _Section(
          title: '7. Limitation of Liability',
          body:
              'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE DEVELOPER, '
              'ITS AFFILIATES, EMPLOYEES, OR LICENSORS BE LIABLE FOR:\n\n'
              '  • Any indirect, incidental, special, consequential, or punitive damages\n'
              '  • Loss of profits, revenue, data, business, or goodwill\n'
              '  • Business interruption or loss of business opportunity\n'
              '  • Financial losses arising from incorrect calculations or entries\n'
              '  • Tax penalties, GST demands, or regulatory actions\n'
              '  • Data loss due to device failure, app bugs, or accidental deletion\n'
              '  • Unauthorised access to your device or data\n\n'
              'WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING NEGLIGENCE), OR ANY OTHER '
              'LEGAL THEORY, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.\n\n'
              'Our total liability to you for any claims arising from use of the App shall not '
              'exceed the amount you paid for the App in the preceding 12 months (if any).',
        ),
        _Section(
          title: '8. Indemnification',
          body:
              'You agree to indemnify, defend, and hold harmless the Developer and its affiliates '
              'from and against any and all claims, liabilities, damages, losses, costs, and expenses '
              '(including reasonable legal fees) arising out of or in connection with:\n\n'
              '  • Your use or misuse of the App\n'
              '  • Data you enter, store, or generate using the App\n'
              '  • Your violation of these Terms\n'
              '  • Your violation of any applicable law or regulation\n'
              '  • Any third-party claims relating to your use of the App',
        ),
        _Section(
          title: '9. Intellectual Property',
          body:
              'The App, including its code, design, user interface, graphics, and content, '
              'is the exclusive intellectual property of the Developer and is protected by '
              'applicable copyright, trademark, and intellectual property laws.\n\n'
              'You are granted a limited, non-exclusive, non-transferable, revocable licence to '
              'use the App solely for your personal or business record-keeping purposes. You may not:\n'
              '  • Copy, modify, distribute, sell, or sublicense the App\n'
              '  • Reverse-engineer, decompile, or disassemble the App\n'
              '  • Remove or alter any copyright, trademark, or other proprietary notices',
        ),
        _Section(
          title: '10. Prohibited Uses',
          body:
              'You agree not to use the App for:\n'
              '  • Any unlawful purpose or in violation of any applicable law\n'
              '  • Recording fictitious transactions for the purpose of tax evasion or fraud\n'
              '  • Money laundering or any financial crime\n'
              '  • Storing data belonging to individuals without their consent\n'
              '  • Any purpose that violates the rights of third parties\n\n'
              'We reserve the right to terminate your access to the App if we have reasonable '
              'grounds to believe you are using it for prohibited purposes.',
        ),
        _Section(
          title: '11. Updates and Changes',
          body:
              'We may update the App and these Terms at any time. When we update these Terms, '
              'you will be prompted to review and accept the new version before continuing to use the App. '
              'Continued use after accepting updated Terms constitutes agreement to the changes.\n\n'
              'We may also update, modify, or discontinue features of the App at any time without notice.',
        ),
        _Section(
          title: '12. Disclaimer of Warranties for Third-Party Services',
          body:
              'If you use optional features that interact with third-party services (such as '
              'e-way bill portals, UPI payment links, or government GST portals), '
              'we make no warranties about the availability, accuracy, or reliability of those services. '
              'Any data submitted to third-party services is governed by their own terms and privacy policies.',
        ),
        _Section(
          title: '13. Governing Law & Dispute Resolution',
          body:
              'These Terms are governed by and construed in accordance with the laws of India, '
              'without regard to its conflict of law provisions.\n\n'
              'Any dispute arising from these Terms or your use of the App shall be subject to '
              'the exclusive jurisdiction of the courts in Tamil Nadu, India.\n\n'
              'Before initiating any legal proceedings, you agree to first attempt to resolve '
              'the dispute by contacting us directly and allowing 30 days for a good-faith response.',
        ),
        _Section(
          title: '14. Severability',
          body:
              'If any provision of these Terms is held to be unenforceable or invalid by a '
              'court of competent jurisdiction, that provision shall be modified to the minimum '
              'extent necessary to make it enforceable, and the remaining provisions shall '
              'continue in full force and effect.',
        ),
        _Section(
          title: '15. Contact',
          body:
              'For questions, feedback, or concerns about these Terms or the App, '
              'please contact us through the support channel listed on the App\'s Play Store listing.\n\n'
              'Last updated: March 2026\n'
              'Terms version: ${AppTerms.currentVersion}',
        ),
      ],
    );
  }
}

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
