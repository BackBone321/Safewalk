import 'package:flutter/material.dart';
import '../login_dashboard/login_page.dart';

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage> {
  int _selectedNavIndex = 0;

  final List<_QuickAction> quickActions = const [
    _QuickAction('SOS Button', Icons.warning_amber_rounded),
    _QuickAction('Location', Icons.location_on_outlined),
    _QuickAction('Safe Walk', Icons.directions_walk_outlined),
    _QuickAction('Device', Icons.bluetooth_connected_outlined),
  ];

  final List<_MenuAction> menuActions = const [
    _MenuAction(
      title: 'Device Connection Status',
      subtitle: 'Check your emergency device and mobile number link',
      icon: Icons.bluetooth_connected_outlined,
    ),
    _MenuAction(
      title: 'Alert History',
      subtitle: 'See your recent alerts and emergency activities',
      icon: Icons.history_outlined,
    ),
    _MenuAction(
      title: 'Profile',
      subtitle: 'Manage your personal information',
      icon: Icons.person_outline,
    ),
    _MenuAction(
      title: 'Settings',
      subtitle: 'Update app preferences and account settings',
      icon: Icons.settings_outlined,
    ),
  ];

  void _handleTap(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title clicked'),
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
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.green),
        title: const Text(
          'Student Dashboard',
          style: TextStyle(
            color: AppColors.green,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusChips(),
              const SizedBox(height: 18),
              _buildMainCard(),
              const SizedBox(height: 22),
              _buildSectionTitle('Quick Actions'),
              const SizedBox(height: 12),
              _buildQuickActions(),
              const SizedBox(height: 22),
              _buildSectionTitle('Your Tools'),
              const SizedBox(height: 12),
              _buildMenuList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildStatusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: const [
          _StatusChip(
            label: 'Connected',
            icon: Icons.check_circle_outline,
            highlighted: true,
          ),
          SizedBox(width: 10),
          _StatusChip(
            label: 'GPS Active',
            icon: Icons.my_location_outlined,
          ),
          SizedBox(width: 10),
          _StatusChip(
            label: 'Safe Mode',
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.16),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'ACTIVE SESSION',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Safe Walk Session',
            style: TextStyle(
              fontSize: 24,
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start or monitor your walk session, location sharing, and emergency support in one place.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.green.withOpacity(0.75),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _infoMiniCard(
                icon: Icons.route_outlined,
                label: 'Route',
                value: 'Campus',
              ),
              const SizedBox(width: 10),
              _infoMiniCard(
                icon: Icons.access_time_outlined,
                label: 'Time',
                value: '16 min',
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _handleTap('Safe Walk Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'View Details',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoMiniCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.offWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.goldDark),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.green.withOpacity(0.65),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 19,
        color: AppColors.green,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildQuickActions() {
    return GridView.builder(
      shrinkWrap: true,
      itemCount: quickActions.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.18,
      ),
      itemBuilder: (context, index) {
        final item = quickActions[index];
        return InkWell(
          onTap: () => _handleTap(item.title),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    item.icon,
                    color: AppColors.green,
                    size: 24,
                  ),
                ),
                const Spacer(),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Open feature',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.goldDark.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuList() {
    return Column(
      children: menuActions.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _handleTap(item.title),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: AppColors.green,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.green.withOpacity(0.68),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.green,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _BottomNavItemData('Home', Icons.home_filled),
      _BottomNavItemData('Map', Icons.map_outlined),
      _BottomNavItemData('Session', Icons.compare_arrows_rounded),
      _BottomNavItemData('Settings', Icons.settings_outlined),
      _BottomNavItemData('Profile', Icons.person_outline),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = _selectedNavIndex == index;

            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _selectedNavIndex = index);
                  _handleTap(item.label);
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 34,
                        width: 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.gold.withOpacity(0.18)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 20,
                          color: isSelected
                              ? AppColors.green
                              : AppColors.green.withOpacity(0.45),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.green
                              : AppColors.green.withOpacity(0.45),
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

class _QuickAction {
  final String title;
  final IconData icon;

  const _QuickAction(this.title, this.icon);
}

class _MenuAction {
  final String title;
  final String subtitle;
  final IconData icon;

  const _MenuAction({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _BottomNavItemData {
  final String label;
  final IconData icon;

  _BottomNavItemData(this.label, this.icon);
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool highlighted;

  const _StatusChip({
    required this.label,
    required this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.green
            : AppColors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted ? AppColors.white : AppColors.green,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: highlighted ? AppColors.white : AppColors.green,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}