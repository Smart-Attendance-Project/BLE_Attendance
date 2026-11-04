import 'package:flutter/material.dart';

import 'offline_attendance_exporter.dart';

enum AttendanceFilter { all, present, absent }

/// Page displaying detailed student records for an offline session with
/// filtering (All, Present, Absent) and XML export.
class OfflineAttendanceDetailsPage extends StatefulWidget {
  final Map<String, dynamic> session;
  final Future<void> Function(Map<String, dynamic> session)? onUpload;

  const OfflineAttendanceDetailsPage({
    super.key,
    required this.session,
    this.onUpload,
  });

  @override
  State<OfflineAttendanceDetailsPage> createState() =>
      _OfflineAttendanceDetailsPageState();
}

class _OfflineAttendanceDetailsPageState
    extends State<OfflineAttendanceDetailsPage> {
  AttendanceFilter _filter = AttendanceFilter.all;
  bool _exporting = false;
  bool _uploading = false;

  List<Map<String, dynamic>> get _allStudents {
    final raw = widget.session['decisions'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        ..sort((a, b) {
          final idA = (a['student_id'] ?? a['id'] ?? '').toString();
          final idB = (b['student_id'] ?? b['id'] ?? '').toString();
          return idA.compareTo(idB);
        });
    }
    return [];
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final list = _allStudents;
    switch (_filter) {
      case AttendanceFilter.present:
        return list.where((s) => s['is_present'] == true).toList();
      case AttendanceFilter.absent:
        return list.where((s) => s['is_present'] != true).toList();
      case AttendanceFilter.all:
        return list;
    }
  }

  int get _presentCount =>
      _allStudents.where((s) => s['is_present'] == true).length;
  int get _absentCount => _allStudents.length - _presentCount;

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'Unknown';
    if (raw.contains('T')) {
      final parts = raw.split('T');
      final date = parts[0];
      final time = parts[1].split('.').first;
      return '$date at $time';
    }
    return raw;
  }

  Future<void> _exportXml() async {
    setState(() => _exporting = true);
    try {
      final exportedFile =
          await OfflineAttendanceExporter.exportAttendanceXml(widget.session);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: Colors.green, size: 48),
          title: const Text('Export Successful'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'XML file has been saved in the BLE_Attendance folder on your device:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  exportedFile.path,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export XML: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _handleUpload() async {
    if (widget.onUpload == null) return;
    setState(() => _uploading = true);
    try {
      await widget.onUpload!(widget.session);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subject = widget.session['subject'] ?? 'Lecture';
    final sessionId = widget.session['sessionId'] ?? '';
    final savedAt = widget.session['savedAt']?.toString();

    final filtered = _filteredStudents;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      appBar: AppBar(
        title: Text(
          '$subject Attendance',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Export button at the top
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Export XML to Phone',
            onPressed: _exporting ? null : _exportXml,
          ),
          // Top right filter menu
          PopupMenuButton<AttendanceFilter>(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter Students',
            initialValue: _filter,
            onSelected: (val) => setState(() => _filter = val),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: AttendanceFilter.all,
                child: Text('All Students'),
              ),
              PopupMenuItem(
                value: AttendanceFilter.present,
                child: Text('Present Only'),
              ),
              PopupMenuItem(
                value: AttendanceFilter.absent,
                child: Text('Absent Only'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Session Header info ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Session: $sessionId',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDateTime(savedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Summary counts
                Row(
                  children: [
                    _buildStatCard(
                      label: 'Total',
                      count: _allStudents.length,
                      color: cs.primary,
                      icon: Icons.people_outline,
                    ),
                    const SizedBox(width: 8),
                    _buildStatCard(
                      label: 'Present',
                      count: _presentCount,
                      color: Colors.green.shade700,
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(width: 8),
                    _buildStatCard(
                      label: 'Absent',
                      count: _absentCount,
                      color: Colors.red.shade700,
                      icon: Icons.cancel_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Top filter segmented tabs
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AttendanceFilter>(
                    segments: [
                      ButtonSegment(
                        value: AttendanceFilter.all,
                        label: Text('All (${_allStudents.length})'),
                      ),
                      ButtonSegment(
                        value: AttendanceFilter.present,
                        label: Text('Present ($_presentCount)'),
                      ),
                      ButtonSegment(
                        value: AttendanceFilter.absent,
                        label: Text('Absent ($_absentCount)'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (val) {
                      setState(() => _filter = val.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Students List ──
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No students match "${_filter.name.toUpperCase()}"',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final studentId =
                          (s['student_id'] ?? s['id'] ?? '').toString();
                      final studentName = s['student_name']?.toString();
                      final isPresent = s['is_present'] == true;
                      final hits = s['hits'] ?? 0;
                      final total = s['total'] ?? 0;
                      final verified = s['verified'] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isPresent
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isPresent
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                child: Icon(
                                  isPresent
                                      ? Icons.check
                                      : Icons.close_rounded,
                                  color: isPresent
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      studentId,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (studentName != null &&
                                        studentName.isNotEmpty &&
                                        studentName != studentId)
                                      Text(
                                        studentName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isPresent
                                          ? Colors.green.shade100
                                          : Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isPresent ? 'Present' : 'Absent',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isPresent
                                          ? Colors.green.shade900
                                          : Colors.red.shade900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        total > 0
                                            ? '$hits / $total hits'
                                            : '$hits hits',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      if (verified) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: Colors.blue,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // ── Bottom Upload Button ──
          if (widget.onUpload != null)
            SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _handleUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _uploading
                          ? 'Uploading...'
                          : 'Upload Attendance to Server',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color.withAlpha(220),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Page displaying all pending offline attendances with the dedicated message,
/// Show and Upload buttons.
class OfflineAttendanceListPage extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  final Future<void> Function(Map<String, dynamic> session) onUpload;
  final Future<void> Function(String sessionId) onDiscard;

  const OfflineAttendanceListPage({
    super.key,
    required this.sessions,
    required this.onUpload,
    required this.onDiscard,
  });

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'Date & Time: Unknown';
    if (raw.contains('T')) {
      final parts = raw.split('T');
      final date = parts[0];
      final time = parts[1].split('.').first;
      return 'Date: $date  •  Time: $time';
    }
    return 'Date/Time: $raw';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F5),
      appBar: AppBar(
        title: const Text(
          'Offline Attendance Sessions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_outlined,
                      size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'All Attendance Uploaded',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No pending offline attendance records found.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final subject = session['subject'] ?? 'Lecture';
                final sessionId = session['sessionId'] ?? '';
                final savedAt = session['savedAt']?.toString();
                final rawDecisions = session['decisions'];
                final count = (rawDecisions is List) ? rawDecisions.length : 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.cloud_off_rounded,
                                color: Colors.orange.shade800,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subject,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Session: $sessionId ($count students)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Date and Time
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatDateTime(savedAt),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Dedicated Message
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Colors.orange.shade900,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You can upload this attendance. Previously it was not stored on the server, but now that your phone is connected to the server, you can send it.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Two main options/buttons: Show and Upload
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          OfflineAttendanceDetailsPage(
                                        session: session,
                                        onUpload: onUpload,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.visibility_outlined,
                                    size: 18),
                                label: const Text('Show'),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  await onUpload(session);
                                },
                                icon: const Icon(Icons.cloud_upload_outlined,
                                    size: 18),
                                label: const Text('Upload'),
                                style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: Colors.orange.shade800,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: Colors.red.shade400, size: 20),
                              tooltip: 'Discard',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Discard offline attendance?'),
                                    content: const Text(
                                      'This session record will be permanently deleted from this device.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await onDiscard(sessionId);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
