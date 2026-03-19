import 'package:flutter/material.dart';

import '../login_dashboard/login_page.dart';

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage> {
  int _selectedNavIndex = 0;

  final List<_ActionItem> _quickActions = const [
    _ActionItem(
      label: 'SOS',
      icon: Icons.warning_amber_rounded,
      background: Color(0xFFFFF0EF),
      iconWrap: Color(0xFFFFDFDC),
      iconColor: Color(0xFFCB392B),
    ),
    _ActionItem(
      label: 'Location',
      icon: Icons.location_on_outlined,
      background: Color(0xFFEFFAF4),
      iconWrap: Color(0xFFD6F0E2),
      iconColor: Color(0xFF1E7E55),
    ),
    _ActionItem(
      label: 'Walk',
      icon: Icons.directions_walk_outlined,
      background: Color(0xFFFFFAEC),
      iconWrap: Color(0xFFF4ECCD),
      iconColor: Color(0xFF9C7A24),
    ),
    _ActionItem(
      label: 'Device',
      icon: Icons.smartphone_rounded,
      background: Color(0xFFF2F4FF),
      iconWrap: Color(0xFFE1E5FC),
      iconColor: Color(0xFF4156B8),
    ),
  ];

  final List<_ToolItem> _tools = const [
    _ToolItem(
      title: 'Device Connection',
      subtitle: 'Check your linked emergency device',
      icon: Icons.smartphone_rounded,
      iconColor: Color(0xFF1E7E55),
      iconBg: Color(0xFFEAF5EF),
    ),
    _ToolItem(
      title: 'Alert History',
      subtitle: 'Recent alerts and emergency logs',
      icon: Icons.history,
      iconColor: Color(0xFF9C7A24),
      iconBg: Color(0xFFFAF3DF),
    ),
    _ToolItem(
      title: 'Profile',
      subtitle: 'Edit personal information',
      icon: Icons.person_outline,
      iconColor: Color(0xFF4156B8),
      iconBg: Color(0xFFEFF2FF),
    ),
    _ToolItem(
      title: 'Settings',
      subtitle: 'Preferences and account settings',
      icon: Icons.settings_outlined,
      iconColor: Color(0xFF6E6D67),
      iconBg: Color(0xFFF2F1ED),
    ),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem('Home', Icons.home_outlined),
    _NavItem('Map', Icons.map_outlined),
    _NavItem('Walk', Icons.directions_walk_outlined),
    _NavItem('Alerts', Icons.notifications_none_rounded),
    _NavItem('Profile', Icons.person_outline),
  ];

  void _showActionSnack(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label tapped'),
        backgroundColor: AppColors.green,
      ),
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 16),
              _buildRouteCard(),
              const SizedBox(height: 16),
              _buildSectionLabel('QUICK ACTIONS'),
              const SizedBox(height: 10),
              _buildQuickActions(),
              const SizedBox(height: 18),
              _buildSectionLabel('CURRENT SESSION'),
              const SizedBox(height: 10),
              _buildSessionCard(),
              const SizedBox(height: 18),
              _buildSectionLabel('TOOLS'),
              const SizedBox(height: 10),
              _buildToolList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05412B), Color(0xFF042D1F)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD9B255)),
                    ),
                    child: const Center(
                      child: Text(
                        'SW',
                        style: TextStyle(
                          color: Color(0xFFD9B255),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SafeWalk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'STUDENT',
                        style: TextStyle(
                          color: Color(0xFF9DB2A9),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E5B3C),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2D8760)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xFF5DF0A0), size: 8),
                    SizedBox(width: 6),
                    Text(
                      'ONLINE',
                      style: TextStyle(
                        color: Color(0xFF5DF0A0),
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF124733),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFF0F5F2),
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Good morning,',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aria Santos',
            style: TextStyle(
              color: Color(0xFFD9B255),
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(label: 'GPS Active', dotColor: Color(0xFF4ADE80)),
              _StatusPill(label: 'Device Linked', dotColor: Color(0xFFFFD166)),
              _StatusPill(label: 'Safe Mode On', dotColor: Color(0xFF4ADE80)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      height: 168,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F5E3E), Color(0xFF0A3D2A)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CustomPaint(painter: _GridPatternPainter()),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF27AE60),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'SAFE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Center(
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Color(0xFF346349),
              child: CircleAvatar(
                radius: 7,
                backgroundColor: Color(0xFFD9B255),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVE ROUTE',
                        style: TextStyle(
                          color: Color(0xFFE2C77D),
                          fontSize: 18,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Main Campus -> Dorm Block C',
                        style: TextStyle(
                          color: Color(0xFFF8FBF9),
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8B453),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF0B2C1E),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFB6AEA2),
        fontSize: 17,
        letterSpacing: 5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: _quickActions.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => _showActionSnack(item.label),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: item.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: item.iconWrap,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, color: item.iconColor, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSessionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safe Walk Session',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Location sharing is active',
                      style: TextStyle(
                        color: Color(0xFF6E7A73),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFCEE4D9)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Color(0xFF60CC8A)),
                    SizedBox(width: 6),
                    Text(
                      'Active',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.border.withValues(alpha: 0.55), height: 1),
          const SizedBox(height: 13),
          const Row(
            children: [
              Expanded(
                child: _MetricCell(value: 'Campus', label: 'ROUTE'),
              ),
              Expanded(
                child: _MetricCell(value: '16 min', label: 'ELAPSED'),
              ),
              Expanded(
                child: _MetricCell(value: '1.2 km', label: 'DISTANCE'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showActionSnack('View Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'VIEW DETAILS',
                style: TextStyle(
                  fontSize: 21,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolList() {
    return Column(
      children: _tools
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _showActionSnack(item.title),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: item.iconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item.icon, color: item.iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: const TextStyle(
                                color: Color(0xFF6E7A73),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFFB5B2AA)),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final selected = index == _selectedNavIndex;

            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _selectedNavIndex = index);
                  _showActionSnack(item.label);
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE5ECE8)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 21,
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String value;
  final String label;

  const _MetricCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.green,
            fontSize: 33,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFB5AEA1),
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color dotColor;

  const _StatusPill({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF164837),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B6851)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: dotColor, size: 7),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEAF2ED),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const spacing = 24.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), stroke);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ActionItem {
  final String label;
  final IconData icon;
  final Color background;
  final Color iconWrap;
  final Color iconColor;

  const _ActionItem({
    required this.label,
    required this.icon,
    required this.background,
    required this.iconWrap,
    required this.iconColor,
  });
}

class _ToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem(this.label, this.icon);
}
