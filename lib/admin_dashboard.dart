import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'add_device_page.dart';
import 'auth_service.dart';
import 'login_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AuthService _authService = AuthService();

  String _selectedFilter = 'all';
  String _searchText = '';

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('login_logs')
        .orderBy('timestamp', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Row(
                      children: [
                        _buildBrandPanel(),
                        const SizedBox(width: 22),
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _buildHeroHeader(),
                              const SizedBox(height: 18),
                              _buildSummaryRow(),
                              const SizedBox(height: 18),
                              _buildFilterBar(),
                              const SizedBox(height: 18),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _LuxuryPanel(
                                        title: 'LOGIN RECORDS',
                                        child: StreamBuilder<
                                            QuerySnapshot<Map<String, dynamic>>>(
                                          stream: query.snapshots(),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            }

                                            final docs = snapshot.data!.docs
                                                .where((doc) {
                                              final email = (doc.data()['email'] ??
                                                      '')
                                                  .toString()
                                                  .toLowerCase();
                                              return email.contains(
                                                _searchText.toLowerCase(),
                                              );
                                            }).toList();

                                            if (docs.isEmpty) {
                                              return const Center(
                                                child: Text(
                                                  'No login records found.',
                                                  style: TextStyle(
                                                    color: AppColors.textSub,
                                                  ),
                                                ),
                                              );
                                            }

                                            return ListView.separated(
                                              padding: const EdgeInsets.all(16),
                                              itemCount: docs.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 12),
                                              itemBuilder: (context, index) {
                                                final data = docs[index].data();
                                                final status =
                                                    (data['status'] ?? '')
                                                        .toString();
                                                final isSuccess =
                                                    status == 'success';

                                                return Container(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.offWhite,
                                                    border: Border.all(
                                                      color: AppColors.border
                                                          .withOpacity(0.5),
                                                    ),
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color:
                                                            AppColors.shadow,
                                                        blurRadius: 10,
                                                        offset: Offset(0, 4),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        width: 46,
                                                        height: 46,
                                                        decoration:
                                                            BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: isSuccess
                                                              ? Colors.green
                                                                  .shade50
                                                              : Colors.red
                                                                  .shade50,
                                                          border: Border.all(
                                                            color: isSuccess
                                                                ? Colors.green
                                                                    .shade200
                                                                : Colors.red
                                                                    .shade200,
                                                          ),
                                                        ),
                                                        child: Icon(
                                                          isSuccess
                                                              ? Icons.check
                                                              : Icons.close,
                                                          color: isSuccess
                                                              ? Colors.green
                                                              : Colors.red,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              data['email'] ??
                                                                  'No Email',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: AppColors
                                                                    .green,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Wrap(
                                                              spacing: 8,
                                                              runSpacing: 8,
                                                              children: [
                                                                _MiniTag(
                                                                  label:
                                                                      'Role: ${data['role'] ?? 'unknown'}',
                                                                ),
                                                                _MiniTag(
                                                                  label:
                                                                      'Status: ${data['status'] ?? ''}',
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 10),
                                                            Text(
                                                              'Location: ${data['location'] ?? 'Unknown'}',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                color: AppColors
                                                                    .textMain,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 4),
                                                            Text(
                                                              'Device: ${data['deviceId'] ?? 'Unknown'}',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                color: AppColors
                                                                    .textMain,
                                                              ),
                                                            ),
                                                            if ((data['error'] ??
                                                                    '')
                                                                .toString()
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                'Error: ${data['error']}',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .red
                                                                      .shade700,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: _LuxuryPanel(
                                        title: 'REGISTERED DEVICES',
                                        child: StreamBuilder<
                                            QuerySnapshot<Map<String, dynamic>>>(
                                          stream: FirebaseFirestore.instance
                                              .collection('devices')
                                              .orderBy('createdAt',
                                                  descending: true)
                                              .snapshots(),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            }

                                            final docs = snapshot.data!.docs;

                                            if (docs.isEmpty) {
                                              return const Center(
                                                child: Text(
                                                  'No devices found.',
                                                  style: TextStyle(
                                                    color: AppColors.textSub,
                                                  ),
                                                ),
                                              );
                                            }

                                            return ListView.separated(
                                              padding: const EdgeInsets.all(16),
                                              itemCount: docs.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 12),
                                              itemBuilder: (context, index) {
                                                final data = docs[index].data();

                                                return Container(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.offWhite,
                                                    border: Border.all(
                                                      color: AppColors.border
                                                          .withOpacity(0.5),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 42,
                                                            height: 42,
                                                            decoration:
                                                                BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: AppColors
                                                                  .green
                                                                  .withOpacity(
                                                                      0.08),
                                                              border:
                                                                  Border.all(
                                                                color: AppColors
                                                                    .gold,
                                                              ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.memory,
                                                              color: AppColors
                                                                  .green,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              data['deviceName'] ??
                                                                  'No Name',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: AppColors
                                                                    .green,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 14),
                                                      Text(
                                                        'Device ID: ${data['deviceId'] ?? ''}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors
                                                              .textMain,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Phone: ${data['phoneNumber'] ?? ''}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors
                                                              .textMain,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Location: ${data['location'] ?? ''}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors
                                                              .textMain,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Status: ${data['status'] ?? ''}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              (data['status'] ??
                                                                          '') ==
                                                                      'active'
                                                                  ? Colors.green
                                                                      .shade700
                                                                  : AppColors
                                                                      .textSub,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.goldLt,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddDevicePage()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'ADD DEVICE',
          style: TextStyle(letterSpacing: 2),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green,
            border: Border.all(color: AppColors.gold, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withOpacity(0.18),
                blurRadius: 16,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: AppColors.gold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'SAFEWALK ADMIN',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 4,
            color: AppColors.goldDark,
            fontWeight: FontWeight.w400,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () async {
            await _authService.signOut();
            if (!mounted) return;
            Navigator.pop(context);
          },
          icon: const Icon(Icons.logout, color: AppColors.green),
          label: const Text(
            'SIGN OUT',
            style: TextStyle(
              color: AppColors.green,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandPanel() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
        decoration: BoxDecoration(
          color: AppColors.white.withOpacity(0.88),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  height: 1.05,
                  color: AppColors.green,
                ),
                children: [
                  TextSpan(text: 'Safe\n'),
                  TextSpan(
                    text: 'Walk',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppColors.goldDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'ADMIN CONTROL CENTER',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 5,
                color: AppColors.gold.withOpacity(0.9),
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              width: 48,
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gold, Colors.transparent],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'MANAGE LOGIN ACTIVITY,\nFAILED ATTEMPTS,\nAND IOT DEVICES.',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                height: 2,
                color: AppColors.textSub,
                fontWeight: FontWeight.w300,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADMIN FEATURES',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 4,
                      color: AppColors.goldDark,
                    ),
                  ),
                  SizedBox(height: 12),
                  _FeatureText('• Monitor login success and failed attempts'),
                  _FeatureText('• Track registered emergency devices'),
                  _FeatureText('• Filter activity records quickly'),
                  _FeatureText('• Keep the same SafeWalk luxury design'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.gold,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONTROL PANEL',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 5,
                  color: AppColors.gold.withOpacity(0.9),
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome\nAdministrator',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 34,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'View login activity, inspect failed access, and manage SafeWalk devices in one elegant dashboard.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        _LuxurySummaryCard(
          title: 'ALL LOGINS',
          icon: Icons.analytics_outlined,
          stream: FirebaseFirestore.instance.collection('login_logs').snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'SUCCESS',
          icon: Icons.check_circle_outline,
          stream: FirebaseFirestore.instance
              .collection('login_logs')
              .where('status', isEqualTo: 'success')
              .snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'FAILED',
          icon: Icons.cancel_outlined,
          stream: FirebaseFirestore.instance
              .collection('login_logs')
              .where('status', isEqualTo: 'failed')
              .snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'DEVICES',
          icon: Icons.memory_outlined,
          stream: FirebaseFirestore.instance.collection('devices').snapshots(),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _AdminSearchField(
              hint: 'Search email address',
              onChanged: (value) {
                setState(() => _searchText = value);
              },
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: DropdownButton<String>(
              value: _selectedFilter,
              underline: const SizedBox(),
              dropdownColor: AppColors.white,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'success', child: Text('Success')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFilter = value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LuxurySummaryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Stream<QuerySnapshot> stream;

  const _LuxurySummaryCard({
    required this.title,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.green, size: 20),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 4,
                    color: AppColors.gold.withOpacity(0.9),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: AppColors.green,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LuxuryPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _LuxuryPanel({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border.withOpacity(0.5),
                ),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 4,
                color: AppColors.gold.withOpacity(0.9),
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _AdminSearchField({
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textSub),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: AppColors.green),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSub,
        ),
      ),
    );
  }
}

class _FeatureText extends StatelessWidget {
  final String text;

  const _FeatureText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textMain,
          height: 1.6,
        ),
      ),
    );
  }
}

class _AdminBackground extends StatelessWidget {
  const _AdminBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AdminVinesPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _AdminVinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final vine = Paint()
      ..color = AppColors.green.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final leaf = Paint()
      ..color = AppColors.gold.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final left = Path()
      ..moveTo(w * 0.03, h)
      ..cubicTo(w * 0.03, h * 0.80, w * 0.01, h * 0.65, w * 0.05, h * 0.48)
      ..cubicTo(w * 0.08, h * 0.34, w * 0.01, h * 0.18, w * 0.06, 0);

    final right = Path()
      ..moveTo(w * 0.97, h)
      ..cubicTo(w * 0.97, h * 0.82, w * 0.99, h * 0.68, w * 0.94, h * 0.50)
      ..cubicTo(w * 0.90, h * 0.34, w * 0.98, h * 0.18, w * 0.93, 0);

    canvas.drawPath(left, vine);
    canvas.drawPath(right, vine);

    void drawLeaf(Offset center, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx, height: ry),
        leaf,
      );
    }

    drawLeaf(Offset(w * 0.035, h * 0.78), 14, 8);
    drawLeaf(Offset(w * 0.055, h * 0.58), 12, 7);
    drawLeaf(Offset(w * 0.028, h * 0.36), 13, 8);
    drawLeaf(Offset(w * 0.95, h * 0.74), 14, 8);
    drawLeaf(Offset(w * 0.93, h * 0.52), 12, 7);
    drawLeaf(Offset(w * 0.965, h * 0.30), 13, 8);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}