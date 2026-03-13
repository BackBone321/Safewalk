import 'package:flutter/material.dart';
import '../login_dashboard/login_page.dart';

class ParentDashboardPage extends StatelessWidget {
  const ParentDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _DashboardItem('Child Location', Icons.location_searching_outlined),
      _DashboardItem('Emergency Notifications', Icons.notifications_active_outlined),
      _DashboardItem('Connection Status', Icons.link_outlined),
    ];

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.green),
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(color: AppColors.green),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: AppColors.green),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: GridView.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, color: AppColors.green, size: 28),
                    const Spacer(),
                    Text(
                      item.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 3,
                        color: AppColors.gold.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardItem {
  final String title;
  final IconData icon;

  _DashboardItem(this.title, this.icon);
}