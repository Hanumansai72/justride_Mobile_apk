import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/help_service.dart';

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen(
      {super.key,
      this.initialCategory,
      this.ticketId,
      this.initialSubject,
      this.helpArticleId});
  final String? initialCategory, ticketId, initialSubject, helpArticleId;
  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _reply = TextEditingController();
  final _errorCode = TextEditingController();
  final _screenshots = <_Screenshot>[];
  SupportTicketModel? _ticket;
  String? _error;
  bool _busy = false,
      _loading = false,
      _diagnosticsConsent = false,
      _screenshotsConsent = false;
  late String _category;
  static const categories = {
    'device_problem': 'Device',
    'connection_issue': 'Connectivity',
    'navigation_issue': 'Navigation',
    'firmware_problem': 'Firmware',
    'account_problem': 'Account',
    'general': 'Other',
    'contact_support': 'General support',
    'feedback': 'Feedback',
  };
  bool get _existing => widget.ticketId != null;
  @override
  void initState() {
    super.initState();
    _category = categories.containsKey(widget.initialCategory)
        ? widget.initialCategory!
        : 'general';
    _subject.text = widget.initialSubject ?? '';
    if (_existing) _load();
  }

  @override
  void dispose() {
    for (final controller in [_subject, _description, _reply, _errorCode]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await BackendService.instance
        .getTicketDetails(_ticket?.id ?? widget.ticketId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success) {
        _ticket = result.data;
      } else {
        _error = result.message;
      }
    });
  }

  void _failure(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _pickScreenshot() async {
    if (_screenshots.length >= 3 || _busy) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final extension = file.name.toLowerCase().split('.').last;
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
        _failure('Choose a JPEG, PNG or WebP screenshot.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _failure('Each screenshot must be 5 MB or smaller.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _screenshots.add(_Screenshot(file.name, bytes,
            extension == 'jpg' ? 'image/jpeg' : 'image/$extension'));
        _error = null;
      });
    } on PlatformException {
      _failure('Unable to open photos. Check photo access and try again.');
    }
  }

  Future<List<String>?> _uploadScreenshots() async {
    final urls = <String>[];
    for (final file in _screenshots) {
      if (file.url == null) {
        final result = await BackendService.instance.uploadSupportScreenshot(
            bytes: file.bytes,
            filename: file.name,
            contentType: file.contentType);
        if (!result.success || result.data?['url'] is! String) {
          _failure(
              'Screenshot upload failed. Your ticket has not been sent. Please retry.');
          return null;
        }
        file.url = result.data!['url'] as String;
      }
      urls.add(file.url!);
    }
    return urls;
  }

  Future<void> _diagnosticPreview() async {
    if (!_diagnosticsConsent) return;
    final report =
        await HelpService.collectDiagnostics(errorCode: _errorCode.text);
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Diagnostic report'),
                content: SingleChildScrollView(
                    child:
                        SelectableText(HelpService.formatDiagnostics(report))),
                actions: [
                  TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                            text: HelpService.formatDiagnostics(report)));
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: const Text('Copy report')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'))
                ]));
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_screenshots.isNotEmpty && !_screenshotsConsent) {
      _failure('Confirm screenshot sharing before sending.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attachments = await _uploadScreenshots();
      if (attachments == null) return;
      final diagnostics = _diagnosticsConsent
          ? await HelpService.collectDiagnostics(errorCode: _errorCode.text)
          : null;
      final result = await BackendService.instance.createSupportTicket(
          subject: _subject.text.trim(),
          message: _description.text.trim(),
          category: _category,
          attachments: attachments,
          helpArticleId: widget.helpArticleId,
          diagnostics: diagnostics);
      if (!mounted) return;
      if (result.success && result.data != null) {
        setState(() {
          _ticket = result.data;
          _screenshots.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ticket saved. Follow replies in My Tickets.')));
      } else {
        _failure(result.message);
      }
    } catch (_) {
      _failure(
          'Unable to send your ticket. Your description is still here; please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReply() async {
    if (_busy || _reply.text.trim().isEmpty || _ticket == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await BackendService.instance
        .sendTicketMessage(ticketId: _ticket!.id, message: _reply.text.trim());
    if (!mounted) return;
    if (result.success) {
      _reply.clear();
      await _load();
    } else {
      _failure(result.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: Text(_ticket == null
                ? 'Create support ticket'
                : _ticket!.ticketNumber),
            actions: [
              if (_ticket != null)
                IconButton(
                    tooltip: 'Refresh replies',
                    onPressed: _busy || _loading ? null : _load,
                    icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: 'My Tickets',
                  onPressed: _busy
                      ? null
                      : () => Navigator.pushNamed(context, '/my-tickets'),
                  icon: const Icon(Icons.confirmation_number_outlined))
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ticket == null && _existing
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? 'Ticket unavailable.'),
                    TextButton(onPressed: _load, child: const Text('Retry'))
                  ]))
                : _ticket != null
                    ? _thread()
                    : _createForm(),
      ));

  Widget _createForm() => Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Tell us what happened.',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Include the error and steps you tried. Never share passwords or OTP codes.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Issue category'),
            items: categories.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged:
                _busy ? null : (value) => setState(() => _category = value!)),
        const SizedBox(height: 16),
        TextFormField(
            controller: _subject,
            enabled: !_busy,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Subject'),
            validator: (value) => (value?.trim().length ?? 0) < 3
                ? 'Enter at least 3 characters.'
                : null),
        const SizedBox(height: 12),
        TextFormField(
            controller: _description,
            enabled: !_busy,
            minLines: 5,
            maxLines: 10,
            maxLength: 6000,
            decoration: const InputDecoration(
                labelText: 'Description', alignLabelWithHint: true),
            validator: (value) => (value?.trim().length ?? 0) < 10
                ? 'Describe the issue in at least 10 characters.'
                : null),
        const SizedBox(height: 12),
        Text('Screenshots (optional)',
            style: Theme.of(context).textTheme.titleMedium),
        const Text(
            'Up to 3 images, 5 MB each. Screenshots use Cloudinary storage and can be viewed by anyone with their link. Remove private information before sharing.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        for (final file in _screenshots)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Image.memory(file.bytes,
                  width: 48, height: 48, fit: BoxFit.cover),
              title:
                  Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                  tooltip: 'Remove screenshot',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _screenshots.remove(file)),
                  icon: const Icon(Icons.close))),
        OutlinedButton.icon(
            onPressed:
                _busy || _screenshots.length >= 3 ? null : _pickScreenshot,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add screenshot')),
        if (_screenshots.isNotEmpty)
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _screenshotsConsent,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _busy
                  ? null
                  : (value) =>
                      setState(() => _screenshotsConsent = value == true),
              title: const Text(
                  'I agree to upload these screenshots for support.',
                  style: TextStyle(fontSize: 13))),
        const SizedBox(height: 16),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _diagnosticsConsent,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _busy
                ? null
                : (value) =>
                    setState(() => _diagnosticsConsent = value == true),
            title: const Text('Include a diagnostic report (optional)',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
                'App version, cached firmware version, platform, and Android phone model/OS when available. No location, passwords or notification contents.',
                style: TextStyle(fontSize: 12))),
        if (_diagnosticsConsent) ...[
          TextField(
              controller: _errorCode,
              enabled: !_busy,
              maxLength: 160,
              decoration:
                  const InputDecoration(labelText: 'Error code (optional)')),
          TextButton.icon(
              onPressed: _busy ? null : _diagnosticPreview,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Preview / copy diagnostic report')),
        ],
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.errorText))),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_outlined),
            label: Text(_busy ? 'Sending ticket…' : 'Send support ticket')),
        const SizedBox(height: 24),
      ]));

  Widget _thread() => RefreshIndicator(
      onRefresh: _load,
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(_ticket!.title,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              Chip(label: Text(_ticket!.status.replaceAll('_', ' '))),
              Chip(
                  label:
                      Text(categories[_ticket!.category] ?? _ticket!.category))
            ]),
            const SizedBox(height: 12),
            if (_ticket!.messages.isEmpty) Text(_ticket!.description),
            for (final message in _ticket!.messages)
              Card(
                  color: message.senderRole == 'USER'
                      ? AppColors.surface
                      : AppColors.surfaceElevated,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                message.senderRole == 'USER'
                                    ? 'You'
                                    : 'JustRide support',
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                message.createdAt
                                    .toLocal()
                                    .toString()
                                    .split('.')
                                    .first,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            SelectableText(message.body),
                            for (final url in message.attachments.where(
                                (url) => Uri.tryParse(url)?.scheme == 'https'))
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Image.network(url,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Text(
                                          'Screenshot unavailable. Pull to refresh and try again.'))),
                          ]))),
            const SizedBox(height: 16),
            TextField(
                controller: _reply,
                enabled: !_busy,
                minLines: 2,
                maxLines: 6,
                maxLength: 6000,
                decoration:
                    const InputDecoration(labelText: 'Reply to support')),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.errorText)),
            FilledButton.icon(
                onPressed: _busy ? null : _sendReply,
                icon: const Icon(Icons.send_outlined),
                label: Text(_busy ? 'Sending…' : 'Send reply')),
            const SizedBox(height: 24),
          ]));
}

class _Screenshot {
  _Screenshot(this.name, this.bytes, this.contentType);
  final String name, contentType;
  final Uint8List bytes;
  String? url;
}
