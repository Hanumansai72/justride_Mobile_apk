import '../../../shared/widgets/device_connection_gate.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/services/help_service.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/constants/app_constants.dart';
import 'support_ticket_screen.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, this.initialCategory = 'All'});
  final String initialCategory;
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  late Future<List<HelpArticle>> _articles;
  final _search = TextEditingController();
  late String _category;
  static const categories = [
    'All',
    'Getting started',
    'Connectivity',
    'Navigation',
    'Firmware',
    'Account'
  ];
  @override
  void initState() {
    super.initState();
    _articles = HelpService.loadArticles();
    _category = categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : 'All';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Help Center'), actions: [
          IconButton(
              tooltip: 'My Tickets',
              onPressed: () => Navigator.pushNamed(context, '/my-tickets'),
              icon: const Icon(Icons.confirmation_number_outlined))
        ]),
        body: FutureBuilder<List<HelpArticle>>(
            future: _articles,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: TextButton(
                        onPressed: () => setState(
                            () => _articles = HelpService.loadArticles()),
                        child: const Text('Reload help articles')));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final articles = snapshot.data!
                  .where((article) =>
                      (_category == 'All' || article.category == _category) &&
                      article.matches(_search.text))
                  .toList();
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text('Get back to the ride.',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Find answers, check your connection, and get help.',
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            hintText: 'Search symptoms, errors or keywords',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(_search.clear)))),
                    const SizedBox(height: 14),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categories
                            .map((category) => ChoiceChip(
                                label: Text(category),
                                selected: _category == category,
                                onSelected: (_) =>
                                    setState(() => _category = category)))
                            .toList()),
                    const SizedBox(height: 20),
                    const Row(children: [
                      Icon(Icons.offline_bolt_outlined,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Answers are available offline. Tickets and feedback need internet.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)))
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                        'Stop safely before troubleshooting or changing device settings.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    Text('${articles.length} answers',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    if (articles.isEmpty) ...[
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                              'No matching answers. Try “Bluetooth”, “GPS”, “OTP” or describe the issue in a ticket.')),
                      TextButton(
                          onPressed: () => setState(() {
                                _category = 'All';
                                _search.clear();
                              }),
                          child: const Text('Clear filters')),
                    ],
                    for (final article in articles)
                      _HelpArticleCard(
                          key: ValueKey(article.id), article: article),
                    const SizedBox(height: 24),
                    Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Still need help?',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              const Text(
                                  'Send a description and optional screenshots. Follow staff replies and ticket status in My Tickets.',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      DevicePageRoute(
                                          builder: (_) =>
                                              const SupportTicketScreen())),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create support ticket')),
                              OutlinedButton(
                                  onPressed: () => Navigator.pushNamed(
                                      context, '/my-tickets'),
                                  child: const Text('My Tickets')),
                            ])),
                    TextButton(
                        onPressed: () => showLicensePage(
                            context: context,
                            applicationName: 'JustRide',
                            applicationVersion: AppConstants.appVersion),
                        child: const Text('Third-party notices')),
                  ]);
            }),
      );
}

class _HelpArticleCard extends StatefulWidget {
  const _HelpArticleCard({super.key, required this.article});
  final HelpArticle article;
  @override
  State<_HelpArticleCard> createState() => _HelpArticleCardState();
}

class _HelpArticleCardState extends State<_HelpArticleCard> {
  final _completed = <int>{};
  bool _sending = false;
  bool? _vote;
  Future<void> _feedback(bool helpful) async {
    setState(() => _sending = true);
    final result = await BackendService.instance
        .submitHelpFeedback(widget.article.id, helpful);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.success) _vote = helpful;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success
            ? 'Thank you for your feedback.'
            : 'Feedback could not be sent. Check your connection and try again.')));
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: AppColors.surface,
        child: ExpansionTile(
          key: PageStorageKey(article.id),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(article.question,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Text(article.category,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Try these checks',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))),
            const SizedBox(height: 10),
            LinearProgressIndicator(
                value: _completed.length / article.steps.length),
            for (var i = 0; i < article.steps.length; i++)
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _completed.contains(i),
                  title: Text('${i + 1}. ${article.steps[i]}',
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                  onChanged: (done) => setState(() {
                        if (done == true) {
                          _completed.add(i);
                        } else {
                          _completed.remove(i);
                        }
                      })),
            Wrap(spacing: 8, runSpacing: 4, children: [
              TextButton.icon(
                  onPressed: () => Navigator.pushNamed(context, article.route),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: Text(article.category == 'Account'
                      ? 'Open account screen'
                      : article.category == 'Navigation' ||
                              article.id == 'first-ride' ||
                              article.id == 'destination'
                          ? 'Open navigation'
                          : 'Open device screen')),
              TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      DevicePageRoute(
                          builder: (_) => SupportTicketScreen(
                              initialCategory: article.supportCategory,
                              initialSubject: article.question,
                              helpArticleId: article.id))),
                  child: const Text('Still need help')),
            ]),
            const Divider(),
            const Align(
                alignment: Alignment.centerLeft,
                child:
                    Text('Was this helpful?', style: TextStyle(fontSize: 13))),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: _sending ? null : () => _feedback(true),
                  icon: Icon(
                      _vote == true ? Icons.thumb_up : Icons.thumb_up_outlined,
                      size: 18),
                  label: const Text('Helpful')),
              TextButton.icon(
                  onPressed: _sending ? null : () => _feedback(false),
                  icon: Icon(
                      _vote == false
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined,
                      size: 18),
                  label: const Text('Not helpful')),
            ]),
          ],
        ));
  }
}
